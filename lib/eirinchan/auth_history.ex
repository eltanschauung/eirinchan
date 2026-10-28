defmodule Eirinchan.AuthHistory do
  @moduledoc false
  use GenServer

  @tables [:eirinchan_manage_login_throttle, :eirinchan_ip_access_auth_throttle]

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  def table(name) when name in @tables do
    case :ets.whereis(name) do
      :undefined ->
        cond do
          Process.whereis(__MODULE__) -> GenServer.call(__MODULE__, {:table, name})
          Process.whereis(Eirinchan.Supervisor) -> exit(:auth_history_unavailable)
          true -> create_table(name)
        end

      table ->
        # A hot upgrade may initially leave the old throttle as table owner.
        if :ets.info(table, :owner) == self() do
          if keeper = Process.whereis(__MODULE__),
            do: :ets.give_away(table, keeper, :auth_history)
        end

        table
    end
  end

  @impl true
  def init(:ok) do
    Enum.each(@tables, fn name -> if :ets.whereis(name) == :undefined, do: create_table(name) end)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:table, name}, _from, state) when name in @tables do
    table =
      case :ets.whereis(name) do
        :undefined -> create_table(name)
        table -> table
      end

    {:reply, table, state}
  end

  @impl true
  def handle_info({:"ETS-TRANSFER", _table, _from, :auth_history}, state), do: {:noreply, state}

  defp create_table(name) do
    :ets.new(name, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
  end
end
