defmodule Eirinchan.ManageLoginThrottle do
  @moduledoc false

  use GenServer

  @table :eirinchan_manage_login_throttle
  @prune_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def allowed?(username, remote_ip, _config) do
    table = ensure_table()
    now = now_seconds()
    key = throttle_key(username, remote_ip)

    case :ets.lookup(table, key) do
      [{^key, _count, _window_started_at, locked_until}] when locked_until > now ->
        {:error, max(locked_until - now, 1)}

      _ ->
        :ok
    end
  end

  def record_failure(username, remote_ip, config) do
    table = ensure_table()
    now = now_seconds()
    key = throttle_key(username, remote_ip)
    max_attempts = Map.get(config, :mod_login_max_attempts, 5)
    window_seconds = Map.get(config, :mod_login_window_seconds, 300)
    lockout_seconds = Map.get(config, :mod_login_lockout_seconds, 900)

    case :ets.lookup(table, key) do
      [{^key, count, window_started_at, locked_until}] ->
        cond do
          locked_until > now ->
            {:error, max(locked_until - now, 1)}

          now - window_started_at >= window_seconds ->
            put_attempt(table, key, 1, now, 0)
            :ok

          count + 1 >= max_attempts ->
            put_attempt(table, key, count + 1, window_started_at, now + lockout_seconds)
            {:error, lockout_seconds}

          true ->
            put_attempt(table, key, count + 1, window_started_at, 0)
            :ok
        end

      [] ->
        put_attempt(table, key, 1, now, 0)
        :ok
    end
  end

  def clear(username, remote_ip) do
    :ets.delete(ensure_table(), throttle_key(username, remote_ip))
    :ok
  end

  @impl true
  def init(_opts) do
    ensure_table()
    schedule_prune()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:prune, state) do
    prune_stale()
    schedule_prune()
    {:noreply, state}
  end

  defp put_attempt(table, key, count, window_started_at, locked_until) do
    true = :ets.insert(table, {key, count, window_started_at, locked_until})
  end

  defp prune_stale do
    table = ensure_table()
    now = now_seconds()

    :ets.select_delete(table, [
      {{:"$1", :"$2", :"$3", :"$4"}, [{:<, :"$4", now}, {:<, {:+, :"$3", 3600}, now}], [true]}
    ])
  end

  defp schedule_prune do
    Process.send_after(self(), :prune, @prune_interval_ms)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])

      table ->
        table
    end
  end

  defp throttle_key(username, remote_ip) do
    {normalize_username(username), normalize_ip(remote_ip)}
  end

  defp normalize_username(username) when is_binary(username), do: username |> String.trim() |> String.downcase()
  defp normalize_username(_), do: ""

  defp normalize_ip(remote_ip) when is_tuple(remote_ip), do: :inet.ntoa(remote_ip) |> to_string()
  defp normalize_ip(remote_ip) when is_binary(remote_ip), do: remote_ip
  defp normalize_ip(_), do: "unknown"

  defp now_seconds, do: System.system_time(:second)
end
