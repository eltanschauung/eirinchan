defmodule EirinchanWeb.BannerControllerTest do
  use EirinchanWeb.ConnCase, async: true

  import Phoenix.ConnTest

  alias Eirinchan.Settings
  alias EirinchanWeb.BannerAsset

  setup do
    original = Settings.current_instance_config()

    on_exit(fn ->
      :ok = Settings.persist_instance_config(original)
    end)

    :ok
  end

  test "b.php redirects to a configured banner path", %{conn: conn} do
    :ok = Settings.persist_instance_config(Map.put(Settings.current_instance_config(), :banners, ["/images/logo.svg"]))

    conn = get(conn, "/b.php")

    assert redirected_to(conn, 307) == "/images/logo.svg"
  end

  test "b.php falls back to the default static banner when no banners are configured", %{conn: conn} do
    :ok = Settings.persist_instance_config(Map.put(Settings.current_instance_config(), :banners, []))

    conn = get(conn, "/b.php")

    assert redirected_to(conn, 307) == BannerAsset.banner_url(%{banners: []})
  end
end
