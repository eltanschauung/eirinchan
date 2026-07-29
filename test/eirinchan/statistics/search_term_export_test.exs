defmodule Eirinchan.Statistics.SearchTermExportTest do
  use Eirinchan.DataCase

  alias Eirinchan.Repo
  alias Eirinchan.Statistics.SearchTerm
  alias Eirinchan.Statistics.SearchTermExport

  test "exports aggregated text, country, and filename searches to a private CSV" do
    since = ~U[2026-07-25 20:55:59Z]

    insert_search_term(~U[2026-07-25 20:00:00Z], "text", "before cutoff", 10)
    insert_search_term(~U[2026-07-25 21:00:00Z], "text", "alpha", 2)
    insert_search_term(~U[2026-07-25 22:00:00Z], "text", "alpha", 3)
    insert_search_term(~U[2026-07-25 22:00:00Z], "text", "zeta", 5)
    insert_search_term(~U[2026-07-25 22:00:00Z], "country", "es", 4)
    insert_search_term(~U[2026-07-25 22:00:00Z], "filename", "scan,\"final\".png", 1)
    insert_search_term(~U[2026-07-25 22:00:00Z], "username", "not exported", 7)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-search-term-export-#{System.unique_integer([:positive])}.csv"
      )

    on_exit(fn -> File.rm(path) end)

    File.write!(path, "stale report")
    File.chmod!(path, 0o644)

    assert {:ok, ^path} = SearchTermExport.export_file(path, since, repo: Repo)

    assert File.read!(path) ==
             """
             "field","term","occurrences"
             "country","es","4"
             "filename","scan,""final"".png","1"
             "text","alpha","5"
             "text","zeta","5"
             """

    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
  end

  defp insert_search_term(period_start, field, term, occurrences) do
    now = DateTime.utc_now(:microsecond)
    period_start = DateTime.from_unix!(DateTime.to_unix(period_start, :microsecond), :microsecond)

    Repo.insert!(%SearchTerm{
      period_start: period_start,
      field: field,
      term: term,
      occurrences: occurrences,
      inserted_at: now,
      updated_at: now
    })
  end
end
