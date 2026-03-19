defmodule EirinchanWeb.Plugs.RenderOverboard do
  import Plug.Conn

  alias Eirinchan.Themes
  alias EirinchanWeb.PageController

  def init(opts), do: opts

  def call(conn, _opts) do
    board_uri = conn.path_params["board"] || conn.params["board"]

    if Themes.overboard_matches_uri?(board_uri) do
      conn
      |> PageController.render_overboard()
      |> halt()
    else
      conn
    end
  end
end
