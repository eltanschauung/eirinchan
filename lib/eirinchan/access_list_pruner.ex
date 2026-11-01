defmodule Eirinchan.AccessListPruner do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(opts) do
    Process.send_after(self(), :prune, 10_000)
    {:ok, Keyword.get(opts, :repo, Eirinchan.Repo)}
  end

  @impl true
  def handle_info(:prune, repo) do
    try do
      Eirinchan.AccessList.cleanup(repo: repo)
    rescue
      _ -> Logger.error("IP-access grant pruning failed")
    after
      Process.send_after(self(), :prune, 60_000)
    end

    {:noreply, repo}
  end
end
