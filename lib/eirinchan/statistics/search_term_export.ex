defmodule Eirinchan.Statistics.SearchTermExport do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.Repo
  alias Eirinchan.Statistics.SearchTerm

  @fields ~w(country filename text)
  @header ["field", "term", "occurrences"]

  def export_file(path, %DateTime{} = since, opts \\ []) when is_binary(path) do
    repo = Keyword.get(opts, :repo, Repo)
    path = Path.expand(path)

    rows =
      repo.all(
        from search_term in SearchTerm,
          where:
            search_term.period_start >= ^since and
              search_term.field in ^@fields,
          group_by: [search_term.field, search_term.term],
          order_by: [
            asc: search_term.field,
            desc: sum(search_term.occurrences),
            asc: search_term.term
          ],
          select: {
            search_term.field,
            search_term.term,
            sum(search_term.occurrences)
          }
      )

    write_private_file(path, encode(rows))
  end

  defp encode(rows) do
    [@header | Enum.map(rows, &Tuple.to_list/1)]
    |> Enum.map(fn row ->
      [Enum.intersperse(Enum.map(row, &encode_field/1), ","), "\n"]
    end)
    |> IO.iodata_to_binary()
  end

  defp encode_field(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\"", "\"\"")

    ["\"", escaped, "\""]
  end

  defp write_private_file(path, contents) do
    temporary =
      Path.join(
        Path.dirname(path),
        ".#{Path.basename(path)}.tmp-#{System.unique_integer([:positive])}"
      )

    try do
      File.open!(temporary, [:write, :exclusive, :binary], fn device ->
        File.chmod!(temporary, 0o600)
        :ok = IO.binwrite(device, contents)
      end)

      File.rename!(temporary, path)
      {:ok, path}
    rescue
      error in File.Error -> {:error, error.reason}
    after
      File.rm(temporary)
    end
  end
end
