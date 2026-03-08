defmodule Eirinchan.Maintenance do
  @moduledoc false

  alias Eirinchan.{Antispam, Bans}

  @table :eirinchan_maintenance

  def run(config, opts \\ []) do
    repo = Keyword.get(opts, :repo, Eirinchan.Repo)

    {:ok,
     %{
       bans: Bans.purge_expired(repo: repo),
       antispam: Antispam.purge_old(config, repo: repo)
     }}
  end

  def run_if_due(config, opts \\ []) do
    if Map.get(config, :auto_maintenance, false) and due?(config) do
      result = run(config, opts)
      record_run()
      result
    else
      {:ok, :skipped}
    end
  end

  def due?(config) do
    interval = max(Map.get(config, :maintenance_interval_seconds, 0), 0)

    case last_run_unix() do
      nil -> true
      _last when interval == 0 -> true
      last -> System.system_time(:second) - last >= interval
    end
  end

  defp record_run do
    ensure_table()
    true = :ets.insert(@table, {:last_run, System.system_time(:second)})
    :ok
  end

  defp last_run_unix do
    ensure_table()

    case :ets.lookup(@table, :last_run) do
      [{:last_run, unix}] -> unix
      _ -> nil
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ -> @table
    end
  end
end
