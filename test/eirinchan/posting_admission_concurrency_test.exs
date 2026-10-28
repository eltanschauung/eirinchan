defmodule Eirinchan.PostingAdmissionRepo do
  use Ecto.Repo, otp_app: :eirinchan, adapter: Ecto.Adapters.Postgres
end

defmodule Eirinchan.PostingAdmissionConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Eirinchan.{
    Antispam,
    Boards,
    BrowserAbuse,
    BrowserIdentity,
    PostingAdmissionRepo,
    Posts,
    Repo
  }

  alias Eirinchan.Antispam.FloodEntry
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.BrowserAbuse.Signal
  alias Eirinchan.Posts.Post
  alias Eirinchan.Runtime.Config

  test "concurrent text posts across boards reserve the global quota atomically" do
    race(:text_text)
  end

  test "text and upload attempts share one atomic global quota" do
    race(:text_upload)
  end

  test "same-board text and upload reservations avoid a foreign-key lock cycle" do
    race(:same_board)
  end

  defp race(kind) do
    opts = Repo.config()
    assert Keyword.get(opts, :hostname) in ["localhost", "127.0.0.1", "::1"]
    assert Regex.match?(~r/_test[0-9]*$/, Keyword.get(opts, :database, ""))

    opts =
      opts
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 4)
      |> Keyword.put(:telemetry_prefix, [:eirinchan, :posting_admission_repo])

    {:ok, pid} = PostingAdmissionRepo.start_link(opts)
    Process.unlink(pid)
    suffix = Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    uris = ["atomic_a" <> suffix, "atomic_b" <> suffix]
    refs = Enum.map(uris, &BrowserIdentity.reference/1)
    handler = {__MODULE__, make_ref()}

    try do
      try do
        boards =
          Enum.map(uris, fn uri ->
            {:ok, board} =
              Boards.create_board(%{uri: uri, title: "Synthetic test"},
                repo: PostingAdmissionRepo
              )

            board
          end)

        config =
          Config.compose(
            nil,
            %{},
            %{
              flood_time: 0,
              flood_global_count: 1,
              flood_global_window: 60,
              duplicate_post_window_minutes: 0,
              duplicate_thread_window_hours: 0,
              filters: [],
              generation_strategy: "build_on_load"
            },
            request_host: "example.test"
          )

        :ok =
          :telemetry.attach(
            handler,
            [:eirinchan, :posting_admission_repo, :query],
            &__MODULE__.query_event/4,
            self()
          )

        parent = self()
        kinds = if kind == :text_text, do: [:text, :text], else: [:text, :upload]
        task_boards = if kind == :same_board, do: [hd(boards), hd(boards)], else: boards

        tasks =
          Enum.zip([task_boards, refs, kinds])
          |> Enum.map(fn {board, ref, action} ->
            Task.async(fn ->
              Process.put(:race_parent, parent)
              Process.put(:same_board_role, if(kind == :same_board, do: action))
              if kind == :same_board and action == :upload, do: Process.put(:paused_quota, true)
              :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
              receive do: (:start -> :ok)

              request = %{
                remote_ip: {192, 0, 2, 1},
                browser_ref: ref,
                referer: "http://example.test/#{board.uri}/index.html"
              }

              attrs = %{"body" => "synthetic #{board.uri}", "post" => "New Topic"}

              result =
                if action == :text,
                  do:
                    Posts.create_post(board, attrs,
                      config: config,
                      request: request,
                      repo: PostingAdmissionRepo
                    ),
                  else:
                    Antispam.reserve_upload_attempt(board, attrs, request, config,
                      repo: PostingAdmissionRepo
                    )

              {ref, result}
            end)
          end)

        if kind == :same_board do
          [text_task, upload_task] = tasks
          send(text_task.pid, :start)
          assert_receive {:initial_quota_read, _}, 3_000
          send(text_task.pid, :continue)
          assert_receive {:board_locked, text_pid}, 3_000
          send(upload_task.pid, :start)
          assert_receive {:upload_locked, upload_pid}, 3_000
          send(text_pid, :continue)
          send(upload_pid, :continue)
        else
          Enum.each(tasks, &send(&1.pid, :start))
          assert_receive {:initial_quota_read, first}, 3_000
          assert_receive {:initial_quota_read, second}, 3_000
          send(first, :continue)
          send(second, :continue)
        end

        results = Enum.map(tasks, &Task.await(&1, 15_000))

        accepted =
          Enum.filter(results, fn {_ref, result} ->
            result == :ok or match?({:ok, _, _}, result)
          end)

        rejected = Enum.filter(results, fn {_ref, result} -> result == {:error, :antispam} end)
        assert length(accepted) == 1
        assert [{rejected_ref, _}] = rejected
        assert BrowserAbuse.signaled?(%{browser_ref: rejected_ref}, repo: PostingAdmissionRepo)

        ids = Enum.map(boards, & &1.id)

        assert PostingAdmissionRepo.aggregate(
                 from(e in FloodEntry, where: e.board_id in ^ids and e.activity == "post"),
                 :count,
                 :id
               ) == 1
      after
        :telemetry.detach(handler)
        ids = PostingAdmissionRepo.all(from b in BoardRecord, where: b.uri in ^uris, select: b.id)
        PostingAdmissionRepo.delete_all(from p in Post, where: p.board_id in ^ids)
        PostingAdmissionRepo.delete_all(from e in FloodEntry, where: e.board_id in ^ids)
        PostingAdmissionRepo.delete_all(from s in Signal, where: s.browser_ref in ^refs)
        PostingAdmissionRepo.delete_all(from b in BoardRecord, where: b.id in ^ids)
      end
    after
      if Process.alive?(pid), do: GenServer.stop(pid)
    end
  end

  def query_event(_event, _measurements, metadata, _config) do
    query = String.downcase(Map.get(metadata, :query, ""))

    if (parent = Process.get(:race_parent)) && !Process.get(:paused_quota) &&
         String.contains?(query, "count(") && String.contains?(query, "\"flood_entries\"") do
      Process.put(:paused_quota, true)
      send(parent, {:initial_quota_read, self()})
      receive do: (:continue -> :ok), after: (5_000 -> raise "quota barrier timed out")
    end

    if parent = Process.get(:race_parent) do
      cond do
        Process.get(:same_board_role) == :text and String.contains?(query, "\"boards\"") and
            String.contains?(query, "for ") ->
          Process.delete(:same_board_role)
          send(parent, {:board_locked, self()})
          receive do: (:continue -> :ok), after: (5_000 -> raise "board barrier timed out")

        Process.get(:same_board_role) == :upload and
            String.contains?(query, "pg_advisory_xact_lock") ->
          Process.delete(:same_board_role)
          send(parent, {:upload_locked, self()})
          receive do: (:continue -> :ok), after: (5_000 -> raise "upload barrier timed out")

        true ->
          :ok
      end
    end
  end
end
