defmodule EirinchanWeb.FeedbackController do
  use EirinchanWeb, :controller

  alias Eirinchan.EventLog
  alias Eirinchan.Feedback.Submission
  alias Eirinchan.PublicPages
  alias Eirinchan.Settings
  alias EirinchanWeb.RequestMeta

  def create(conn, params) do
    request = RequestMeta.public_identity(conn)

    case Submission.submit(params, request) do
      {:ok, _entry} ->
        if params["json_response"] == "1" do
          # Same public receipt for accepted and silently discarded submissions.
          json(conn, %{status: "ok"})
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

      {:error, reason, message} when reason in [:body_shape, :rate_limited] ->
        EventLog.log(conn, "feedback.rejected", %{outcome: Atom.to_string(reason)})
        status = if reason == :rate_limited, do: :too_many_requests, else: :unprocessable_entity
        reject_feedback(conn, params, message, status)
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
        errors: Keyword.get(opts, :errors),
        config: Settings.effective_instance_config()
      )

    conn
    |> Phoenix.Controller.put_view(EirinchanWeb.PageHTML)
    |> render(:feedback, assigns)
  end
end
