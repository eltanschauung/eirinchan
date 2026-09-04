defmodule Eirinchan.VisitorQualification do
  @moduledoc """
  Qualifies browser identities for aggregate visitor statistics.

  The tracker retains only HMAC-derived client buckets and canonical browser
  references in ETS. Raw addresses and browser headers are never stored. New
  identities must survive a minimum age and must not belong to a client bucket
  that is rapidly rotating identities before they can contribute presence.
  """

  use GenServer

  alias Eirinchan.BrowserIdentity
  alias Eirinchan.CredentialHash
  alias Eirinchan.Settings
  alias Eirinchan.Statistics

  @identity_table :eirinchan_visitor_qualification_identities
  @bucket_table :eirinchan_visitor_qualification_buckets
  @default_minimum_age_seconds 60
  @default_churn_limit 3
  @default_churn_window_seconds 10 * 60
  @retention_seconds 2 * 86_400
  @prune_interval_ms 60_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def client_bucket(address, browser_features)
      when is_binary(address) and is_list(browser_features) do
    normalized_features =
      browser_features
      |> Enum.map(&normalize_feature/1)
      |> Enum.join(<<0>>)

    CredentialHash.fingerprint(
      address <> <<0>> <> normalized_features,
      :visitor_qualification_client,
      43
    )
  end

  def record_issue(browser_ref, client_bucket, issued_at, opts \\ []) do
    now = now_seconds(opts)

    if valid_entry?(browser_ref, client_bucket, issued_at) and tables_available?() do
      entry = {browser_ref, client_bucket, issued_at, :pending}

      if :ets.insert_new(@identity_table, entry) do
        minute = div(issued_at, 60)

        :ets.update_counter(
          @bucket_table,
          {client_bucket, minute},
          {2, 1},
          {{client_bucket, minute}, 0}
        )

        record_metric("visitors.identities.issued", now)
      end
    end

    :ok
  end

  def qualify(browser_ref, issued_at, opts \\ []) do
    now = now_seconds(opts)

    case lookup_identity(browser_ref) do
      {:ok, _stored_bucket, _stored_issued_at, :qualified} ->
        :qualified

      {:ok, _stored_bucket, _stored_issued_at, :excluded_churn} ->
        {:excluded, :identity_churn}

      {:ok, _stored_bucket, _stored_issued_at, :excluded_crawler} ->
        {:excluded, :crawler}

      {:ok, stored_bucket, stored_issued_at, state} ->
        {minimum_age, churn_limit, churn_window} = qualification_config(opts)

        qualify_tracked(
          browser_ref,
          stored_bucket,
          stored_issued_at,
          state,
          now,
          minimum_age,
          churn_limit,
          churn_window
        )

      :missing ->
        {minimum_age, _churn_limit, _churn_window} = qualification_config(opts)
        qualify_untracked(issued_at, now, minimum_age)
    end
  end

  def exclude_crawler(browser_ref, opts \\ []) do
    now = now_seconds(opts)

    if transition(browser_ref, [:pending, :returned_early, :qualified], :excluded_crawler) do
      record_metric("visitors.identities.excluded_crawler", now)
    end

    :ok
  end

  def prune(server \\ __MODULE__), do: GenServer.call(server, :prune)

  def identity_table, do: @identity_table
  def bucket_table, do: @bucket_table

  @impl true
  def init(_opts) do
    create_table(@identity_table, :set)
    create_table(@bucket_table, :set)
    schedule_prune()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:prune, _from, state) do
    prune_expired()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:prune, state) do
    prune_expired()
    schedule_prune()
    {:noreply, state}
  end

  defp qualify_tracked(
         browser_ref,
         bucket,
         issued_at,
         _state,
         now,
         minimum_age,
         churn_limit,
         churn_window
       ) do
    cond do
      now - issued_at < minimum_age ->
        if transition(browser_ref, [:pending], :returned_early) do
          record_metric("visitors.identities.returned_early", now)
        end

        {:pending, :minimum_age}

      churn_limit > 0 and churn_count(bucket, now, churn_window) > churn_limit ->
        if transition(browser_ref, [:pending, :returned_early], :excluded_churn) do
          record_metric("visitors.identities.excluded_churn", now)
        end

        case lookup_identity(browser_ref) do
          {:ok, _bucket, _issued_at, :qualified} -> :qualified
          _other -> {:excluded, :identity_churn}
        end

      true ->
        if transition(browser_ref, [:pending, :returned_early], :qualified) do
          record_metric("visitors.identities.qualified", now)
        end

        case lookup_identity(browser_ref) do
          {:ok, _bucket, _issued_at, :excluded_churn} -> {:excluded, :identity_churn}
          {:ok, _bucket, _issued_at, :excluded_crawler} -> {:excluded, :crawler}
          _other -> :qualified
        end
    end
  end

  defp qualify_untracked(issued_at, now, minimum_age)
       when is_integer(issued_at) and now - issued_at < minimum_age,
       do: {:pending, :minimum_age}

  defp qualify_untracked(_issued_at, _now, _minimum_age), do: :qualified

  defp churn_count(bucket, now, window_seconds) do
    first_minute = div(max(now - window_seconds, 0), 60)
    last_minute = div(now, 60)

    Enum.reduce(first_minute..last_minute, 0, fn minute, total ->
      case :ets.lookup(@bucket_table, {bucket, minute}) do
        [{{^bucket, ^minute}, count}] -> total + count
        _other -> total
      end
    end)
  end

  defp transition(browser_ref, from_states, to_state) do
    if table_available?(@identity_table) do
      Enum.reduce_while(from_states, false, fn from_state, _changed ->
        match_spec = [
          {{browser_ref, :"$1", :"$2", from_state}, [], [{{browser_ref, :"$1", :"$2", to_state}}]}
        ]

        if :ets.select_replace(@identity_table, match_spec) == 1,
          do: {:halt, true},
          else: {:cont, false}
      end)
    else
      false
    end
  end

  defp lookup_identity(browser_ref) do
    if table_available?(@identity_table) do
      case :ets.lookup(@identity_table, browser_ref) do
        [{^browser_ref, bucket, issued_at, state}] -> {:ok, bucket, issued_at, state}
        _other -> :missing
      end
    else
      :missing
    end
  end

  defp record_metric(metric, now) do
    now
    |> DateTime.from_unix!(:second)
    |> then(&Statistics.record_metrics([metric], &1))
  end

  defp valid_entry?(browser_ref, client_bucket, issued_at) do
    BrowserIdentity.reference?(browser_ref) and is_binary(client_bucket) and
      byte_size(client_bucket) == 43 and is_integer(issued_at) and issued_at >= 0
  end

  defp normalize_feature(feature) when is_binary(feature) do
    if String.valid?(feature) do
      feature
      |> String.trim()
      |> String.downcase()
      |> String.slice(0, 512)
    else
      binary_part(feature, 0, min(byte_size(feature), 512))
    end
  end

  defp normalize_feature(nil), do: ""
  defp normalize_feature(feature), do: feature |> to_string() |> normalize_feature()

  defp qualification_config(opts) do
    config = Keyword.get_lazy(opts, :config, &Settings.effective_instance_config/0)

    minimum_age =
      configured_non_negative(
        config,
        :visitor_minimum_age_seconds,
        @default_minimum_age_seconds,
        86_400
      )

    churn_limit =
      configured_non_negative(
        config,
        :visitor_identity_churn_limit,
        @default_churn_limit,
        1_000
      )

    churn_window =
      configured_positive(
        config,
        :visitor_identity_churn_window_seconds,
        @default_churn_window_seconds,
        86_400
      )

    {minimum_age, churn_limit, churn_window}
  end

  defp configured_non_negative(config, key, default, maximum) do
    case Map.get(config, key, default) do
      value when is_integer(value) and value >= 0 -> min(value, maximum)
      _other -> default
    end
  end

  defp configured_positive(config, key, default, maximum) do
    case Map.get(config, key, default) do
      value when is_integer(value) and value > 0 -> min(value, maximum)
      _other -> default
    end
  end

  defp now_seconds(opts) do
    case Keyword.get(opts, :now) do
      now when is_integer(now) -> now
      %DateTime{} = now -> DateTime.to_unix(now, :second)
      now when is_function(now, 0) -> now.() |> normalize_now()
      _other -> System.system_time(:second)
    end
  end

  defp normalize_now(%DateTime{} = now), do: DateTime.to_unix(now, :second)
  defp normalize_now(now) when is_integer(now), do: now

  defp create_table(name, type) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [
          :named_table,
          :public,
          type,
          read_concurrency: true,
          write_concurrency: true
        ])

      table ->
        table
    end
  end

  defp tables_available?,
    do: table_available?(@identity_table) and table_available?(@bucket_table)

  defp table_available?(table), do: :ets.whereis(table) != :undefined

  defp prune_expired do
    cutoff = System.system_time(:second) - @retention_seconds
    cutoff_minute = div(cutoff, 60)

    if tables_available?() do
      :ets.select_delete(@identity_table, [
        {{:"$1", :"$2", :"$3", :"$4"}, [{:<, :"$3", cutoff}], [true]}
      ])

      :ets.select_delete(@bucket_table, [
        {{{:"$1", :"$2"}, :"$3"}, [{:<, :"$2", cutoff_minute}], [true]}
      ])
    end

    :ok
  end

  defp schedule_prune do
    Process.send_after(self(), :prune, @prune_interval_ms)
  end
end
