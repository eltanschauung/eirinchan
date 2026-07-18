defmodule EirinchanWeb.FeedbackController do
  use EirinchanWeb, :controller

  alias Eirinchan.Antispam
  alias Eirinchan.Antispam.PublicActivityPolicy
  alias Eirinchan.EventLog
  alias Eirinchan.Feedback
  alias Eirinchan.PublicPages
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.RequestMeta

  def create(conn, params) do
    request = RequestMeta.public_identity(conn)

    config =
      Settings.current_instance_config()
      |> Config.deep_merge(Application.get_env(:eirinchan, :feedback_overrides, %{}))
      |> then(&Config.compose(nil, &1, %{}))

    cond do
      invalid_feedback_body?(params["body"]) ->
        EventLog.log(conn, "feedback.rejected", %{outcome: "body_shape"})
        reject_feedback(conn, params, config.error.antispam, :unprocessable_entity)

      true ->
        case Antispam.reserve_configured_public_activity("feedback", request, config) do
          {:ok, _entry} ->
            create_feedback(conn, params)

          {:error, _reason} ->
            EventLog.log(conn, "feedback.rejected", %{outcome: "rate_limited"})

            message = PublicActivityPolicy.rate_limit_message(:feedback, config)

            reject_feedback(conn, params, message, :too_many_requests)
        end
    end
  end

  defp create_feedback(conn, params) do
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
          |> json(%{errors: EirinchanWeb.ChangesetErrors.translate(changeset)})
        else
          conn
          |> put_status(:unprocessable_entity)
          |> render_feedback_page(
            params: params,
            errors: EirinchanWeb.ChangesetErrors.translate(changeset)
          )
        end
    end
  end

  defp reject_feedback(conn, params, message, status) do
    if params["json_response"] == "1" do
      conn
      |> put_status(status)
      |> json(%{error: message})
    else
      conn
      |> put_status(status)
      |> render_feedback_page(params: params, errors: %{"rate_limit" => [message]})
    end
  end

  defp invalid_feedback_body?(body) when is_binary(body), do: not String.contains?(body, " ")
  defp invalid_feedback_body?(_body), do: false

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
