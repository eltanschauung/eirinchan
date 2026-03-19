defmodule Eirinchan.ImportExport do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Repo

  @tables [
    {"boards", Eirinchan.Boards.BoardRecord},
    {"mod_users", Eirinchan.Moderation.ModUser},
    {"mod_board_accesses", Eirinchan.Moderation.ModBoardAccess},
    {"posts", Eirinchan.Posts.Post},
    {"post_files", Eirinchan.Posts.PostFile},
    {"cites", Eirinchan.Posts.Cite},
    {"nntp_references", Eirinchan.Posts.NntpReference},
    {"reports", Eirinchan.Reports.Report},
    {"bans", Eirinchan.Bans.Ban},
    {"ban_appeals", Eirinchan.Bans.Appeal},
    {"feedback", Eirinchan.Feedback.Entry},
    {"feedback_comments", Eirinchan.Feedback.Comment},
    {"news_entries", Eirinchan.News.Entry},
    {"noticeboard_entries", Eirinchan.Noticeboard.Entry},
    {"announcement_entries", Eirinchan.Announcement.Entry},
    {"custom_pages", Eirinchan.CustomPages.Page},
    {"ip_notes", Eirinchan.Moderation.IpNote},
    {"mod_messages", Eirinchan.Moderation.ModMessage},
    {"flood_entries", Eirinchan.Antispam.FloodEntry},
    {"search_queries", Eirinchan.Antispam.SearchQuery},
    {"build_jobs", Eirinchan.BuildQueue.Job}
  ]

  def export(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    {:ok,
     %{
       version: 1,
       exported_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
       tables:
         Map.new(@tables, fn {name, schema} ->
           rows =
             repo.all(from row in schema, order_by: [asc: row.id])
             |> Enum.map(&dump_row(schema, &1))

           {name, rows}
         end)
     }}
  end

  def export_file(path, opts \\ []) do
    with {:ok, payload} <- export(opts),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, Jason.encode_to_iodata!(payload, pretty: true)) do
      {:ok, path}
    end
  end

  def import_file(path, opts \\ []) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      import_data(payload, opts)
    end
  end

  def import_data(payload, opts \\ [])

  def import_data(payload, opts) when is_map(payload) do
    tables = payload[:tables] || payload["tables"]

    if is_map(tables) do
      do_import_data(tables, opts)
    else
      {:error, :invalid_payload}
    end
  end

  defp do_import_data(tables, opts) do
    repo = Keyword.get(opts, :repo, Repo)
    idempotent = Keyword.get(opts, :idempotent, true)
    dry_run = Keyword.get(opts, :dry_run, false)

    result =
      repo.transaction(fn ->
        counts =
          Enum.reduce(@tables, %{}, fn {name, schema}, acc ->
            rows =
              tables
              |> Map.get(name, [])
              |> Enum.map(&load_row(schema, &1))

            count =
              if rows == [] do
                0
              else
                insert_opts =
                  if idempotent do
                    [on_conflict: :nothing, conflict_target: [:id]]
                  else
                    []
                  end

                {inserted, _} = repo.insert_all(schema, rows, insert_opts)

                maybe_reset_sequence(repo, schema)
                inserted
              end

            Map.put(acc, name, count)
          end)

        if dry_run do
          repo.rollback({:dry_run, counts})
        else
          counts
        end
      end)

    case result do
      {:ok, counts} -> {:ok, counts}
      {:error, {:dry_run, counts}} -> {:ok, counts}
      {:error, reason} -> {:error, reason}
    end
  end

  def analyze_mysql_dump(path) do
    with {:ok, body} <- File.read(path) do
      create_tables =
        Regex.scan(~r/CREATE TABLE\s+`([^`]+)`/i, body, capture: :all_but_first)
        |> List.flatten()

      insert_tables =
        Regex.scan(~r/INSERT INTO\s+`([^`]+)`/i, body, capture: :all_but_first)
        |> List.flatten()

      discovered = Enum.uniq(create_tables ++ insert_tables)
      supported = Enum.filter(discovered, &supported_mysql_table?/1)

      {:ok,
       %{
         discovered_tables: discovered,
         supported_tables: supported,
         unsupported_tables: discovered -- supported
       }}
    end
  end

  defp supported_mysql_table?(table_name) do
    table_name in Enum.map(@tables, &elem(&1, 0))
  end

  defp dump_row(schema, row) do
    schema.__schema__(:fields)
    |> Enum.reduce(%{}, fn field, acc ->
      Map.put(acc, Atom.to_string(field), dump_value(Map.get(row, field)))
    end)
  end

  defp dump_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp dump_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp dump_value(value), do: value

  defp load_row(schema, row) do
    schema.__schema__(:fields)
    |> Enum.reduce(%{}, fn field, acc ->
      key = Atom.to_string(field)
      Map.put(acc, field, load_value(schema.__schema__(:type, field), Map.get(row, key)))
    end)
  end

  defp load_value(:utc_datetime, value) when is_binary(value) do
    value |> DateTime.from_iso8601() |> elem(1) |> DateTime.truncate(:second)
  end

  defp load_value(:utc_datetime_usec, value) when is_binary(value) do
    value |> DateTime.from_iso8601() |> elem(1) |> DateTime.truncate(:microsecond)
  end

  defp load_value(_type, value), do: value

  defp maybe_reset_sequence(repo, schema) do
    table = schema.__schema__(:source)

    _ =
      repo.query(
        "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), COALESCE((SELECT MAX(id) FROM #{table}), 1), true)"
      )

    :ok
  end
end
