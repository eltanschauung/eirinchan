defmodule EirinchanWeb.PublicPostEditController do
  use EirinchanWeb, :controller

  alias Eirinchan.Antispam
  alias Eirinchan.Boards
  alias Eirinchan.Posts
  alias Eirinchan.Settings
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.{Announcements, BoardChrome, PostView, PublicShell, RequestMeta}
  alias Eirinchan.Repo

  plug EirinchanWeb.Plugs.LoadBoard
  plug :assign_public_shell

  def show(conn, %{"board" => _board_uri, "post_id" => post_id}) do
    board = conn.assigns.current_board

    with {:ok, post} <- Posts.get_post(board, post_id) do
      render_form(conn, post)
    else
      _ -> send_resp(conn, :not_found, "Post not found")
    end
  end

  def update(conn, %{"board" => _board_uri, "post_id" => post_id} = params) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    moderator = edit_override_moderator(conn.assigns[:current_moderator], board)

    request = %{
      remote_ip: RequestMeta.effective_remote_ip(conn),
      forwarded_for: RequestMeta.forwarded_for(conn),
      referer: List.first(get_req_header(conn, "referer")),
      moderator: moderator
    }

    with :ok <- Antispam.check_public_action(board, :edit, params, request, config),
         :ok <- maybe_log_edit_attempt(board, params, request, moderator),
         {:ok, post} <- Posts.edit_post(board, post_id, params, config: config, moderator: moderator) do
      redirect(conn, to: return_path(board, post, config))
    else
      {:error, :invalid_password} ->
        with {:ok, post} <- Posts.get_post(board, post_id) do
          conn
          |> put_status(:unprocessable_entity)
          |> render_form(post,
            error: "Incorrect password.",
            form_params: Map.take(params, ["name", "email", "subject", "body", "password"])
          )
        else
          _ -> send_resp(conn, :not_found, "Post not found")
        end

      {:error, :body_required} ->
        render_edit_error(conn, board, post_id, params, "Body required.")

      {:error, :body_too_long} ->
        render_edit_error(conn, board, post_id, params, "Body too long.")

      {:error, :too_many_lines} ->
        render_edit_error(conn, board, post_id, params, "Too many lines.")

      {:error, :antispam} ->
        render_edit_error(conn, board, post_id, params, "Wait a while before editing again, please.", :too_many_requests)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_edit_error(conn, board, post_id, params, error_message(changeset))

      _ ->
        send_resp(conn, :not_found, "Post not found")
    end
  end

  defp render_edit_error(conn, board, post_id, params, message, status \\ :unprocessable_entity) do
    with {:ok, post} <- Posts.get_post(board, post_id) do
      conn
      |> put_status(status)
      |> render_form(post,
        error: message,
        form_params: Map.take(params, ["name", "email", "subject", "body", "password"])
      )
    else
      _ -> send_resp(conn, :not_found, "Post not found")
    end
  end

  defp render_form(conn, post, opts \\ []) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    form_params = Keyword.get(opts, :form_params, %{})
    post = Repo.preload(post, :thread)

    render(conn, :edit,
      board: board,
      board_chrome: BoardChrome.for_board(board),
      current_moderator: conn.assigns[:current_moderator],
      error: Keyword.get(opts, :error),
      global_message_html:
        Announcements.global_message_html(Settings.current_instance_config(), surround_hr: true, board: board),
      page_title: "Edit post",
      post: post,
      form: %{
        name: Map.get(form_params, "name", post.name),
        email: Map.get(form_params, "email", post.email),
        subject: Map.get(form_params, "subject", post.subject),
        body: Map.get(form_params, "body", post.body),
        password: Map.get(form_params, "password", "")
      },
      return_path: return_path(board, post, config),
      admin_override?: !is_nil(edit_override_moderator(conn.assigns[:current_moderator], board))
    )
  end

  defp assign_public_shell(conn, _opts) do
    boards = Boards.list_boards()
    stylesheet = conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"

    conn
    |> assign(:public_shell, true)
    |> assign(:base_stylesheet, "/stylesheets/style.css")
    |> assign(:primary_stylesheet, stylesheet)
    |> assign(:primary_stylesheet_id, "stylesheet")
    |> assign(:body_class, "8chan vichan is-not-moderator active-page")
    |> assign(:body_data_stylesheet, Path.basename(stylesheet))
    |> assign(:watcher_count, 0)
    |> assign(:watcher_unread_count, 0)
    |> assign(:watcher_you_count, 0)
    |> assign(:global_boardlist_groups, PostView.boardlist_groups(boards))
    |> assign(
      :head_meta,
      PublicShell.head_meta("page",
        resource_version: conn.assigns[:asset_version],
        theme_label: conn.assigns[:theme_label],
        theme_options: conn.assigns[:theme_options],
        browser_timezone: conn.assigns[:browser_timezone],
        browser_timezone_offset_minutes: conn.assigns[:browser_timezone_offset_minutes]
      )
    )
    |> assign(:javascript_urls, PublicShell.javascript_urls(:search))
    |> assign(:extra_stylesheets, [])
    |> assign(:skip_app_stylesheet, true)
    |> assign(:skip_flash_group, true)
    |> assign(:hide_theme_switcher, true)
  end

  defp return_path(board, post, config) do
    post = Repo.preload(post, :thread)
    thread = post.thread || post
    ThreadPaths.thread_path(board, thread, config) <> "#p#{PostView.public_post_id(post)}"
  end

  defp maybe_log_edit_attempt(board, params, request, moderator) do
    if is_nil(moderator) do
      _ = Antispam.log_public_action(board, :edit, params, request)
    end

    :ok
  end

  defp edit_override_moderator(%{role: "admin"} = moderator, board) do
    if Eirinchan.Moderation.board_access?(moderator, board), do: moderator, else: nil
  end

  defp edit_override_moderator(_moderator, _board), do: nil

  defp error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
