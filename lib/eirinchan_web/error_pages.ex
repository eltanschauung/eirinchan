defmodule EirinchanWeb.ErrorPages do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Eirinchan.Boards
  alias Eirinchan.PrimaryBoard
  alias Eirinchan.Settings
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PostView
  alias EirinchanWeb.PublicControllerHelpers

  def not_found(conn, message \\ nil) do
    boards = Boards.list_boards()
    instance_config = Settings.effective_instance_config()
    primary_board = PrimaryBoard.resolve(boards, instance_config)

    assigns =
      [
        layout: false,
        page_title: "Error 404",
        message: message,
        boards: boards,
        primary_board: primary_board,
        show_public_page_banner: Map.get(instance_config, :show_public_page_banner, false),
        board_chrome: BoardChrome.for_board(primary_board),
        global_boardlist_groups:
          PostView.boardlist_groups(boards,
            mobile_client?: conn.assigns[:mobile_client?] || false
          ),
        body_class: "8chan vichan is-not-moderator active-page"
      ] ++
        PublicControllerHelpers.public_shell_assigns(conn, "page", show_nav_arrows_page: false)

    conn
    |> put_status(:not_found)
    |> put_view(EirinchanWeb.PageHTML)
    |> put_layout(false)
    |> render(:not_found, assigns)
    |> halt()
  end
end
