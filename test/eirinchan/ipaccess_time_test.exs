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

  test "the existing flag threshold bypasses both raw and decoded image-age checks" do
    config = %{ipaccess_time: 3, user_flag: true, ip_nulling_flags: 8}
    request = %{remote_ip: {192, 0, 2, 20}}

    for attrs <- [
          %{"file" => upload_fixture("flags.png")},
          %{"__upload_entries__" => [%{metadata: %{file_type: "image/png"}}]}
        ] do
      # The exact threshold passes, even without a grant. Whitespace does not
      # count toward the threshold, and disabling either flag setting closes it.
      passing = Map.put(attrs, "user_flag", "custom01")
      assert :ok = RequestGuards.validate_ipaccess_time(passing, request, config, grant: nil)

      assert :ok =
               RequestGuards.validate_ipaccess_time(
                 Map.put(attrs, "flags", "custom01"),
                 request,
                 config, grant: nil)

      for flags <- ["", "country", " country "] do
        assert {:error, :ipaccess_time} =
                 RequestGuards.validate_ipaccess_time(
                   Map.put(attrs, "user_flag", flags),
                   request,
                   config, grant: nil)
      end

      for disabled <- [%{config | user_flag: false}, %{config | ip_nulling_flags: 0}] do
        assert {:error, :ipaccess_time} =
                 RequestGuards.validate_ipaccess_time(passing, request, disabled, grant: nil)
      end
    end
  end

  test "flag-qualified image posts succeed without a grant or with a young grant" do
    for grant? <- [false, true] do
      board = board_fixture()

      config =
        Config.compose(nil, %{}, %{
          ipaccess: true,
          ipaccess_time: 3,
          ip_nulling: false,
          ip_nulling_flags: 8,
          user_flag: true,
          multiple_flags: true,
          user_flags: %{"custom01" => "Custom"},
          generation_strategy: "build_on_load",
          flood_time: 0,
          filters: []
        })

      if grant?, do: AccessList.record_access("192.0.2.0/24", "synthetic-door")

      assert {:ok, post, _} =
               Posts.create_public_post(
                 board,
                 %{
                   "body" => "Flag-qualified image",
                   "post" => "New Topic",
                   "user_flag" => "custom01",
                   "file" => upload_fixture("flags.png")
                 }, config: config, request: request(board))

      assert post.file_path
      assert post.ip_subnet == "192.0.2.20"
      if grant?, do: assert(Repo.one!(IpAccessEntry).post_count == 1)
    end
  end
end
