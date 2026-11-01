defmodule Eirinchan.IpaccessTimeTest do
  use Eirinchan.DataCase, async: false
  alias Eirinchan.{AccessList, IpAccessEntry, Posts}
  alias Eirinchan.Posts.RequestGuards
  alias Eirinchan.Runtime.Config

  defp request(board),
    do: %{remote_ip: {192, 0, 2, 20}, referer: "http://example.test/#{board.uri}/index.html"}

  test "young grants reject images but accept text; repeated auth does not reset image eligibility" do
    board = board_fixture()

    config =
      Config.compose(nil, %{}, %{
        ipaccess_time: 3,
        generation_strategy: "build_on_load",
        flood_time: 0,
        filters: []
      })

    assert {:ok, grant} = AccessList.record_access("192.0.2.0/24", "door")

    assert {:error, :ipaccess_time} =
             Posts.create_public_post(
               board,
               %{
                 "body" => "Image post",
                 "file" => upload_fixture("new.png"),
                 "post" => "New Topic"
               },
               config: config,
               request: request(board)
             )

    assert Repo.one!(IpAccessEntry).post_count == 0

    assert {:ok, _, _} =
             Posts.create_public_post(board, %{"body" => "Text only", "post" => "New Topic"},
               config: config,
               request: request(board)
             )

    old = DateTime.add(grant.authenticated_at, -4 * 3600, :second)
    Repo.update_all(IpAccessEntry, set: [authenticated_at: old])
    assert {:ok, repeat} = AccessList.record_access("192.0.2.0/24", "door")
    assert repeat.authenticated_at == old

    assert {:ok, _, _} =
             Posts.create_public_post(
               board,
               %{
                 "body" => "Old grant image",
                 "file" => upload_fixture("old.png"),
                 "post" => "New Topic"
               },
               config: config,
               request: request(board)
             )

    assert Repo.one!(IpAccessEntry).post_count == 2
  end

  test "missing grants block images, zero disables the rule, and prepared images cannot bypass the final check" do
    board = board_fixture()
    attrs = %{"file" => upload_fixture("new.png")}

    assert {:error, :ipaccess_time} =
             RequestGuards.validate_ipaccess_time(attrs, request(board), %{ipaccess_time: 3})

    assert :ok = RequestGuards.validate_ipaccess_time(attrs, request(board), %{ipaccess_time: 0})

    assert :ok =
             RequestGuards.validate_ipaccess_time(%{"body" => "Text"}, request(board), %{
               ipaccess_time: 3
             })

    prepared = %{"__upload_entries__" => [%{metadata: %{file_type: "image/png"}}]}

    assert {:error, :ipaccess_time} =
             RequestGuards.validate_ipaccess_time(prepared, request(board), %{ipaccess_time: 3},
               grant: nil
             )
  end
end
