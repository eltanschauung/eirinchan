defmodule Eirinchan.Ban24FailureRepo do
  alias Eirinchan.Repo

  defdelegate get_by(schema, clauses), to: Repo
  defdelegate preload(value, preloads), to: Repo
  defdelegate preload(value, preloads, opts), to: Repo
  defdelegate one(query), to: Repo
  defdelegate all(query), to: Repo
  defdelegate transaction(fun), to: Repo
  defdelegate rollback(reason), to: Repo

  def insert(%Ecto.Changeset{data: %Eirinchan.Bans.Ban{}} = changeset),
    do: maybe_fail(changeset, :ban, &Repo.insert/1)

  def insert(%Ecto.Changeset{data: %Eirinchan.Moderation.PostEvent{}} = changeset),
    do: maybe_fail(changeset, :audit, &Repo.insert/1)

  def update(%Ecto.Changeset{data: %Eirinchan.Posts.Post{}} = changeset),
    do: maybe_fail(changeset, :post_update, &Repo.update/1)

  def update(%Ecto.Changeset{data: %Eirinchan.Posts.PostFile{}} = changeset),
    do: maybe_fail(changeset, :file_update, &Repo.update/1)

  defp maybe_fail(changeset, stage, fun) do
    if Process.get(:ban24_failure) == stage,
      do: {:error, Ecto.Changeset.add_error(changeset, :id, "injected failure")},
      else: fun.(changeset)
  end
end

defmodule Eirinchan.Ban24AuditTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.{Bans, Posts, Uploads}
  alias Eirinchan.Moderation.PostEvent
  alias Eirinchan.Runtime.Config

  for stage <- [:ban, :audit, :post_update, :file_update] do
    test "#{stage} failure rolls back ban, evidence and file markers without removing bytes" do
      board = board_fixture()
      moderator = moderator_fixture(%{role: "admin"})

      post =
        thread_fixture(board, %{
          files: [upload_fixture("primary.png", "primary"), upload_fixture("extra.png", "extra")]
        })

      set_ip(post, "203.0.113.29")
      Process.put(:ban24_failure, unquote(stage))

      try do
        assert {:error, %Ecto.Changeset{}} =
                 Posts.ban_subnet_and_delete_files(
                   board,
                   post.public_id,
                   moderator,
                   repo: Eirinchan.Ban24FailureRepo
                 )
      after
        Process.delete(:ban24_failure)
      end

      assert Bans.list_bans() == []
      assert Repo.aggregate(PostEvent, :count) == 0
      assert {:ok, unchanged} = Posts.get_post(board, post.public_id)
      assert unchanged.file_path == post.file_path

      assert Enum.map(unchanged.extra_files, & &1.file_path) ==
               Enum.map(post.extra_files, & &1.file_path)

      for file <- [post | post.extra_files] do
        assert File.exists?(Uploads.filesystem_path(file.file_path))
        assert File.exists?(Uploads.filesystem_path(file.thumb_path))
      end
    end
  end

  test "only active attachments are counted; evidence survives subsequent record deletion" do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "admin"})

    post =
      thread_fixture(board, %{
        files: [upload_fixture("primary.png", "primary"), upload_fixture("extra.png", "extra")]
      })

    set_ip(post, "2001:db8:abcd:12::29")
    config = Config.compose(nil, %{}, board.config_overrides)
    assert {:ok, _} = Posts.delete_post_file(board, post.public_id, 0, config: config)

    assert {:ok, %{event: event, ban: ban}} =
             Posts.ban_subnet_and_delete_files(
               board,
               post.public_id,
               moderator,
               config: config
             )

    assert event.file_count == 1
    assert [%{file_name: "extra.png", position: 1}] = event.files
    assert event.banned_subnet == "2001:db8:abcd::/48"
    assert event.public_post_id == post.public_id
    assert event.post_id == post.id
    assert event.board_uri == board.uri
    assert event.inserted_at

    assert {:ok, _} = Posts.moderate_delete_post(board, post.public_id, config: config)
    assert {:ok, _} = Repo.delete(ban)
    assert {:ok, _} = Repo.delete(moderator)
    assert {:ok, _} = Repo.delete(board)
    persisted = Repo.get!(PostEvent, event.id)
    assert persisted.file_count == 1
    assert persisted.ban_id == nil
    assert persisted.mod_user_id == nil
    assert persisted.ip_subnet == "2001:db8:abcd:12::29"
  end

  test "incomplete legacy file metadata is preserved without inventing values" do
    board = board_fixture()
    post = thread_fixture(board, %{file: upload_fixture("legacy.png", "legacy")})

    Repo.update_all(from(p in Posts.Post, where: p.id == ^post.id),
      set: [ip_subnet: "192.0.2.45", file_name: nil, file_md5: nil, file_size: nil]
    )

    moderator = moderator_fixture(%{role: "admin"})

    assert {:ok, %{event: event}} =
             Posts.ban_subnet_and_delete_files(board, post.public_id, moderator)

    assert event.file_count == 1
    assert [%{position: 0, file_name: nil, file_md5: nil, file_size: nil}] = event.files
    refute File.exists?(Uploads.filesystem_path(post.file_path))
  end

  test "invalid stored IP cannot delete attachments or create a ban/evidence" do
    board = board_fixture()
    post = thread_fixture(board, %{file: upload_fixture("intact.png", "intact")})
    set_ip(post, "not-an-ip")
    moderator = moderator_fixture(%{role: "admin"})

    assert {:error, :invalid_ip} =
             Posts.ban_subnet_and_delete_files(board, post.public_id, moderator)

    assert Bans.list_bans() == []
    assert Repo.aggregate(PostEvent, :count) == 0
    assert File.exists?(Uploads.filesystem_path(post.file_path))
  end

  test "plain attachment deletion also leaves reply media intact and does not create B24 evidence" do
    board = board_fixture()
    post = thread_fixture(board, %{file: upload_fixture("opening.png", "opening")})
    reply = reply_fixture(board, post, %{file: upload_fixture("reply.png", "reply")})
    config = Config.compose(nil, %{}, board.config_overrides)
    assert {:ok, _} = Posts.delete_post_files(board, post.public_id, config: config)
    assert File.exists?(Uploads.filesystem_path(reply.file_path))
    assert File.exists?(Uploads.filesystem_path(reply.thumb_path))
    assert Repo.aggregate(PostEvent, :count) == 0
  end

  defp set_ip(post, ip) do
    Repo.update_all(from(p in Posts.Post, where: p.id == ^post.id), set: [ip_subnet: ip])
  end
end
