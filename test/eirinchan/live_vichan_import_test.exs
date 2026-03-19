defmodule Eirinchan.LiveVichanImportTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.LiveVichanImport
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo

  test "rewrite_imported_citations rewrites cites using persisted legacy import ids" do
    board = board_fixture()
    imported_target = thread_fixture(board, %{body: "Imported target"})
    imported_source = thread_fixture(board, %{body: "Original source body"})

    Repo.update_all(
      from(post in Post, where: post.id == ^imported_target.id),
      set: [legacy_import_id: 1234]
    )

    row = %{"id" => 5678, "body_nomarkup" => ">>1234"}

    assert :ok =
             LiveVichanImport.rewrite_imported_citations(
               board,
               [row],
               %{5678 => imported_source},
               Repo
             )

    rewritten_source = Repo.get!(Post, imported_source.id)

    assert rewritten_source.body == ">>#{imported_target.public_id}"

    assert Repo.exists?(
             from cite in "cites",
               where:
                 field(cite, :post_id) == ^imported_source.id and
                   field(cite, :target_post_id) == ^imported_target.id
           )

    assert Repo.exists?(
             from ref in "nntp_references",
               where:
                 field(ref, :post_id) == ^imported_source.id and
                   field(ref, :target_post_id) == ^imported_target.id
           )
  end
end
