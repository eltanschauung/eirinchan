defmodule Eirinchan.IpAccessAuthThrottle do
  @moduledoc false

  use GenServer

  alias Eirinchan.FailureWindow

  @table :eirinchan_ip_access_auth_throttle
  @prune_interval_ms 60_000
  @default_max_entries 50_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def allowed?(remote_ip, _config) do
    GenServer.call(__MODULE__, {:allowed, [subnet_key(remote_ip), :global]})
  end

  def record_failure(remote_ip, config) do
    window_seconds = FailureWindow.nonnegative_integer(config, :window_seconds, 300)
    lockout_seconds = FailureWindow.nonnegative_integer(config, :lockout_seconds, 900)

    limits = [
      {subnet_key(remote_ip), FailureWindow.nonnegative_integer(config, :max_attempts, 5)},
      {:global, FailureWindow.nonnegative_integer(config, :global_max_attempts, 100)}
    ]

    GenServer.call(__MODULE__, {:failure, limits, window_seconds, lockout_seconds})
  end

  def clear(remote_ip) do
    GenServer.call(__MODULE__, {:clear, [subnet_key(remote_ip)]})
  end

  @impl true
  def init(_opts) do
    ensure_table()
    schedule_prune()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:allowed, keys}, _from, state) do
    {:reply, FailureWindow.allowed?(ensure_table(), keys, now_seconds()), state}
  end

  def handle_call({:failure, limits, window, lockout}, _from, state) do
    result =
      FailureWindow.record(ensure_table(), limits, now_seconds(), window, lockout, max_entries())

    {:reply, result, state}
  end

  def handle_call({:clear, keys}, _from, state) do
    Enum.each(keys, &:ets.delete(ensure_table(), &1))
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:prune, state) do
    prune_stale()
    schedule_prune()
    {:noreply, state}
  end

  defp prune_stale do
    FailureWindow.prune(ensure_table(), now_seconds())
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, @prune_interval_ms)

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
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

  defp subnet_key(remote_ip) do
    case Eirinchan.IpAccessAuth.subnet_for_ip(remote_ip) do
      {:ok, subnet} -> {:subnet, subnet}
      _ -> {:subnet, "unknown"}
    end
  end

  defp max_entries do
    case Application.get_env(
           :eirinchan,
           :ip_access_auth_throttle_max_entries,
           @default_max_entries
         ) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_max_entries
    end
  end

  defp now_seconds, do: System.system_time(:second)
end
