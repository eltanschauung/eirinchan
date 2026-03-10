defmodule EirinchanWeb.ManageConfigControllerTest do
  use EirinchanWeb.ConnCase, async: false

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-settings-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "admin browser config editor persists instance overrides and affects board rendering", %{
    conn: conn
  } do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "cfg#{System.unique_integer([:positive])}", title: "Config"})

    update_conn =
      conn
      |> login_moderator(moderator)
      |> patch("/manage/config/browser", %{
        "config_json" => ~s({"field_disable_name": true, "search_enabled": false})
      })

    assert redirected_to(update_conn) == "/manage/config/browser"
    assert Eirinchan.Settings.current_instance_config().field_disable_name
    assert Eirinchan.Settings.current_instance_config().search_enabled == false

    config_page =
      update_conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/config/browser")
      |> html_response(200)

    assert config_page =~ "field_disable_name"
    assert config_page =~ "search_enabled"

    board_page =
      update_conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)
      |> Floki.parse_document!()

    assert Floki.find(board_page, ~s(input[name="name"])) == []
  end

  test "instance config editor preserves authored key order", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    raw_json = """
    {
      "Flags": "/flags",
      "FAQ": "/faq",
      "Feedback": "/feedback",
      "Home": "/"
    }
    """

    update_conn =
      conn
      |> login_moderator(moderator)
      |> patch("/manage/config/browser", %{"config_json" => raw_json})

    assert redirected_to(update_conn) == "/manage/config/browser"
    assert Eirinchan.Settings.raw_instance_config_json() == raw_json
    persisted = Eirinchan.Settings.raw_instance_config_json()

    assert elem(:binary.match(persisted, ~s("Flags": "/flags")), 0) <
             elem(:binary.match(persisted, ~s("FAQ": "/faq")), 0)

    assert elem(:binary.match(persisted, ~s("FAQ": "/faq")), 0) <
             elem(:binary.match(persisted, ~s("Feedback": "/feedback")), 0)

    config_page =
      update_conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/config/browser")
      |> html_response(200)

    assert config_page =~ "Flags"
    assert config_page =~ "Feedback"
  end

  test "admin browser board config editor persists board overrides and affects board rendering",
       %{
         conn: conn
       } do
    moderator = moderator_fixture(%{role: "admin"})

    board =
      board_fixture(%{
        uri: "bcfg#{System.unique_integer([:positive])}",
        title: "Board Config"
      })

    update_conn =
      conn
      |> login_moderator(moderator)
      |> patch("/manage/boards/#{board.uri}/config/browser", %{
        "config_json" => ~s({"country_flags": true, "allow_no_country": true})
      })

    assert redirected_to(update_conn) == "/manage/boards/#{board.uri}/config/browser"

    updated_board = Eirinchan.Boards.get_board_by_uri!(board.uri)
    assert updated_board.config_overrides["country_flags"]
    assert updated_board.config_overrides["allow_no_country"]

    config_page =
      update_conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/boards/#{board.uri}/config/browser")
      |> html_response(200)

    assert config_page =~ "country_flags"
    assert config_page =~ "allow_no_country"

    board_page =
      update_conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)
      |> Floki.parse_document!()

    assert Floki.find(board_page, ~s(input[name="no_country"][type="checkbox"])) != []
  end
end
