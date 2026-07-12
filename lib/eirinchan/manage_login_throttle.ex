defmodule Eirinchan.ManageLoginThrottle do
  @moduledoc false

  use GenServer

  @table :eirinchan_manage_login_throttle
  @prune_interval_ms 60_000
  @default_max_entries 50_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def allowed?(username, remote_ip, _config) do
    table = ensure_table()
    now = now_seconds()

    [username_key(username), user_key(username, remote_ip), ip_key(remote_ip)]
    |> Enum.map(&locked_retry_after(table, &1, now))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> :ok
      retry_after -> {:error, Enum.max(retry_after)}
    end
  end

  def record_failure(username, remote_ip, config) do
    table = ensure_table()
    now = now_seconds()
    max_attempts = Map.get(config, :mod_login_max_attempts, 5)
    username_max_attempts =
      Map.get(config, :mod_login_username_max_attempts, max(max_attempts * 2, 10))

    ip_max_attempts = Map.get(config, :mod_login_ip_max_attempts, max(max_attempts * 4, 20))
    window_seconds = Map.get(config, :mod_login_window_seconds, 300)
    lockout_seconds = Map.get(config, :mod_login_lockout_seconds, 900)

    [
      record_key_failure(
        table,
        username_key(username),
        now,
        username_max_attempts,
        window_seconds,
        lockout_seconds
      ),
      record_key_failure(
        table,
        user_key(username, remote_ip),
        now,
        max_attempts,
        window_seconds,
        lockout_seconds
      ),
      record_key_failure(
        table,
        ip_key(remote_ip),
        now,
        ip_max_attempts,
        window_seconds,
        lockout_seconds
      )
    ]
    |> Enum.flat_map(fn
      {:error, retry_after} -> [retry_after]
      :ok -> []
    end)
    |> case do
      [] -> :ok
      retry_after -> {:error, Enum.max(retry_after)}
    end
  end

  defp record_key_failure(table, key, now, max_attempts, window_seconds, lockout_seconds) do
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
        if :ets.info(table, :size) < max_entries() do
          put_attempt(table, key, 1, now, 0)
          :ok
        else
          {:error, lockout_seconds}
        end
    end
  end

  def clear(username, remote_ip) do
    table = ensure_table()
    :ets.delete(table, username_key(username))
    :ets.delete(table, user_key(username, remote_ip))
    :ets.delete(table, ip_key(remote_ip))
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

  defp user_key(username, remote_ip), do: {:user, normalize_username(username), normalize_ip(remote_ip)}
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

  defp locked_retry_after(table, key, now) do
    case :ets.lookup(table, key) do
      [{^key, _count, _window_started_at, locked_until}] when locked_until > now ->
        max(locked_until - now, 1)

      _ ->
        nil
    end
  end

  defp max_entries do
    case Application.get_env(:eirinchan, :manage_login_throttle_max_entries, @default_max_entries) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_max_entries
    end
  end
end
