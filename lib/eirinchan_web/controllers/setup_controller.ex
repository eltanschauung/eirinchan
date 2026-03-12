defmodule EirinchanWeb.SetupController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Installation
  alias EirinchanWeb.PostView

  plug :assign_setup_shell

  def show(conn, _params) do
    if Installation.setup_required?() do
      render(conn, :show, params: Installation.setup_defaults(), errors: %{})
    else
      redirect(conn, to: ~p"/manage/login")
    end
  end

  def create(conn, params) do
    case Installation.run_setup(params) do
      {:ok, _admin} ->
        conn
        |> put_flash(:info, "Setup complete. Sign in with the admin account you just created.")
        |> redirect(to: ~p"/manage/login")

      {:error, %{errors: errors}} ->
        render(conn, :show,
          params: Map.merge(Installation.setup_defaults(), stringify(params)),
          errors: errors
        )

      {:error, reason} ->
        render(conn, :show,
          params: Map.merge(Installation.setup_defaults(), stringify(params)),
          errors: %{"setup" => Exception.message(reason)}
        )
    end
  end

  defp stringify(params) do
    Enum.into(params, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp assign_setup_shell(conn, _opts) do
    conn
    |> assign(:page_title, "Eirinchan Setup")
    |> assign(:global_boardlist_groups, shell_boardlist_groups())
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

  defp shell_boardlist_groups do
    Boards.list_boards()
    |> PostView.boardlist_groups()
  end
end
