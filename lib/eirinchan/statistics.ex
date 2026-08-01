defmodule Eirinchan.Statistics do
  @moduledoc """
  Collects bounded, privacy-preserving site counters for hourly snapshots.

  Request processes only update ETS. Persistence is batched by the snapshot
  worker so statistics never add a database write to the request path.
  """

  alias Eirinchan.Settings
  alias Eirinchan.Statistics.RequestClassifier
  alias Eirinchan.Statistics.Store

  @counter_table :eirinchan_statistics_counters
  @search_term_table :eirinchan_statistics_search_terms
  @metric_pattern ~r/\A[a-z0-9_.-]{1,160}\z/
  @search_term_fields ~w(text thread post_id subject username tripcode email uid country filename image_hash width height start_date end_date)
  @search_term_max_length 256
  @rate_limit_actions ~w(catalog_search delete feedback ip_access_auth manage_login post report search watcher)

  def enabled? do
    Map.get(Settings.current_instance_config(), :statistics_snapshots, true) != false
  end

  def latest_daily_board_ppd(opts \\ []), do: Store.latest_daily_board_ppd(opts)

  def record_request(%Plug.Conn{} = conn, opts \\ []) do
    if Keyword.get(opts, :enabled?, enabled?()) do
      now = Keyword.get(opts, :now, DateTime.utc_now(:second))
      record_metrics(RequestClassifier.metrics(conn), now)
    end

    :ok
  end

  def mark_rate_limited(%Plug.Conn{} = conn, action) when is_atom(action) do
    mark_rate_limited(conn, Atom.to_string(action))
  end

  def mark_rate_limited(%Plug.Conn{} = conn, action) when action in @rate_limit_actions do
    Plug.Conn.put_private(conn, :statistics_rate_limit, action)
  end

  def mark_rate_limited(%Plug.Conn{} = conn, _action), do: conn

  def record_metrics(metrics, %DateTime{} = now) when is_list(metrics) do
    if :ets.whereis(@counter_table) != :undefined do
      bucket = hour_start_unix(now)

      metrics
      |> Enum.filter(&valid_metric?/1)
      |> Enum.uniq()
      |> Enum.each(fn metric ->
        :ets.update_counter(@counter_table, {bucket, metric}, {2, 1}, {{bucket, metric}, 0})
      end)
    end

    :ok
  end

  def record_search_terms(terms, %DateTime{} = now) when is_list(terms) do
    if :ets.whereis(@search_term_table) != :undefined do
      bucket = hour_start_unix(now)

      terms
      |> Enum.map(&normalize_search_term/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.each(fn {field, term} ->
        key = {bucket, field, term}
        :ets.update_counter(@search_term_table, key, {2, 1}, {key, 0})
      end)
    end

    :ok
  end

  def drain_counters do
    if :ets.whereis(@counter_table) == :undefined do
      %{}
    else
      @counter_table
      |> :ets.tab2list()
      |> Enum.reduce(%{}, fn {{bucket, metric} = key, _count}, drained ->
        case :ets.take(@counter_table, key) do
          [{^key, count}] ->
            update_in(drained, [Access.key(bucket, %{}), Access.key(metric, 0)], &(&1 + count))

          [] ->
            drained
        end
      end)
    end
  end

  def restore_counters(bucket, counters) when is_integer(bucket) and is_map(counters) do
    if :ets.whereis(@counter_table) != :undefined do
      Enum.each(counters, fn {metric, count} ->
        if valid_metric?(metric) and is_integer(count) and count > 0 do
          :ets.update_counter(
            @counter_table,
            {bucket, metric},
            {2, count},
            {{bucket, metric}, 0}
          )
        end
      end)
    end

    :ok
  end

  def drain_search_terms do
    if :ets.whereis(@search_term_table) == :undefined do
      %{}
    else
      @search_term_table
      |> :ets.tab2list()
      |> Enum.reduce(%{}, fn {{bucket, field, term} = key, _count}, drained ->
        case :ets.take(@search_term_table, key) do
          [{^key, count}] ->
            update_in(
              drained,
              [Access.key(bucket, %{}), Access.key({field, term}, 0)],
              &(&1 + count)
            )

          [] ->
            drained
        end
      end)
    end
  end

  def restore_search_terms(bucket, terms) when is_integer(bucket) and is_map(terms) do
    if :ets.whereis(@search_term_table) != :undefined do
      Enum.each(terms, fn {term_entry, count} ->
        if normalized = normalize_search_term(term_entry) do
          if is_integer(count) and count > 0 do
            {field, term} = normalized
            key = {bucket, field, term}
            :ets.update_counter(@search_term_table, key, {2, count}, {key, 0})
          end
        end
      end)
    end

    :ok
  end

  def create_counter_table do
    case :ets.whereis(@counter_table) do
      :undefined ->
        :ets.new(@counter_table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      table ->
        table
    end
  end

  def create_search_term_table do
    case :ets.whereis(@search_term_table) do
      :undefined ->
        :ets.new(@search_term_table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      table ->
        table
    end
  end

  def hour_start(%DateTime{} = datetime) do
    datetime
    |> hour_start_unix()
    |> DateTime.from_unix!(:second)
  end

  def hour_start_unix(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_unix(:second)
    |> then(&(div(&1, 3_600) * 3_600))
  end

  def counter_table, do: @counter_table
  def search_term_table, do: @search_term_table

  defp valid_metric?(metric), do: is_binary(metric) and Regex.match?(@metric_pattern, metric)

  defp normalize_search_term({field, term}) when is_atom(field),
    do: normalize_search_term({Atom.to_string(field), term})

  defp normalize_search_term({field, term})
       when field in @search_term_fields and is_binary(term) do
    normalized =
      term
      |> String.trim()
      |> String.slice(0, @search_term_max_length)

    if normalized == "", do: nil, else: {field, normalized}
  end

  defp normalize_search_term(_term), do: nil
end
