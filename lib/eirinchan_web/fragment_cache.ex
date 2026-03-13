defmodule EirinchanWeb.FragmentCache do
  @moduledoc false

  use GenServer

  @table __MODULE__
  @retry_attempts 2

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    {:ok, %{table: create_table()}}
  end

  def fetch_or_store(key, fun) when is_function(fun, 0) do
    fetch_or_store(key, fun, @retry_attempts)
  end

  def clear do
    clear(@retry_attempts)
  end

  @impl true
  def handle_call(:ensure_table, _from, state) do
    {:reply, :ok, ensure_state_table(state)}
  end

  defp fetch_or_store(key, fun, attempts_left) when attempts_left > 0 do
    ensure_table()

    case lookup(key) do
      {:ok, [{^key, value}]} ->
        value

      {:ok, []} ->
        value = fun.()

        case insert(key, value) do
          :ok -> value
          :retry -> fetch_or_store(key, fun, attempts_left - 1)
        end

      :retry ->
        fetch_or_store(key, fun, attempts_left - 1)
    end
  end

  defp fetch_or_store(key, fun, _attempts_left) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = fun.()
        :ets.insert(@table, {key, value})
        value
    end
  end

  defp clear(attempts_left) when attempts_left > 0 do
    ensure_table()

    case delete_all_objects() do
      :ok -> :ok
      :retry -> clear(attempts_left - 1)
    end
  end

  defp clear(_attempts_left) do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_table do
    ensure_owner_started()
    GenServer.call(__MODULE__, :ensure_table)
  end

  defp ensure_owner_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp ensure_state_table(state) do
    case :ets.whereis(@table) do
      :undefined -> %{state | table: create_table()}
      _table -> state
    end
  end

  defp create_table do
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

  defp lookup(key) do
    {:ok, :ets.lookup(@table, key)}
  rescue
    error in ArgumentError ->
      if stale_table_error?(error) do
        repair_table()
        :retry
      else
        reraise error, __STACKTRACE__
      end
  end

  defp insert(key, value) do
    :ets.insert(@table, {key, value})
    :ok
  rescue
    error in ArgumentError ->
      if stale_table_error?(error) do
        repair_table()
        :retry
      else
        reraise error, __STACKTRACE__
      end
  end

  defp delete_all_objects do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    error in ArgumentError ->
      if stale_table_error?(error) do
        repair_table()
        :retry
      else
        reraise error, __STACKTRACE__
      end
  end

  defp repair_table do
    ensure_owner_started()
    GenServer.call(__MODULE__, :ensure_table)
  end

  defp stale_table_error?(%ArgumentError{message: message}) when is_binary(message) do
    String.contains?(message, "ETS table") or
      String.contains?(message, "table identifier does not refer to an existing ETS table")
  end

  defp stale_table_error?(_error), do: false
end
