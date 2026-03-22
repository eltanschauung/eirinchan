defmodule Eirinchan.BrowserPresence do
  @moduledoc false
  use GenServer
  @table :eirinchan_browser_presence
  @window_seconds 10 * 60
  @touch_interval_seconds 30
  @prune_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Public API: no ensure_table — table must already exist (owned by GenServer)
  def touch(browser_token) when is_binary(browser_token) and byte_size(browser_token) >= 16 do
    now = now_seconds()
    case :ets.lookup(@table, browser_token) do
      [{^browser_token, last_seen_at}] when last_seen_at >= now - @touch_interval_seconds ->
        :ok
      _ ->
        true = :ets.insert(@table, {browser_token, now})
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
    # GenServer owns the table — it dies when the GenServer dies, restarts with it
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
end