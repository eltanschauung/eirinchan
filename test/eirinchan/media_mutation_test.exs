defmodule Eirinchan.MediaMutationTest do
  use Eirinchan.DataCase, async: false
  alias Eirinchan.{MediaMutation, Posts, Uploads}
  alias Eirinchan.Runtime.Config

  for move <- [:reply, :thread], first <- [:spoiler, :move] do
    test "#{move} move and spoiler are serialized with #{first} first" do
      exercise(unquote(move), unquote(first))
    end
  end

  defp exercise(move, first) do
    source = board_fixture()
    target = board_fixture()
    target_thread = thread_fixture(target)

    config =
      Config.compose(nil, %{}, %{generation_strategy: "build_on_load"},
        request_host: "example.test"
      )

    source_thread = if move == :reply, do: thread_fixture(source)

    attrs = %{
      "body" => "Media lifecycle test",
      "post" => "New Topic",
      "files" => [upload_fixture("first.png", "first"), upload_fixture("second.gif", "second")]
    }

    attrs =
      if source_thread,
        do:
          attrs
          |> Map.put("thread", to_string(source_thread.public_id))
          |> Map.put("post", "Reply"),
        else: attrs

    assert {:ok, original, _} =
             Posts.create_post(source, attrs,
               config: config,
               request: %{referer: "http://example.test/#{source.uri}/index.html"}
             )

    parent = self()

    task =
      Task.async(fn ->
        MediaMutation.with_post(source, original.public_id, Repo, fn ->
          send(parent, :media_locked)
          receive do: (:continue -> :ok)

          if first == :spoiler,
            do: Posts.spoilerize_post_files(source, original.public_id, config: config),
            else: move(move, source, original.public_id, target, target_thread, config)
        end)
      end)

    assert_receive :media_locked, 5_000

    try do
      blocked =
        if first == :spoiler,
          do: move(move, source, original.public_id, target, target_thread, config),
          else: Posts.spoilerize_post_files(source, original.public_id, config: config)

      assert blocked == {:error, :stale_media}
    after
      send(task.pid, :continue)
    end

    assert {:ok, intermediate} = Task.await(task, 15_000)

    final =
      if first == :spoiler,
        do: move(move, source, original.public_id, target, target_thread, config),
        else: Posts.spoilerize_post_files(target, intermediate.public_id, config: config)

    assert {:ok, final} = final
    assert final.spoiler
    assert final.board_id == target.id
    assert String.starts_with?(final.thumb_path, "/#{target.uri}/thumb/spoiler-")
    assert File.exists?(Uploads.filesystem_path(final.thumb_path))
    assert [extra] = final.extra_files
    assert extra.spoiler
    assert String.starts_with?(extra.thumb_path, "/#{target.uri}/thumb/spoiler-")
    assert File.exists?(Uploads.filesystem_path(extra.thumb_path))
  end

  defp move(:thread, source, id, target, _target_thread, config),
    do: Posts.move_thread(source, id, target, config: config)

  defp move(:reply, source, id, target, target_thread, config),
    do: Posts.move_reply(source, id, target, target_thread.public_id, config: config)
end
