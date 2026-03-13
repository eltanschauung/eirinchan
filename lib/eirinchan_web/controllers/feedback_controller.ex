defmodule EirinchanWeb.FeedbackController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.CustomPages
  alias Eirinchan.Feedback
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.RequestMeta

  plug :assign_feedback_shell

  def show(conn, _params) do
    render(conn, :show,
      boards: Boards.list_boards(),
      global_message: current_global_message(),
      custom_pages: CustomPages.list_pages(),
      board_chrome: BoardChrome.for_board(%{uri: "bant"})
    )
  end

  def create(conn, params) do
    case Feedback.create_feedback(params, remote_ip: RequestMeta.effective_remote_ip(conn)) do
      {:ok, entry} ->
        if params["json_response"] == "1" do
          json(conn, %{feedback_id: entry.id, status: "ok"})
        else
          redirect(conn, to: "/feedback")
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        if params["json_response"] == "1" do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: translate_errors(changeset)})
        else
          conn
          |> put_status(:unprocessable_entity)
          |> render(:show,
            errors: translate_errors(changeset),
            params: params,
            boards: Boards.list_boards(),
            global_message: current_global_message(),
            custom_pages: CustomPages.list_pages(),
            board_chrome: BoardChrome.for_board(%{uri: "bant"})
          )
        end
    end
  end

  defp assign_feedback_shell(conn, _opts) do
    stylesheet = conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"

    conn
    |> assign(:page_title, "Feedback")
    |> assign(:public_shell, true)
    |> assign(:base_stylesheet, "/stylesheets/style.css")
    |> assign(:primary_stylesheet, stylesheet)
    |> assign(:primary_stylesheet_id, "stylesheet")
    |> assign(:body_class, "8chan vichan is-not-moderator active-feedback")
    |> assign(:body_data_stylesheet, Path.basename(stylesheet))
    |> assign(:global_boardlist_groups, EirinchanWeb.PostView.boardlist_groups(Boards.list_boards()))
    |> assign(
      :head_html,
      PublicShell.head_html("feedback",
        resource_version: conn.assigns[:asset_version],
        theme_label: conn.assigns[:theme_label],
        theme_options: conn.assigns[:theme_options],
        browser_timezone: conn.assigns[:browser_timezone],
        browser_timezone_offset_minutes: conn.assigns[:browser_timezone_offset_minutes]
      )
    )
    |> assign(:javascript_urls, PublicShell.javascript_urls(:feedback))
    |> assign(:body_end_html, PublicShell.body_end_html())
    |> assign(:extra_stylesheets, [
      "/stylesheets/eirinchan-public.css",
      "/stylesheets/eirinchan-bant.css"
    ])
    |> assign(:skip_app_stylesheet, true)
    |> assign(:skip_flash_group, true)
  end

  defp current_global_message do
    case Eirinchan.Settings.current_instance_config() |> Map.get(:global_message) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
