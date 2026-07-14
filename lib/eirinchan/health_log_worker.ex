defmodule Eirinchan.HealthLogWorker do
  @moduledoc false

  use GenServer

  require Logger

  alias Eirinchan.{AccessLog, Repo}

  @default_interval_ms 5 * 60 * 1_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def run_now(server \\ __MODULE__), do: GenServer.call(server, :run, 15_000)

  @impl true
  def init(opts) do
    state = %{
      access_log_server: Keyword.get(opts, :access_log_server, AccessLog),
      interval_ms: Keyword.get(opts, :interval_ms, configured_interval_ms()),
      repo: Keyword.get(opts, :repo, Repo)
    }

    schedule(Keyword.get(opts, :initial_delay_ms, 60_000))
    {:ok, state}
  end

  @impl true
  def handle_call(:run, _from, state), do: {:reply, log_snapshot(state), state}

  @impl true
  def handle_info(:run, state) do
    _ = log_snapshot(state)
    schedule(state.interval_ms)
    {:noreply, state}
  end

  defp log_snapshot(state) do
    {db_latency_us, db_result} =
      :timer.tc(fn -> Ecto.Adapters.SQL.query(state.repo, "SELECT 1", []) end)

    payload = %{
      access_log: access_log_stats(state.access_log_server),
      database: database_status(db_result, db_latency_us),
      process_count: :erlang.system_info(:process_count),
      run_queue: :erlang.statistics(:run_queue),
      uptime_seconds: elem(:erlang.statistics(:wall_clock), 0) |> div(1_000),
      vm_memory_bytes: Map.take(:erlang.memory(), [:atom, :binary, :ets, :processes, :total])
    }

    level = if payload.database.status == "ok", do: :info, else: :error
    Logger.log(level, fn -> "health.snapshot " <> Jason.encode!(payload) end)
    {:ok, payload}
  rescue
    error ->
      Logger.error("health snapshot failed: #{Exception.message(error)}")
      {:error, error}
  end

  defp database_status({:ok, _result}, latency_us) do
    %{latency_ms: Float.round(latency_us / 1_000, 1), status: "ok"}
  end

  defp database_status({:error, reason}, latency_us) do
    %{
      error: reason |> Exception.message() |> String.slice(0, 512),
      latency_ms: Float.round(latency_us / 1_000, 1),
      status: "error"
    }
  end

  defp access_log_stats(server) do
    case AccessLog.stats(server) do
      %{} = stats -> stats
      {:error, reason} -> %{status: to_string(reason)}
    end
  end

  defp configured_interval_ms do
    case Application.get_env(:eirinchan, :health_log_interval_seconds, 300) do
      seconds when is_integer(seconds) and seconds >= 60 -> seconds * 1_000
      _ -> @default_interval_ms
    end
  end

  defp schedule(delay_ms), do: Process.send_after(self(), :run, delay_ms)
end
