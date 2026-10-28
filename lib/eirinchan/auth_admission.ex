defmodule Eirinchan.AuthAdmission do
  @moduledoc false

  # OTP's lock server monitors the actual caller. Locks remain attached to the
  # request across throttle restarts and disappear if the request dies. There
  # are no waiting credentials, timers or owner-local reservation registries.
  def acquire(family, keys, max_inflight, allowed) do
    nonce = make_ref()

    case acquire_slot(family, nonce, max_inflight) do
      nil ->
        {:error, 1}

      slot ->
        case lock_keys(family, Enum.sort(keys), nonce, [slot]) do
          {:ok, locks} ->
            try do
              case allowed.() do
                :ok ->
                  {:ok, {self(), locks}}

                error ->
                  unlock(locks)
                  error
              end
            rescue
              error ->
                unlock(locks)
                reraise error, __STACKTRACE__
            catch
              :exit, _reason ->
                unlock(locks)
                {:error, :unavailable}

              kind, reason ->
                unlock(locks)
                :erlang.raise(kind, reason, __STACKTRACE__)
            end

          :busy ->
            {:error, 1}
        end
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def release({owner, locks}) when owner == self(), do: unlock(locks)
  def release(_), do: :ok

  defp acquire_slot(family, nonce, max_inflight) do
    Enum.find_value(1..max_inflight, fn index ->
      id = {{__MODULE__, family, :slot, index}, nonce}
      if :global.set_lock(id, [node()], 0), do: id
    end)
  end

  defp lock_keys(_family, [], _nonce, held), do: {:ok, held}

  defp lock_keys(family, [key | rest], nonce, held) do
    id = {{__MODULE__, family, :identity, key}, nonce}

    if :global.set_lock(id, [node()], 0) do
      lock_keys(family, rest, nonce, [id | held])
    else
      unlock(held)
      :busy
    end
  catch
    kind, reason ->
      unlock(held)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp unlock(locks) do
    Enum.each(locks, &:global.del_lock(&1, [node()]))
    :ok
  end
end
