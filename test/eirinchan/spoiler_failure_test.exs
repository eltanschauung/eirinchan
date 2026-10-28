defmodule Eirinchan.SpoilerFailingRepo do
  alias Eirinchan.Repo
  alias Eirinchan.Posts.Post

  def get_by(schema, clauses), do: Repo.get_by(schema, clauses)
  def get!(schema, id), do: Repo.get!(schema, id)
  def one(query), do: Repo.one(query)
  def all(query), do: Repo.all(query)
  def transaction(fun), do: Repo.transaction(fun)
  def rollback(reason), do: Repo.rollback(reason)
  def preload(value, associations, opts \\ []), do: Repo.preload(value, associations, opts)

  def update(%Ecto.Changeset{data: %Post{}} = changeset),
    do: {:error, Ecto.Changeset.add_error(changeset, :spoiler, "forced failure")}

  def update(changeset), do: Repo.update(changeset)
end

defmodule Eirinchan.SpoilerFailureTest do
  use Eirinchan.DataCase, async: true
  alias Eirinchan.{Posts, SpoilerFailingRepo, Uploads}
  alias Eirinchan.Runtime.Config

  test "database rollback removes newly prepared variants but leaves original media intact" do
    board = board_fixture()
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")
    request = %{referer: "http://example.test/#{board.uri}/index.html"}

    {:ok, post, _} =
      Posts.create_post(
        board,
        %{
          "body" => "Synthetic post",
          "files" => [upload_fixture("one.png"), upload_fixture("two.gif")],
          "post" => "New Topic"
        }, config: config, request: request)

    [extra] = post.extra_files
    old_primary = File.read!(Uploads.filesystem_path(post.thumb_path))
    old_extra = File.read!(Uploads.filesystem_path(extra.thumb_path))
    directory = Uploads.filesystem_path("/#{board.uri}/thumb")
    before = File.ls!(directory) |> Enum.sort()

    assert {:error, %Ecto.Changeset{}} =
             Posts.spoilerize_post_files(board, post.id, config: config, repo: SpoilerFailingRepo)

    {:ok, unchanged} = Posts.get_post(board, post.id)
    refute unchanged.spoiler
    assert unchanged.thumb_path == post.thumb_path
    assert [%{spoiler: false, thumb_path: thumb}] = unchanged.extra_files
    assert thumb == extra.thumb_path
    assert File.read!(Uploads.filesystem_path(post.thumb_path)) == old_primary
    assert File.read!(Uploads.filesystem_path(extra.thumb_path)) == old_extra
    assert File.ls!(directory) |> Enum.sort() == before
  end
end
