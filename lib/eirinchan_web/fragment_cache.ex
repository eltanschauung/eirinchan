defmodule EirinchanWeb.FragmentCache do
  @moduledoc false

  @table __MODULE__

  def fetch_or_store(key, fun) when is_function(fun, 0) do
    table = ensure_table()

    case :ets.lookup(table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = fun.()
        :ets.insert(table, {key, value})
        value
    end
  end

  def clear do
    table = ensure_table()
    :ets.delete_all_objects(table)
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])

      table ->
        table
    end
  end
end
