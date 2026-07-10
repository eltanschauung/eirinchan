defmodule EirinchanWeb.SetupController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Installation

  plug :assign_setup_shell

  def show(conn, _params) do
    if Installation.setup_required?() do
      render(conn, :show)
    else
      redirect(conn, to: ~p"/manage/login")
    end
  end

  defp assign_setup_shell(conn, _opts) do
    conn
    |> assign(:page_title, "Eirinchan Setup")
    |> assign(:global_boardlist_groups, shell_boardlist_groups(conn))
    |> assign(:base_stylesheet, "/stylesheets/style.css")
    |> assign(:primary_stylesheet, "/stylesheets/yotsuba.css")
    |> assign(:primary_stylesheet_id, "stylesheet")
    |> assign(:body_class, "8chan vichan is-not-moderator setup-page")
    |> assign(:body_data_stylesheet, "yotsuba.css")
    |> assign(:extra_stylesheets, ["/stylesheets/eirinchan-mod.css"])
    |> assign(:skip_app_stylesheet, true)
    |> assign(:skip_flash_group, true)
    |> assign(:hide_theme_switcher, true)
  end

  defp shell_boardlist_groups(conn) do
    Boards.list_boards()
    |> EirinchanWeb.BoardChrome.boardlist_groups(nil, mobile_client?: conn.assigns[:mobile_client?] || false)
  end
end
