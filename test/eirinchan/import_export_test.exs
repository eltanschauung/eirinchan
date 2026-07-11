defmodule Eirinchan.ImportExportTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.ImportExport
  alias Eirinchan.Posts
  alias Eirinchan.Runtime.Config

  test "export and idempotent import round-trip core board/post data" do
    board = board_fixture()

    {:ok, thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "hello export", "post" => "New Topic"},
        config: Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    {:ok, payload} = ImportExport.export(repo: Repo)
    assert get_in(payload, ["tables", "boards"]) != []
    assert get_in(payload, ["tables", "posts"]) != []

    Repo.delete_all(Eirinchan.Posts.Post)
    Repo.delete_all(Eirinchan.Boards.BoardRecord)

    assert {:ok, counts} = ImportExport.import_data(payload, repo: Repo)
    assert counts["boards"] >= 1
    assert counts["posts"] >= 1

    assert {:ok, counts_again} = ImportExport.import_data(payload, repo: Repo)
    assert counts_again["boards"] == 0
    assert counts_again["posts"] == 0

    imported_board = Repo.get_by!(Eirinchan.Boards.BoardRecord, uri: board.uri)
    imported_post = Repo.get!(Eirinchan.Posts.Post, thread.id)
    assert imported_board.title == board.title
    assert imported_post.body == "hello export"
  end

  test "dry-run import rolls back inserted rows" do
    payload = %{
      "tables" => %{
        "boards" => [
          %{
            "id" => 9001,
            "uri" => "dryrun",
            "title" => "Dry Run",
            "subtitle" => nil,
            "config_overrides" => %{},
            "inserted_at" =>
              DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
            "updated_at" =>
              DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
          }
        ]
      }
    }

    assert {:ok, %{"boards" => 1}} = ImportExport.import_data(payload, repo: Repo, dry_run: true)
    refute Repo.get(Eirinchan.Boards.BoardRecord, 9001)
  end

  test "older imports receive defaults for fields added by later migrations" do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    payload = %{
      "tables" => %{
        "boards" => [
          %{
            "id" => 9002,
            "uri" => "legacyexport",
            "title" => "Legacy Export",
            "config_overrides" => %{},
            "inserted_at" => now,
            "updated_at" => now
          }
        ]
      }
    }

    assert {:ok, %{"boards" => 1}} = ImportExport.import_data(payload, repo: Repo)
    assert Repo.get!(Eirinchan.Boards.BoardRecord, 9002).next_public_post_id == 1
  end

  test "mysql dump analysis reports supported and unsupported tables" do
    path =
      Path.join(System.tmp_dir!(), "eirinchan-mysql-#{System.unique_integer([:positive])}.sql")

    File.write!(
      path,
      """
      CREATE TABLE `boards` (...);
      CREATE TABLE `posts` (...);
      CREATE TABLE `legacy_only` (...);
      INSERT INTO `bans` VALUES (...);
      """
    )

    assert {:ok, analysis} = ImportExport.analyze_mysql_dump(path)
    assert "boards" in analysis.supported_tables
    assert "posts" in analysis.supported_tables
    assert "bans" in analysis.supported_tables
    assert "legacy_only" in analysis.unsupported_tables
  end
end
