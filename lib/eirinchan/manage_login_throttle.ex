defmodule Eirinchan.ManageLoginThrottle do
  @moduledoc false

  use GenServer

  alias Eirinchan.FailureWindow

  @table :eirinchan_manage_login_throttle
  @prune_interval_ms 60_000
  @default_max_entries 50_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def allowed?(username, remote_ip, _config) do
    GenServer.call(
      __MODULE__,
      {:allowed, [username_key(username), user_key(username, remote_ip), ip_key(remote_ip)]}
    )
  end

  def record_failure(username, remote_ip, config) do
    max_attempts = FailureWindow.nonnegative_integer(config, :mod_login_max_attempts, 5)

    username_max_attempts =
      FailureWindow.nonnegative_integer(
        config,
        :mod_login_username_max_attempts,
        max(max_attempts * 2, 10)
      )

    ip_max_attempts =
      FailureWindow.nonnegative_integer(
        config,
        :mod_login_ip_max_attempts,
        max(max_attempts * 4, 20)
      )

    window_seconds = FailureWindow.nonnegative_integer(config, :mod_login_window_seconds, 300)
    lockout_seconds = FailureWindow.nonnegative_integer(config, :mod_login_lockout_seconds, 900)

    limits = [
      {username_key(username), username_max_attempts},
      {user_key(username, remote_ip), max_attempts},
      {ip_key(remote_ip), ip_max_attempts}
    ]

    GenServer.call(__MODULE__, {:failure, limits, window_seconds, lockout_seconds})
  end

  def clear(username, remote_ip) do
    GenServer.call(
      __MODULE__,
      {:clear, [username_key(username), user_key(username, remote_ip), ip_key(remote_ip)]}
    )
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

  defp schedule_prune do
    Process.send_after(self(), :prune, @prune_interval_ms)
  end

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

  defp user_key(username, remote_ip),
    do: {:user, normalize_username(username), normalize_ip(remote_ip)}

  defp username_key(username), do: {:username, normalize_username(username)}
  defp ip_key(remote_ip), do: {:ip, normalize_ip(remote_ip)}

  defp normalize_username(username) when is_binary(username) do
    username |> String.trim() |> String.downcase() |> String.slice(0, 128)
  end

  defp normalize_username(_), do: ""

  defp normalize_ip(remote_ip) when is_tuple(remote_ip), do: :inet.ntoa(remote_ip) |> to_string()
  defp normalize_ip(remote_ip) when is_binary(remote_ip), do: remote_ip
  defp normalize_ip(_), do: "unknown"

  defp now_seconds, do: System.system_time(:second)

  defp max_entries do
    case Application.get_env(:eirinchan, :manage_login_throttle_max_entries, @default_max_entries) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_max_entries
    end
  end
end
