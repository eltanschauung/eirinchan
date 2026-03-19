defmodule EirinchanWeb.FeedbackController do
  use EirinchanWeb, :controller

  alias Eirinchan.Antispam
  alias Eirinchan.Boards
  alias Eirinchan.CustomPages
  alias Eirinchan.Feedback
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias Eirinchan.ThreadWatcher
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.HtmlSanitizer
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
    request = %{remote_ip: RequestMeta.effective_remote_ip(conn)}
    config =
      Settings.current_instance_config()
      |> Config.deep_merge(Application.get_env(:eirinchan, :search_overrides, %{}))
      |> then(&Config.compose(nil, &1, %{}))

    if feedback_rate_limited?(request, config) do
      message = "Wait a while before searching again, please."

      if params["json_response"] == "1" do
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: message})
      else
        conn
        |> put_status(:too_many_requests)
        |> render(:show,
          errors: %{"rate_limit" => [message]},
          params: params,
          boards: Boards.list_boards(),
          global_message: current_global_message(),
          custom_pages: CustomPages.list_pages(),
          board_chrome: BoardChrome.for_board(%{uri: "bant"})
        )
      end
    else
      _ = Antispam.log_search_query("feedback", request)

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
  end

  defp feedback_rate_limited?(request, config) do
    {per_ip_count, per_ip_minutes} = search_limit_tuple(config, :search_queries_per_minutes, 15, 2)
    {global_count, global_minutes} = search_limit_tuple(config, :search_queries_per_minutes_all, 50, 2)

    Antispam.public_search_rate_limited?(
      request,
      per_ip_count: per_ip_count,
      per_ip_window_seconds: per_ip_minutes * 60,
      global_count: global_count,
      global_window_seconds: global_minutes * 60
    )
  end

  defp search_limit_tuple(config, key, default_count, default_minutes) do
    case Map.get(config, key) do
      [count, minutes] when is_integer(count) and is_integer(minutes) -> {count, minutes}
      {count, minutes} when is_integer(count) and is_integer(minutes) -> {count, minutes}
      _ -> {default_count, default_minutes}
    end
  end

  defp assign_feedback_shell(conn, _opts) do
    stylesheet = conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"
    watcher_metrics =
      case conn.assigns[:browser_token] do
        token when is_binary(token) -> ThreadWatcher.watch_metrics(token)
        _ -> %{watcher_count: 0, watcher_unread_count: 0, watcher_you_count: 0}
      end

    conn
    |> assign(:page_title, "Feedback")
    |> assign(:public_shell, true)
    |> assign(:base_stylesheet, "/stylesheets/style.css")
    |> assign(:primary_stylesheet, stylesheet)
    |> assign(:primary_stylesheet_id, "stylesheet")
    |> assign(:body_class, "8chan vichan is-not-moderator active-feedback")
    |> assign(:body_data_stylesheet, Path.basename(stylesheet))
    |> assign(:global_boardlist_groups, EirinchanWeb.PostView.boardlist_groups(Boards.list_boards()))
    |> assign(:watcher_count, watcher_metrics.watcher_count)
    |> assign(:watcher_unread_count, watcher_metrics.watcher_unread_count)
    |> assign(:watcher_you_count, watcher_metrics.watcher_you_count)
    |> assign(
      :head_meta,
      PublicShell.head_meta("feedback",
        resource_version: conn.assigns[:asset_version],
        theme_label: conn.assigns[:theme_label],
        theme_options: conn.assigns[:theme_options],
        browser_timezone: conn.assigns[:browser_timezone],
        browser_timezone_offset_minutes: conn.assigns[:browser_timezone_offset_minutes],
        watcher_count: watcher_metrics.watcher_count,
        watcher_unread_count: watcher_metrics.watcher_unread_count,
        watcher_you_count: watcher_metrics.watcher_you_count
      )
    )
    |> assign(:javascript_urls, PublicShell.javascript_urls(:feedback))
    |> assign(:extra_stylesheets, [
      "/stylesheets/eirinchan-public.css",
      "/stylesheets/eirinchan-bant.css"
    ])
    |> assign(:skip_app_stylesheet, true)
    |> assign(:skip_flash_group, true)
  end

  defp current_global_message do
    case Eirinchan.Settings.current_instance_config() |> Map.get(:global_message) do
      value when is_binary(value) -> HtmlSanitizer.sanitize_fragment(value)
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
