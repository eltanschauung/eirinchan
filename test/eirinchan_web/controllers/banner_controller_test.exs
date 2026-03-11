defmodule EirinchanWeb.BannerControllerTest do
  use EirinchanWeb.ConnCase, async: true

  import Phoenix.ConnTest

  alias Eirinchan.Settings

  setup do
    original = Settings.current_instance_config()

    on_exit(fn ->
      :ok = Settings.persist_instance_config(original)
    end)

    :ok
  end

  test "b.php redirects to a configured banner path", %{conn: conn} do
    :ok =
      Settings.persist_instance_config(
        Map.put(Settings.current_instance_config(), :banners, ["/images/logo.svg"])
      )

    conn = get(conn, "/b.php")

    assert redirected_to(conn, 307) == "/images/logo.svg"
  end

  test "b.php falls back to a static banner when no banners are configured", %{conn: conn} do
    :ok = Settings.persist_instance_config(Map.put(Settings.current_instance_config(), :banners, []))

    conn = get(conn, "/b.php")
    redirected = redirected_to(conn, 307)

    assert String.starts_with?(redirected, "/static/banners/")
  end
end
