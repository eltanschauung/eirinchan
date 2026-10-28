defmodule Eirinchan.SpoilerConcurrencyRepo do
  use Ecto.Repo, otp_app: :eirinchan, adapter: Ecto.Adapters.Postgres
end

defmodule Eirinchan.SpoilerBarrierRepo do
  alias Eirinchan.SpoilerConcurrencyRepo, as: Repo
  def get_by(schema, clauses), do: Repo.get_by(schema, clauses)
  def get(schema, id), do: Repo.get(schema, id)
  def get!(schema, id), do: Repo.get!(schema, id)
  def one(query), do: Repo.one(query)
  def all(query), do: Repo.all(query)
  def update(changeset), do: Repo.update(changeset)
  def transaction(fun), do: Repo.transaction(fun)
  def rollback(reason), do: Repo.rollback(reason)
  def aggregate(query, aggregate, field), do: Repo.aggregate(query, aggregate, field)

  def preload(value, associations, opts \\ []) do
    result = Repo.preload(value, associations, opts)

    if parent = Process.delete(:spoiler_barrier_parent) do
      send(parent, {:snapshot, self()})
      receive do: (:continue -> :ok), after: (5_000 -> raise "spoiler barrier timed out")
    end

    result
  end
end

defmodule Eirinchan.SpoilerConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Eirinchan.UploadsFixtures
  alias Eirinchan.{Boards, Posts, Repo, SpoilerBarrierRepo, SpoilerConcurrencyRepo, Uploads}
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Runtime.Config

  test "concurrent spoilerization commits only one version and cleans the losing candidate" do
    opts = Repo.config()
    assert Keyword.get(opts, :hostname) in ["localhost", "127.0.0.1", "::1"]
    assert Regex.match?(~r/_test[0-9]*$/, Keyword.get(opts, :database, ""))
    opts = opts |> Keyword.put(:pool, DBConnection.ConnectionPool) |> Keyword.put(:pool_size, 4)
    {:ok, repo_pid} = SpoilerConcurrencyRepo.start_link(opts)
    Process.unlink(repo_pid)
    uri = "spoilerace#{System.unique_integer([:positive, :monotonic])}"
    root = Path.expand(Uploads.board_root())
    board_root = Path.join(root, uri)
    assert Path.dirname(board_root) == root

    try do
      {:ok, board} =
        Boards.create_board(%{uri: uri, title: "Spoiler race"}, repo: SpoilerConcurrencyRepo)

      original_path = "/#{uri}/thumb/original.png"
      original_abs = Uploads.filesystem_path(original_path)
      File.mkdir_p!(Path.dirname(original_abs))
      fixture = upload_fixture("race.png", "synthetic")
      File.cp!(fixture.path, original_abs)
      original_bytes = File.read!(original_abs)

      {:ok, post} =
        %Post{}
        |> Post.create_changeset(%{
          board_id: board.id,
          public_id: 1,
          body: "race",
          file_path: "/#{uri}/src/original.png",
          thumb_path: original_path,
          file_type: "image/png"
        })
        |> SpoilerConcurrencyRepo.insert()

      config = Config.compose(nil, %{}, %{generation_strategy: "build_on_load"})
      parent = self()

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            Process.put(:spoiler_barrier_parent, parent)

            Posts.spoilerize_post_file(board, post.id, 0,
              config: config,
              repo: SpoilerBarrierRepo
            )
          end)
        end

      assert_receive {:snapshot, first}, 5_000
      assert_receive {:snapshot, second}, 5_000
      send(first, :continue)
      send(second, :continue)
      results = Enum.map(tasks, &Task.await(&1, 15_000))
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :stale_media})) == 1
      current = SpoilerConcurrencyRepo.get!(Post, post.id)
      assert current.spoiler
      refute current.thumb_path == original_path
      assert File.read!(original_abs) == original_bytes
      assert File.exists?(Uploads.filesystem_path(current.thumb_path))

      assert length(
               Enum.filter(
                 File.ls!(Path.dirname(original_abs)),
                 &String.starts_with?(&1, "spoiler-")
               )
             ) == 1
    after
      ids = SpoilerConcurrencyRepo.all(from b in BoardRecord, where: b.uri == ^uri, select: b.id)
      SpoilerConcurrencyRepo.delete_all(from p in Post, where: p.board_id in ^ids)
      SpoilerConcurrencyRepo.delete_all(from b in BoardRecord, where: b.id in ^ids)
      File.rm_rf!(board_root)
      if Process.alive?(repo_pid), do: GenServer.stop(repo_pid)
    end
  end
end
