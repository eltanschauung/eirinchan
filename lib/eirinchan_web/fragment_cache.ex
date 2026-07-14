defmodule EirinchanWeb.FragmentCache do
  @moduledoc false

  use GenServer

  @table __MODULE__
  @retry_attempts 2
  @default_max_entries 5_000
  @default_ttl_ms 5 * 60 * 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok), do: {:ok, %{table: create_table()}}

  def fetch_or_store(key, fun) when is_function(fun, 0) do
    fetch_or_store(key, fun, @retry_attempts)
  end

  def clear, do: clear(@retry_attempts)

  def delete_namespace(namespace), do: delete_namespaces([namespace])

  def delete_namespaces(namespaces) when is_list(namespaces) do
    delete_namespaces(MapSet.new(namespaces), @retry_attempts)
  end

  def size do
    ensure_table()
    :ets.info(@table, :size)
  end

  @impl true
  def handle_call(:ensure_table, _from, state) do
    {:reply, :ok, ensure_state_table(state)}
  end

  defp fetch_or_store(key, fun, attempts_left) when attempts_left > 0 do
    ensure_table()

    case lookup_fresh(key) do
      {:ok, {:hit, value}} -> value
      {:ok, :miss} -> store_computed(key, fun, attempts_left)
      :retry -> fetch_or_store(key, fun, attempts_left - 1)
    end
  end

  defp fetch_or_store(key, fun, _attempts_left) do
    ensure_table()

    case lookup_fresh_unsafe(key) do
      {:hit, value} ->
        value

      :miss ->
        value = fun.()
        insert_unsafe(key, value)
        value
    end
  end

  defp store_computed(key, fun, attempts_left) do
    value = fun.()

    case insert(key, value) do
      :ok -> value
      :retry -> fetch_or_store(key, fn -> value end, attempts_left - 1)
    end
  end

  defp lookup_fresh(key) do
    {:ok, lookup_fresh_unsafe(key)}
  rescue
    error in ArgumentError -> handle_stale_table(error)
  end

  defp lookup_fresh_unsafe(key) do
    case :ets.lookup(@table, key) do
      [{^key, inserted_at, value}] ->
        if monotonic_ms() - inserted_at <= ttl_ms() do
          {:hit, value}
        else
          :ets.delete(@table, key)
          :miss
        end

      _other ->
        :miss
    end
  end

  defp insert(key, value) do
    insert_unsafe(key, value)
    :ok
  rescue
    error in ArgumentError -> handle_stale_table(error)
  end

  defp insert_unsafe(key, value) do
    evict_if_full()
    :ets.insert(@table, {key, monotonic_ms(), value})
  end

  defp evict_if_full do
    size = :ets.info(@table, :size)
    maximum = max_entries()

    if size >= maximum do
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {_key, inserted_at, _value} -> inserted_at end)
      |> Enum.take(size - maximum + 1)
      |> Enum.each(fn {key, _inserted_at, _value} -> :ets.delete(@table, key) end)
    end
  end

  defp clear(attempts_left) when attempts_left > 0 do
    ensure_table()

    try do
      :ets.delete_all_objects(@table)
      :ok
    rescue
      error in ArgumentError ->
        case handle_stale_table(error) do
          :retry -> clear(attempts_left - 1)
        end
    end
  end

  defp clear(_attempts_left) do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp delete_namespaces(namespaces, attempts_left) when attempts_left > 0 do
    ensure_table()

    try do
      delete_namespaces_unsafe(namespaces)
    rescue
      error in ArgumentError ->
        case handle_stale_table(error) do
          :retry -> delete_namespaces(namespaces, attempts_left - 1)
        end
    end
  end

  defp delete_namespaces(namespaces, _attempts_left) do
    ensure_table()
    delete_namespaces_unsafe(namespaces)
  end

  defp delete_namespaces_unsafe(namespaces) do
    @table
    |> :ets.tab2list()
    |> Enum.each(fn {key, _inserted_at, _value} ->
      if namespaced_key?(key, namespaces), do: :ets.delete(@table, key)
    end)

    :ok
  end

  defp namespaced_key?(key, namespaces) when is_tuple(key) and tuple_size(key) > 0,
    do: MapSet.member?(namespaces, elem(key, 0))

  defp namespaced_key?(_key, _namespace), do: false

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

  defp handle_stale_table(error) do
    if stale_table_error?(error) do
      ensure_owner_started()
      GenServer.call(__MODULE__, :ensure_table)
      :retry
    else
      raise error
    end
  end

  defp cache_config, do: Application.get_env(:eirinchan, :fragment_cache, [])
  defp max_entries, do: max(Keyword.get(cache_config(), :max_entries, @default_max_entries), 1)
  defp ttl_ms, do: max(Keyword.get(cache_config(), :ttl_ms, @default_ttl_ms), 1)
  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp stale_table_error?(%ArgumentError{message: message}) when is_binary(message) do
    String.contains?(message, "ETS table") or
      String.contains?(message, "table identifier does not refer to an existing ETS table")
  end

  defp stale_table_error?(_error), do: false
end
