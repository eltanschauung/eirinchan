defmodule EirinchanWeb.BannerController do
  use EirinchanWeb, :controller

  alias Eirinchan.Settings
  alias EirinchanWeb.BannerAsset

  def show(conn, _params) do
    conn
    |> put_status(:temporary_redirect)
    |> redirect(external: BannerAsset.banner_url(Settings.current_instance_config()))
  end
end
