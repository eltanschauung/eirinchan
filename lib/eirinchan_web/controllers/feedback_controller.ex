defmodule EirinchanWeb.FeedbackController do
  use EirinchanWeb, :controller

  alias Eirinchan.Antispam
  alias Eirinchan.Feedback
  alias Eirinchan.PublicPages
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.RequestMeta

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
        |> render_feedback_page(params: params, errors: %{"rate_limit" => [message]})
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
            |> render_feedback_page(params: params, errors: translate_errors(changeset))
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

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp render_feedback_page(conn, opts) do
    page = PublicPages.fetch_named_page("feedback")
    show_global_message = PublicPages.show_global_message?("feedback")

    assigns =
      Keyword.merge(
        EirinchanWeb.PublicControllerHelpers.public_page_assigns(conn, "active-page", "feedback",
          include_global_message: show_global_message
        ),
        layout: false,
        page: page,
        global_message_html: nil,
        sanitized_body: EirinchanWeb.HtmlSanitizer.sanitize_fragment(page.body || ""),
        page_subtitle: PublicPages.page_subtitle("feedback"),
        show_global_message: show_global_message,
        params: Keyword.get(opts, :params, %{}),
        errors: Keyword.get(opts, :errors)
      )

    conn
    |> Phoenix.Controller.put_view(EirinchanWeb.PageHTML)
    |> render(:feedback, assigns)
  end
end
