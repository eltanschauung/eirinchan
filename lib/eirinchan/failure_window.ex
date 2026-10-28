defmodule Eirinchan.FailureWindow do
  @moduledoc false

  # Called only by the owning throttle process, so lookup/update and capacity
  # decisions are serialized. Password verification stays outside that process.
  def allowed?(table, keys, now) do
    keys
    |> Enum.flat_map(fn key ->
      case :ets.lookup(table, key) do
        [{^key, _count, _started, locked_until, _expires}] when locked_until > now ->
          [max(locked_until - now, 1)]

        [{^key, _count, _started, locked_until}] when locked_until > now ->
          [max(locked_until - now, 1)]

        _ ->
          []
      end
    end)
    |> result()
  end

  def record(table, limits, now, window_seconds, lockout_seconds, max_entries) do
    limits
    |> Enum.flat_map(fn {key, max_attempts} ->
      case record_key(table, key, now, max_attempts, window_seconds, lockout_seconds, max_entries) do
        {:error, retry_after} -> [retry_after]
        :ok -> []
      end
    end)
    |> result()
  end

  def prune(table, now) do
    :ets.select_delete(table, [
      {{:"$1", :"$2", :"$3", :"$4", :"$5"}, [{:"=<", :"$5", now}], [true]}
    ])
  end

  defp record_key(table, key, now, max_attempts, window, lockout, max_entries) do
    case :ets.lookup(table, key) do
      [{^key, count, started, locked_until, _expires}] ->
        update_existing(
          table,
          key,
          count,
          started,
          locked_until,
          now,
          max_attempts,
          window,
          lockout
        )

      [{^key, count, started, locked_until}] ->
        update_existing(
          table,
          key,
          count,
          started,
          locked_until,
          now,
          max_attempts,
          window,
          lockout
        )

      [] ->
        if :ets.info(table, :size) < max_entries do
          put_failure(table, key, 1, now, now, max_attempts, window, lockout)
        else
          {:error, lockout}
        end
    end
  end

  defp update_existing(
         table,
         key,
         count,
         started,
         locked_until,
         now,
         max_attempts,
         window,
         lockout
       ) do
    cond do
      locked_until > now ->
        {:error, max(locked_until - now, 1)}

      now - started >= window ->
        put_failure(table, key, 1, now, now, max_attempts, window, lockout)

      true ->
        put_failure(table, key, count + 1, started, now, max_attempts, window, lockout)
    end
  end

  defp put_failure(table, key, count, started, now, max_attempts, window, lockout) do
    locked_until = if count >= max_attempts, do: now + lockout, else: 0
    expires_at = max(started + max(window, 3_600), locked_until)
    true = :ets.insert(table, {key, count, started, locked_until, expires_at})
    if locked_until > now, do: {:error, lockout}, else: :ok
  end

  defp result([]), do: :ok
  defp result(values), do: {:error, Enum.max(values)}
end
