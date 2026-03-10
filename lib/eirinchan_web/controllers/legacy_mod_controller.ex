defmodule EirinchanWeb.LegacyModController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Moderation
  alias Eirinchan.Posts
  alias Eirinchan.Reports
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.ManageSecurity

  def show(conn, _params) do
    case conn.query_string do
      "/themes" ->
        redirect(conn, to: ~p"/manage/themes/browser")

      "/themes/" <> rest ->
        redirect_legacy_theme_path(conn, rest)

      "/IP/" <> ip ->
        redirect(conn, to: "/manage/ip/#{ip}/browser")

      "/feedback" <> rest ->
        dispatch_feedback_action(conn, String.split(rest, "/", trim: true))

      "/reports/" <> rest ->
        dispatch_report_action(conn, String.split(rest, "/", trim: true))

      "/" <> rest ->
        dispatch_board_action(conn, String.split(rest, "/", trim: true))

      _ ->
        send_resp(conn, :not_found, "Page not found")
    end
  end

  defp redirect_legacy_theme_path(conn, rest) do
    case String.split(rest, "/") do
      [theme] ->
        redirect(conn, to: "/manage/themes/browser/#{theme}")

      [theme, "rebuild" | _] ->
        redirect(conn, to: "/manage/themes/browser/#{theme}")

      [theme, "uninstall" | _] ->
        redirect(conn, to: "/manage/themes/browser/#{theme}")

      _ ->
        send_resp(conn, :not_found, "Page not found")
    end
  end

  defp dispatch_board_action(conn, [uri, "delete", post_id, token]) do
    with {:ok, _moderator, board} <- authorized_board(conn, uri),
         :ok <- verify_action_token(conn, "#{uri}/delete/#{post_id}", token),
         {:ok, _result} <-
           Posts.moderate_delete_post(board, post_id,
             config: board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      redirect(conn, to: "/#{uri}")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "deletefile", post_id, file_index, token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 10),
         :ok <- verify_action_token(conn, "#{uri}/deletefile/#{post_id}/#{file_index}", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _updated_post} <-
           Posts.delete_post_file(board, post_id, file_index,
             config: board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      redirect(conn,
        to: thread_destination(board, post, EirinchanWeb.RequestMeta.request_host(conn))
      )
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "spoiler", post_id, file_index, token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 10),
         :ok <- verify_action_token(conn, "#{uri}/spoiler/#{post_id}/#{file_index}", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _updated_post} <-
           Posts.spoilerize_post_file(board, post_id, file_index,
             config: board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      redirect(conn,
        to: thread_destination(board, post, EirinchanWeb.RequestMeta.request_host(conn))
      )
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "deletebyip", post_id, token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 20),
         :ok <- verify_action_token(conn, "#{uri}/deletebyip/#{post_id}", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _result} <-
           Posts.moderate_delete_posts_by_ip(board, post.ip_subnet,
             config: board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      redirect(conn, to: "/#{uri}")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "deletebyip", post_id, "global", token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 30),
         :ok <- verify_action_token(conn, "#{uri}/deletebyip/#{post_id}/global", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _result} <-
           Posts.moderate_delete_posts_by_ip(
             Moderation.list_accessible_boards(moderator),
             post.ip_subnet,
             config_by_board:
               config_map(
                 Moderation.list_accessible_boards(moderator),
                 EirinchanWeb.RequestMeta.request_host(conn)
               )
           ) do
      redirect(conn, to: "/#{uri}")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, action, post_id, token])
       when action in [
              "sticky",
              "unsticky",
              "lock",
              "unlock",
              "bumplock",
              "bumpunlock",
              "cycle",
              "uncycle"
            ] do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 20),
         :ok <- verify_action_token(conn, "#{uri}/#{action}/#{post_id}", token),
         {:ok, _thread} <-
           update_thread_action(
             board,
             post_id,
             action,
             EirinchanWeb.RequestMeta.request_host(conn)
           ) do
      redirect(conn, to: "/#{uri}")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "ban", post_id]) do
    with {:ok, moderator, _board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 20) do
      redirect(conn, to: "/manage/boards/#{uri}/posts/#{post_id}/ban/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "ban&delete", post_id]) do
    with {:ok, moderator, _board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 20) do
      redirect(conn, to: "/manage/boards/#{uri}/posts/#{post_id}/ban/browser?delete=1")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "move", thread_id]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 20),
         {:ok, thread} <- Posts.get_post(board, thread_id),
         true <- is_nil(thread.thread_id) do
      redirect(conn, to: "/manage/boards/#{uri}/threads/#{thread_id}/move/browser")
    else
      false -> send_resp(conn, :not_found, "Thread not found")
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "move_reply", post_id]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 20),
         {:ok, post} <- Posts.get_post(board, post_id),
         false <- is_nil(post.thread_id) do
      redirect(conn, to: "/manage/boards/#{uri}/posts/#{post_id}/move/browser")
    else
      true -> send_resp(conn, :not_found, "Reply not found")
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "edit", post_id]) do
    with {:ok, moderator, _board} <- authorized_board(conn, uri),
         :ok <- require_role(moderator, 30) do
      redirect(conn, to: "/manage/boards/#{uri}/posts/#{post_id}/edit/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, _parts), do: send_resp(conn, :not_found, "Page not found")

  defp dispatch_report_action(conn, [report_id, "dismiss", token]) do
    with {:ok, moderator} <- authorized_moderator(conn),
         report when not is_nil(report) <- Reports.get_report(report_id),
         :ok <- authorize_report(moderator, report),
         :ok <- verify_action_token(conn, "reports/#{report_id}/dismiss", token),
         {:ok, _report} <- Reports.dismiss_report(report.board, report_id) do
      redirect(conn, to: "/manage/reports/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_report_action(conn, [report_id, "dismiss&post", token]) do
    with {:ok, moderator} <- authorized_moderator(conn),
         report when not is_nil(report) <- Reports.get_report(report_id),
         :ok <- authorize_report(moderator, report),
         :ok <- verify_action_token(conn, "reports/#{report_id}/dismiss&post", token),
         {:ok, _count} <- Reports.dismiss_reports_for_post(report.board, report.post_id) do
      redirect(conn, to: "/manage/reports/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_report_action(conn, [report_id, "dismiss&all", token]) do
    with {:ok, moderator} <- authorized_moderator(conn),
         report when not is_nil(report) <- Reports.get_report(report_id),
         :ok <- authorize_report(moderator, report),
         :ok <- verify_action_token(conn, "reports/#{report_id}/dismiss&all", token),
         {:ok, _count} <-
           Reports.dismiss_reports_for_ip(accessible_report_scope(moderator), report.ip) do
      redirect(conn, to: "/manage/reports/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_report_action(conn, _parts), do: send_resp(conn, :not_found, "Page not found")

  defp dispatch_feedback_action(conn, []) do
    with {:ok, _moderator} <- authorized_moderator(conn) do
      redirect(conn, to: "/manage/feedback/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_feedback_action(conn, [feedback_id, "delete", token]) do
    with {:ok, moderator} <- authorized_moderator(conn),
         :ok <- require_role(moderator, 10),
         :ok <- verify_action_token(conn, "feedback/#{feedback_id}/delete", token),
         {:ok, _feedback} <- Eirinchan.Feedback.delete_feedback(feedback_id) do
      redirect(conn, to: "/manage/feedback/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_feedback_action(conn, [feedback_id, "mark_read", token]) do
    with {:ok, moderator} <- authorized_moderator(conn),
         :ok <- require_role(moderator, 10),
         :ok <- verify_action_token(conn, "feedback/#{feedback_id}/mark_read", token),
         {:ok, _feedback} <- Eirinchan.Feedback.mark_read(feedback_id) do
      redirect(conn, to: "/manage/feedback/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_feedback_action(conn, _parts), do: send_resp(conn, :not_found, "Page not found")

  defp authorized_board(conn, uri) do
    case {conn.assigns[:current_moderator], Boards.get_board_by_uri(uri)} do
      {nil, _} ->
        {:error, :unauthorized}

      {_moderator, nil} ->
        {:error, :not_found}

      {moderator, board} ->
        if Moderation.board_access?(moderator, board) do
          {:ok, moderator, board}
        else
          {:error, :forbidden}
        end
    end
  end

  defp authorized_moderator(%Plug.Conn{assigns: %{current_moderator: nil}}),
    do: {:error, :unauthorized}

  defp authorized_moderator(%Plug.Conn{assigns: %{current_moderator: moderator}}),
    do: {:ok, moderator}

  defp require_role(%{role: "admin"}, _level), do: :ok
  defp require_role(%{role: "mod"}, level) when level <= 20, do: :ok
  defp require_role(%{role: "janitor"}, level) when level <= 10, do: :ok
  defp require_role(_, _), do: {:error, :forbidden}

  defp verify_action_token(conn, path, token) do
    if ManageSecurity.valid_action_token?(conn.assigns[:secure_manage_token], path, token) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_report(%{role: "admin"}, _report), do: :ok

  defp authorize_report(moderator, %{board: board}) when not is_nil(board) do
    if Moderation.board_access?(moderator, board), do: :ok, else: {:error, :forbidden}
  end

  defp authorize_report(_moderator, _report), do: {:error, :not_found}

  defp accessible_report_scope(%{role: "admin"}), do: nil
  defp accessible_report_scope(moderator), do: Moderation.list_accessible_boards(moderator)

  defp update_thread_action(board, post_id, action, host) do
    attrs =
      case action do
        "sticky" -> %{"sticky" => true}
        "unsticky" -> %{"sticky" => false}
        "lock" -> %{"locked" => true}
        "unlock" -> %{"locked" => false}
        "bumplock" -> %{"sage" => true}
        "bumpunlock" -> %{"sage" => false}
        "cycle" -> %{"cycle" => true}
        "uncycle" -> %{"cycle" => false}
      end

    Posts.update_thread_state(board, post_id, attrs, config: board_config(board, host))
  end

  defp legacy_error(conn, {:error, :unauthorized}), do: redirect(conn, to: ~p"/manage/login")
  defp legacy_error(conn, {:error, :forbidden}), do: send_resp(conn, :forbidden, "Forbidden")
  defp legacy_error(conn, {:error, :not_found}), do: send_resp(conn, :not_found, "Page not found")
  defp legacy_error(conn, nil), do: send_resp(conn, :not_found, "Page not found")
  defp legacy_error(conn, false), do: send_resp(conn, :forbidden, "Forbidden")
  defp legacy_error(conn, _), do: send_resp(conn, :unprocessable_entity, "Unprocessable action")

  defp config_map(boards, host) do
    Map.new(boards, fn board -> {board.id, board_config(board, host)} end)
  end

  defp thread_destination(board, post, host) do
    config = board_config(board, host)

    thread =
      if is_nil(post.thread_id), do: post, else: elem(Posts.get_post(board, post.thread_id), 1)

    Eirinchan.ThreadPaths.thread_path(board, thread, config)
  rescue
    _ -> "/#{board.uri}"
  end

  defp board_config(board_record, request_host) do
    Config.compose(nil, Settings.current_instance_config(), board_record.config_overrides,
      board: Eirinchan.Boards.BoardRecord.to_board(board_record),
      request_host: request_host
    )
  end
end
