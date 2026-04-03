defmodule EirinchanWeb.ErrorPages do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Eirinchan.Boards
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PostView
  alias EirinchanWeb.PublicControllerHelpers

  def not_found(conn, message \\ nil) do
    boards = Boards.list_boards()
    primary_board = Enum.find(boards, &(&1.uri == "bant")) || %{uri: "bant"}

    assigns =
      [
        layout: false,
        page_title: "Error 404",
        message: message,
        boards: boards,
        primary_board: primary_board,
        board_chrome: BoardChrome.for_board(primary_board),
        global_boardlist_groups:
          PostView.boardlist_groups(boards, mobile_client?: conn.assigns[:mobile_client?] || false),
        body_class: "8chan vichan is-not-moderator active-page"
      ] ++
        PublicControllerHelpers.public_shell_assigns(conn, "page",
          base_stylesheet: "/stylesheets/style.css",
          primary_stylesheet: "/stylesheets/yotsuba.css",
          body_data_stylesheet: "yotsuba.css",
          theme_label: "Yotsuba",
          theme_options: [],
          show_options_shell: false,
          hide_theme_switcher: true,
          show_nav_arrows_page: false
        )

    conn
    |> put_status(:not_found)
    |> put_view(EirinchanWeb.PageHTML)
    |> put_layout(false)
    |> render(:not_found, assigns)
    |> halt()
  end
end
