defmodule Eirinchan.Statistics.Worker do
  @moduledoc false

  use GenServer

  require Logger

  alias Eirinchan.Statistics
  alias Eirinchan.Statistics.Store

  @default_flush_interval_ms 60_000
  @snapshot_grace_ms 5_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def flush(server \\ __MODULE__), do: GenServer.call(server, :flush, 30_000)

  def finalize(period_end), do: finalize(__MODULE__, period_end)

  def finalize(server, period_end) do
    GenServer.call(server, {:finalize, period_end}, 30_000)
  end

  @impl true
  def init(opts) do
    Statistics.create_counter_table()
    Statistics.create_search_term_table()

    state = %{
      repo: Keyword.get(opts, :repo, Eirinchan.Repo),
      presence_server: Keyword.get(opts, :presence_server, Eirinchan.BrowserPresence),
      enabled?: Keyword.get(opts, :enabled?, &Statistics.enabled?/0),
      now: Keyword.get(opts, :now, fn -> DateTime.utc_now(:second) end),
      local_hour: Keyword.get(opts, :local_hour, &local_hour/1),
      flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
      schedule_snapshots?: Keyword.get(opts, :schedule_snapshots?, true)
    }

    schedule_flush(state)
    schedule_snapshot(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, flush_counters(state), state}
  end

  def handle_call({:finalize, period_end}, _from, state) do
    {:reply, finalize_period(state, period_end), state}
  end

  @impl true
  def handle_info(:flush, state) do
    _ = flush_counters(state)
    schedule_flush(state)
    {:noreply, state}
  end

  def handle_info(:snapshot, state) do
    now = state.now.()
    period_end = Statistics.hour_start(now)
    _ = finalize_period(state, period_end)
    schedule_snapshot(state)
    {:noreply, state}
  end

  defp finalize_period(state, period_end) do
    with :ok <- flush_counters(state),
         true <- state.enabled?.(),
         {:ok, _snapshot} <-
           Store.finalize(period_end,
             repo: state.repo,
             captured_at: state.now.(),
             daily?: state.local_hour.(period_end) == 0,
             presence_server: state.presence_server
           ) do
      :ok
    else
      false ->
        :disabled

      {:error, reason} = error ->
        Logger.error("statistics snapshot failed: #{error_message(reason)}")
        error
    end
  end

  defp flush_counters(state) do
    counters_by_bucket = Statistics.drain_counters()
    terms_by_bucket = Statistics.drain_search_terms()

    buckets =
      counters_by_bucket
      |> Map.keys()
      |> Kernel.++(Map.keys(terms_by_bucket))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.reduce(buckets, :ok, fn bucket, result ->
      counters = Map.get(counters_by_bucket, bucket, %{})
      terms = Map.get(terms_by_bucket, bucket, %{})

      case Store.add_batch(bucket, counters, terms, repo: state.repo) do
        {:ok, :ok} ->
          result

        {:error, reason} ->
          Statistics.restore_counters(bucket, counters)
          Statistics.restore_search_terms(bucket, terms)
          if result == :ok, do: {:error, reason}, else: result
      end
    end)
  end

  defp schedule_flush(%{flush_interval_ms: interval})
       when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :flush, interval)
  end

  defp schedule_flush(_state), do: :ok

  defp schedule_snapshot(%{schedule_snapshots?: true} = state) do
    now_ms = state.now.() |> DateTime.to_unix(:millisecond)
    next_hour_ms = (div(now_ms, 3_600_000) + 1) * 3_600_000 + @snapshot_grace_ms
    Process.send_after(self(), :snapshot, max(next_hour_ms - now_ms, 1))
  end

  defp schedule_snapshot(_state), do: :ok

  defp local_hour(datetime) do
    datetime
    |> DateTime.to_unix(:second)
    |> :calendar.system_time_to_local_time(:second)
    |> elem(1)
    |> elem(0)
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(_reason), do: "unknown persistence error"
end
