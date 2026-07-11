defmodule Eirinchan.BrowserPresence do
  @moduledoc false
  use GenServer
  @table :eirinchan_browser_presence
  @window_seconds 10 * 60
  @touch_interval_seconds 30
  @prune_interval_ms 60_000
  @default_max_entries 50_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # The supervision tree starts this owner before request handling begins.
  def touch(browser_token) when is_binary(browser_token) and byte_size(browser_token) >= 16 do
    now = now_seconds()

    case :ets.lookup(@table, browser_token) do
      [{^browser_token, last_seen_at}] when last_seen_at >= now - @touch_interval_seconds ->
        :ok

      [{^browser_token, _last_seen_at}] ->
        true = :ets.insert(@table, {browser_token, now})
        :ok

      _ ->
        maybe_insert(browser_token, now)
        :ok
    end
  end

  def touch(_browser_token), do: :ok

  def users_10minutes do
    cutoff = now_seconds() - @window_seconds
    :ets.select_count(@table, [
      {{:"$1", :"$2"}, [{:>, :"$2", cutoff}], [true]}
    ])
  end

  @impl true
  def init(_opts) do
    # The table lifecycle follows its owner, so a restarted process begins cleanly.
    :ets.new(@table, [
      :named_table, :public, :set,
      read_concurrency: true,
      write_concurrency: true
    ])
    schedule_prune()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:prune, state) do
    prune_stale()
    schedule_prune()
    {:noreply, state}
  end

  defp prune_stale do
    cutoff = now_seconds() - @window_seconds
    :ets.select_delete(@table, [
      {{:"$1", :"$2"}, [{:<, :"$2", cutoff}], [true]}
    ])
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, @prune_interval_ms)
  defp now_seconds, do: System.system_time(:second)

  defp maybe_insert(browser_token, now) do
    if :ets.info(@table, :size) < max_entries() do
      true = :ets.insert(@table, {browser_token, now})
    end
  end

  defp max_entries do
    case Application.get_env(:eirinchan, :browser_presence_max_entries, @default_max_entries) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_max_entries
    end
  end
end
