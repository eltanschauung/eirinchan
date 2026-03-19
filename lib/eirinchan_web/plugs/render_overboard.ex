defmodule EirinchanWeb.Plugs.RenderOverboard do
  import Plug.Conn

  alias Eirinchan.Themes
  alias EirinchanWeb.PageController

  def init(opts), do: opts

  def call(conn, _opts) do
    board_uri = conn.path_params["board"] || conn.params["board"]

    if Themes.overboard_matches_uri?(board_uri) do
      page =
        case conn.path_params["page_num_html"] do
          nil ->
            1

          value ->
            value
            |> to_string()
            |> String.trim()
            |> String.trim_trailing(".html")
            |> Integer.parse()
            |> case do
              {page_num, ""} when page_num > 0 -> page_num
              _ -> 1
            end
        end

      conn
      |> PageController.render_overboard(page)
      |> halt()
    else
      conn
    end
  end
end
