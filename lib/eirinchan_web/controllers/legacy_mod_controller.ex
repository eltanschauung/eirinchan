defmodule EirinchanWeb.LegacyModController do
  use EirinchanWeb, :controller

  alias Eirinchan.Bans
  alias Eirinchan.Boards
  alias Eirinchan.IpAccessAuth
  alias Eirinchan.IpCrypt
  alias Eirinchan.Moderation
  alias Eirinchan.Posts
  alias Eirinchan.Reports
  alias EirinchanWeb.{BoardRuntime, ManageSecurity, ModerationAudit, ModeratorPermissions}
  alias EirinchanWeb.PostView

  def show(conn, _params) do
    case conn.query_string do
      "/bans" ->
        redirect(conn, to: ~p"/manage/bans/browser")

      "/themes" ->
        redirect(conn, to: ~p"/manage/themes/browser")

      "/themes/" <> rest ->
        redirect_legacy_theme_path(conn, rest)

      "/IP/" <> ip ->
        redirect_legacy_ip(conn, ip)

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

  defp redirect_legacy_ip(conn, ip) do
    with {:ok, moderator} <- authorized_moderator(conn),
         true <- PostView.can_view_ip?(moderator),
         decoded when not is_nil(decoded) <- IpCrypt.uncloak_ip(ip) do
      redirect(conn, to: "/manage/ip/#{IpCrypt.cloak_ip(decoded)}/browser")
    else
      {:error, :unauthorized} -> redirect(conn, to: "/manage/login")
      false -> send_resp(conn, :forbidden, "Insufficient permissions.")
      nil -> send_resp(conn, :bad_request, "Invalid IP address.")
    end
  end

  defp dispatch_board_action(conn, [uri, "delete", post_id, token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- verify_action_token(conn, "#{uri}/delete/#{post_id}", token),
         {:ok, _result} <-
           Posts.moderate_delete_post(board, post_id,
             config: board_config(board, conn)
           ) do
      ModerationAudit.log(conn, "Deleted post No. #{post_id}", moderator: moderator, board: board)
      redirect(conn, to: "/#{uri}")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "deletefile", post_id, file_index, token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_permission(moderator, :deletefile),
         :ok <- verify_action_token(conn, "#{uri}/deletefile/#{post_id}/#{file_index}", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _updated_post} <-
           Posts.delete_post_file(board, post_id, file_index,
             config: board_config(board, conn)
           ) do
      ModerationAudit.log(conn, "Deleted file from post No. #{PostView.public_post_id(post)}",
        moderator: moderator,
        board: board
      )

      redirect(conn,
        to: thread_destination(board, post, BoardRuntime.request_host(conn))
      )
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "spoiler", post_id, file_index, token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_permission(moderator, :spoilerimage),
         :ok <- verify_action_token(conn, "#{uri}/spoiler/#{post_id}/#{file_index}", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _updated_post} <-
           Posts.spoilerize_post_file(board, post_id, file_index,
             config: board_config(board, conn)
           ) do
      ModerationAudit.log(conn, "Spoilered file on post No. #{PostView.public_post_id(post)}",
        moderator: moderator,
        board: board
      )

      redirect(conn,
        to: thread_destination(board, post, BoardRuntime.request_host(conn))
      )
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "deletebyip", post_id, token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_permission(moderator, :deletebyip),
         :ok <- verify_action_token(conn, "#{uri}/deletebyip/#{post_id}", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _result} <-
           Posts.moderate_delete_posts_by_ip(board, post.ip_subnet,
             config: board_config(board, conn)
           ) do
      ModerationAudit.log(conn, "Deleted posts by IP #{display_ip_for_log(post.ip_subnet)}",
        moderator: moderator,
        board: board
      )

      redirect(conn, to: "/#{uri}")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "deletebyip", post_id, "global", token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_permission(moderator, :deletebyip_global),
         :ok <- verify_action_token(conn, "#{uri}/deletebyip/#{post_id}/global", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _result} <-
           Posts.moderate_delete_posts_by_ip(
             Moderation.list_accessible_boards(moderator),
             post.ip_subnet,
             config_by_board:
               config_map(
                 Moderation.list_accessible_boards(moderator),
                 conn
              )
           ) do
      ModerationAudit.log(conn, "Deleted posts across boards by IP #{display_ip_for_log(post.ip_subnet)}",
        moderator: moderator,
        board: board
      )

      redirect(conn, to: "/#{uri}")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "ban24", post_id, token]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_permission(moderator, :show_ip_global),
         :ok <- verify_action_token(conn, "#{uri}/ban24/#{post_id}", token),
         {:ok, post} <- Posts.get_post(board, post_id),
         {:ok, _post_after_file_delete} <-
           maybe_delete_post_files_for_ban24(board, post, board_config(board, conn)),
         true <- is_binary(post.ip_subnet) and post.ip_subnet != "",
         {:ok, subnet} <- IpAccessAuth.subnet_for_ip(post.ip_subnet),
         {:ok, _ban} <-
           Bans.create_ban(%{
             board_id: nil,
             mod_user_id: moderator.id,
             ip_subnet: subnet,
             reason:
               "Subnet ban from post control for #{display_ip_for_log(post.ip_subnet)} on /#{board.uri}/ No. #{PostView.public_post_id(post)}",
             active: true
           }) do
      ModerationAudit.log(
        conn,
        "Created /24 ban #{subnet} from #{display_ip_for_log(post.ip_subnet)} on post No. #{PostView.public_post_id(post)} and deleted attached files",
        moderator: moderator,
        board: board
      )

      redirect(conn, to: "/#{uri}")
    else
      false -> send_resp(conn, :bad_request, "Post has no IP.")
      {:error, :invalid_ip} -> send_resp(conn, :bad_request, "Invalid IP address.")
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
         :ok <- require_thread_action_permission(moderator, action),
         :ok <- verify_action_token(conn, "#{uri}/#{action}/#{post_id}", token),
         {:ok, _thread} <-
           update_thread_action(
             board,
             post_id,
             action,
             BoardRuntime.request_host(conn)
           ) do
      ModerationAudit.log(conn, "#{humanize_thread_action(action)} thread No. #{post_id}",
        moderator: moderator,
        board: board
      )

      redirect(conn, to: "/#{uri}")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "ban", post_id]) do
    with {:ok, moderator, _board} <- authorized_board(conn, uri),
         :ok <- require_permission(moderator, :ban) do
      redirect(conn, to: "/manage/boards/#{uri}/posts/#{post_id}/ban/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "ban&delete", post_id]) do
    with {:ok, moderator, _board} <- authorized_board(conn, uri),
         :ok <- require_permission(moderator, :bandelete) do
      redirect(conn, to: "/manage/boards/#{uri}/posts/#{post_id}/ban/browser?delete=1")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_board_action(conn, [uri, "move", thread_id]) do
    with {:ok, moderator, board} <- authorized_board(conn, uri),
         :ok <- require_permission(moderator, :move),
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
         :ok <- require_permission(moderator, :move),
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
         :ok <- require_permission(moderator, :editpost) do
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
      ModerationAudit.log(conn, "Dismissed report ##{report.id}",
        moderator: moderator,
        board: report.board
      )

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
      ModerationAudit.log(conn, "Dismissed reports for post No. #{report.post_id}",
        moderator: moderator,
        board: report.board
      )

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
      ModerationAudit.log(conn, "Dismissed reports for IP #{display_ip_for_log(report.ip)}",
        moderator: moderator,
        board: report.board
      )

      redirect(conn, to: "/manage/reports/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_report_action(conn, _parts), do: send_resp(conn, :not_found, "Page not found")

  defp humanize_thread_action("sticky"), do: "Made sticky"
  defp humanize_thread_action("unsticky"), do: "Removed sticky from"
  defp humanize_thread_action("lock"), do: "Locked"
  defp humanize_thread_action("unlock"), do: "Unlocked"
  defp humanize_thread_action("bumplock"), do: "Bumplocked"
  defp humanize_thread_action("bumpunlock"), do: "Removed bumplock from"
  defp humanize_thread_action("cycle"), do: "Enabled cycle on"
  defp humanize_thread_action("uncycle"), do: "Disabled cycle on"
  defp humanize_thread_action(action), do: String.capitalize(action)

  defp display_ip_for_log(nil), do: "hidden IP"
  defp display_ip_for_log(ip), do: IpCrypt.cloak_ip(ip)

  defp dispatch_feedback_action(conn, []) do
    with {:ok, _moderator} <- authorized_moderator(conn) do
      redirect(conn, to: "/manage/feedback/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_feedback_action(conn, [feedback_id, "delete", token]) do
    with {:ok, moderator} <- authorized_moderator(conn),
         :ok <- require_permission(moderator, :feedback_delete),
         :ok <- verify_action_token(conn, "feedback/#{feedback_id}/delete", token),
         {:ok, _feedback} <- Eirinchan.Feedback.delete_feedback(feedback_id) do
      redirect(conn, to: "/manage/feedback/browser")
    else
      error -> legacy_error(conn, error)
    end
  end

  defp dispatch_feedback_action(conn, [feedback_id, "mark_read", token]) do
    with {:ok, moderator} <- authorized_moderator(conn),
         :ok <- require_permission(moderator, :feedback_mark_read),
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

  defp require_permission(moderator, permission) do
    if ModeratorPermissions.allowed?(moderator, permission), do: :ok, else: {:error, :forbidden}
  end

  defp require_thread_action_permission(moderator, action) do
    permission =
      case action do
        "sticky" -> :sticky
        "unsticky" -> :sticky
        "lock" -> :lock
        "unlock" -> :lock
        "bumplock" -> :bumplock
        "bumpunlock" -> :bumplock
        "cycle" -> :cycle
        "uncycle" -> :cycle
      end

    require_permission(moderator, permission)
  end

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

  defp maybe_delete_post_files_for_ban24(board, post, config) do
    if post_has_files?(post) do
      Posts.delete_post_files(board, post.id, config: config)
    else
      {:ok, post}
    end
  end

  defp post_has_files?(post) do
    post.file_path not in [nil, "", "deleted"] or Enum.any?(post.extra_files || [])
  end

  defp legacy_error(conn, {:error, :unauthorized}), do: redirect(conn, to: ~p"/manage/login")
  defp legacy_error(conn, {:error, :forbidden}), do: send_resp(conn, :forbidden, "Forbidden")
  defp legacy_error(conn, {:error, :not_found}), do: send_resp(conn, :not_found, "Page not found")
  defp legacy_error(conn, nil), do: send_resp(conn, :not_found, "Page not found")
  defp legacy_error(conn, false), do: send_resp(conn, :forbidden, "Forbidden")
  defp legacy_error(conn, _), do: send_resp(conn, :unprocessable_entity, "Unprocessable action")

  defp config_map(boards, conn) do
    BoardRuntime.config_map(boards, conn)
  end

  defp thread_destination(board, post, host) do
    config = board_config(board, host)

    thread =
      if is_nil(post.thread_id), do: post, else: elem(Posts.get_post(board, post.thread_id), 1)

    Eirinchan.ThreadPaths.thread_path(board, thread, config)
  rescue
    _ -> "/#{board.uri}"
  end

  defp board_config(board_record, conn) do
    BoardRuntime.board_config(board_record, conn)
  end
end
