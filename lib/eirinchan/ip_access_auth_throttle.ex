defmodule Eirinchan.IpAccessAuthThrottle do
  @moduledoc false

  use GenServer

  alias Eirinchan.FailureWindow
  alias Eirinchan.AuthAdmission

  @table :eirinchan_ip_access_auth_throttle
  @prune_interval_ms 60_000
  @default_max_entries 50_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def allowed?(remote_ip, config) do
    GenServer.call(
      __MODULE__,
      {:allowed, [subnet_key(remote_ip), :global],
       FailureWindow.nonnegative_integer(config, :window_seconds, 300)}
    )
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

  def acquire(remote_ip, config) do
    # The global failure budget is shared, so conservatively serialize this
    # short operation, including its access-grant write, across subnets.
    AuthAdmission.acquire(__MODULE__, [subnet_key(remote_ip), :global], 1, fn ->
      allowed?(remote_ip, config)
    end)
  end

  defdelegate release(lease), to: AuthAdmission

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

  def handle_call({:allowed, keys, window}, _from, state) do
    {:reply, FailureWindow.allowed?(ensure_table(), keys, now_seconds()),
     remember_window(state, window)}
  end

  def handle_call({:failure, limits, window, lockout}, _from, state) do
    result =
      FailureWindow.record(ensure_table(), limits, now_seconds(), window, lockout, max_entries())

    {:reply, result, remember_window(state, window)}
  end

  def handle_call({:clear, keys}, _from, state) do
    Enum.each(keys, &:ets.delete(ensure_table(), &1))
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:prune, state) do
    FailureWindow.prune(ensure_table(), now_seconds(), Map.get(state, :legacy_window))
    schedule_prune()
    {:noreply, state}
  end

  defp remember_window(state, window),
    do: Map.put(state, :legacy_window, max(Map.get(state, :legacy_window, 0), window))

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
