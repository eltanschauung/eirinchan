defmodule Eirinchan.LogRetention do
  @moduledoc false

  require Logger

  alias Eirinchan.{AccessLog, ModerationLog, Repo}

  @default_days 7

  def run(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    days = Keyword.get(opts, :retention_days, configured_days())
    cutoff = DateTime.add(now, -days * 86_400, :second)
    repo = Keyword.get(opts, :repo, Repo)
    access_log_server = Keyword.get(opts, :access_log_server, AccessLog)

    with {:ok, access_lines} <- AccessLog.purge_older_than(cutoff, access_log_server) do
      moderation_rows = ModerationLog.purge_older_than(cutoff, repo: repo)

      result = %{
        access_lines: access_lines,
        cutoff: DateTime.to_iso8601(cutoff),
        moderation_rows: moderation_rows
      }

      Logger.info(
        "log.retention access_lines=#{access_lines} moderation_rows=#{moderation_rows} cutoff=#{result.cutoff}"
      )

      {:ok, result}
    end
  rescue
    error ->
      Logger.error("log retention failed: #{Exception.message(error)}")
      {:error, error}
  end

  defp configured_days do
    case Application.get_env(:eirinchan, :log_retention_days, @default_days) do
      days when is_integer(days) and days > 0 -> days
      _ -> @default_days
    end
  end
end
