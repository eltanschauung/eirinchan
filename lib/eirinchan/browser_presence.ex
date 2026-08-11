defmodule Eirinchan.BrowserPresence do
  @moduledoc false

  use GenServer

  import Ecto.Query

  require Logger

  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Repo

  @table :eirinchan_browser_presence
  @dirty_table :eirinchan_browser_presence_dirty
  @window_seconds 10 * 60
  @touch_interval_seconds 30
  @prune_interval_ms 60_000
  @default_flush_interval_ms 5_000
  @default_max_entries 50_000

  @persist_sql """
  UPDATE browser_identities AS identities
  SET presence_seen_at = timezone('UTC', to_timestamp(touches.seen_at))
  FROM unnest($1::text[], $2::bigint[]) AS touches(browser_ref, seen_at)
  WHERE identities.browser_ref = touches.browser_ref
    AND (
      identities.presence_seen_at IS NULL OR
      identities.presence_seen_at < timezone('UTC', to_timestamp(touches.seen_at))
    )
  """

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Request processes update ETS only. The owner periodically persists a
  # de-duplicated batch so presence survives releases without a write per hit.
  def touch(browser_ref) when is_binary(browser_ref) do
    if BrowserIdentity.reference?(browser_ref), do: do_touch(browser_ref)
    :ok
  end

  def touch(_browser_ref), do: :ok

  defp do_touch(browser_ref) do
    now = now_seconds()

    case :ets.lookup(@table, browser_ref) do
      [{^browser_ref, last_seen_at}] when last_seen_at >= now - @touch_interval_seconds ->
        :ok

      [{^browser_ref, _last_seen_at}] ->
        record_touch(browser_ref, now)

      _other ->
        maybe_insert(browser_ref, now)
    end
  end

  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, 30_000)
  end

  def active_browsers_10minutes(opts \\ []) do
    active_browsers(@window_seconds, opts)
  end

  def active_browsers(window_seconds, opts \\ [])
      when is_integer(window_seconds) and window_seconds > 0 do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)
    server = Keyword.get(opts, :server, __MODULE__)
    cutoff = DateTime.add(now, -window_seconds, :second)

    _ = flush(server)

    repo.aggregate(
      from(identity in Identity, where: identity.presence_seen_at > ^cutoff),
      :count,
      :browser_ref
    ) || 0
  end

  def users_10minutes(opts \\ []), do: active_browsers_10minutes(opts)

  @impl true
  def init(opts) do
    create_table(@table)
    create_table(@dirty_table)

    state = %{
      repo: Keyword.get(opts, :repo, Repo),
      flush_interval_ms:
        Keyword.get_lazy(opts, :flush_interval_ms, fn ->
          Application.get_env(
            :eirinchan,
            :browser_presence_flush_interval_ms,
            @default_flush_interval_ms
          )
        end)
    }

    schedule_prune()
    schedule_flush(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, persist_dirty(state.repo), state}
  end

  @impl true
  def handle_info(:prune, state) do
    prune_stale()
    schedule_prune()
    {:noreply, state}
  end

  def handle_info(:flush, state) do
    _ = persist_dirty(state.repo)
    schedule_flush(state)
    {:noreply, state}
  end

  defp create_table(name) do
    :ets.new(name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  defp record_touch(browser_ref, now) do
    put_max(@table, browser_ref, now)
    put_max(@dirty_table, browser_ref, now)
  end

  defp maybe_insert(browser_ref, now) do
    if :ets.insert_new(@table, {browser_ref, now}) do
      if :ets.info(@table, :size) <= max_entries() do
        put_max(@dirty_table, browser_ref, now)
      else
        :ets.delete(@table, browser_ref)
      end
    else
      record_touch(browser_ref, now)
    end
  end

  defp put_max(table, browser_ref, seen_at) do
    case :ets.lookup(table, browser_ref) do
      [] ->
        if :ets.insert_new(table, {browser_ref, seen_at}) do
          :ok
        else
          put_max(table, browser_ref, seen_at)
        end

      [{^browser_ref, current_seen_at}] when current_seen_at >= seen_at ->
        :ok

      [{^browser_ref, current_seen_at}] ->
        match_spec = [{{browser_ref, current_seen_at}, [], [{{browser_ref, seen_at}}]}]

        if :ets.select_replace(table, match_spec) == 1 do
          :ok
        else
          put_max(table, browser_ref, seen_at)
        end
    end
  end

  defp persist_dirty(repo) do
    repo
    |> persist_entries(drain_dirty())
  end

  defp persist_entries(_repo, []), do: :ok

  defp persist_entries(repo, entries) do
    {references, seen_at} = Enum.unzip(entries)

    case repo.query(@persist_sql, [references, seen_at]) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        requeue(entries)
        Logger.error("browser presence persistence failed: #{error_message(error)}")
        {:error, error}
    end
  rescue
    error ->
      requeue(entries)
      Logger.error("browser presence persistence failed: #{error_message(error)}")
      {:error, error}
  end

  defp drain_dirty do
    @dirty_table
    |> :ets.tab2list()
    |> Enum.flat_map(fn {browser_ref, _seen_at} ->
      :ets.take(@dirty_table, browser_ref)
    end)
  end

  defp requeue(entries) do
    Enum.each(entries, fn {browser_ref, seen_at} ->
      put_max(@dirty_table, browser_ref, seen_at)
    end)
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(_error), do: "unknown database error"

  defp prune_stale do
    cutoff = now_seconds() - @window_seconds

    :ets.select_delete(@table, [
      {{:"$1", :"$2"}, [{:<, :"$2", cutoff}], [true]}
    ])
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, @prune_interval_ms)

  defp schedule_flush(%{flush_interval_ms: interval})
       when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :flush, interval)
  end

  defp schedule_flush(_state), do: :ok

  defp now_seconds, do: System.system_time(:second)

  defp max_entries do
    case Application.get_env(:eirinchan, :browser_presence_max_entries, @default_max_entries) do
      value when is_integer(value) and value > 0 -> value
      _other -> @default_max_entries
    end
  end
end
