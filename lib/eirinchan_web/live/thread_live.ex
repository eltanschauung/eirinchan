defmodule EirinchanWeb.ThreadLive do
  use EirinchanWeb, :live_view

  import Phoenix.Controller, only: [get_csrf_token: 0]

  alias Eirinchan.{Announcement, Boards, Moderation, Posts}
  alias EirinchanWeb.{BoardChrome, PostView}

  @tick_interval 1_000
  @poll_interval 10

  embed_templates "thread_live_html/*"

  @impl true
  def render(assigns), do: thread(assigns)

  @impl true
  def mount(_params, session, socket) do
    request_host = session["request_host"]
    board_record = Boards.get_board_by_uri!(session["board_uri"])

    {:ok, runtime_context} =
      Boards.open_board(board_record.uri, request_host: request_host)

    board = runtime_context.board
    config = runtime_context.config

    moderator =
      case session["current_moderator_id"] do
        nil -> nil
        id -> Moderation.get_user(id)
      end

    summary = load_summary!(board_record, session["thread_id"])
    page_num = thread_page(board_record, summary.thread.id, config)

    socket =
      socket
      |> assign(
        board: board,
        config: config,
        board_record: board_record,
        summary: summary,
        replies: summary.replies,
        page_num: page_num,
        boards: Boards.list_boards(),
        board_chrome: BoardChrome.for_board(board_record),
        announcement: Announcement.current(),
        current_moderator: moderator,
        secure_manage_token: session["secure_manage_token"],
        reply_form: default_reply_form(config),
        auto_update: true,
        update_secs: @poll_interval,
        request_host: request_host
      )
      |> allow_upload(:files, accept: :any, max_entries: max(config.max_images, 1))

    if connected?(socket) do
      Process.send_after(self(), :tick, @tick_interval)
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("reply", params, socket) do
    board = socket.assigns.board
    board_record = socket.assigns.board_record
    config = socket.assigns.config
    thread = socket.assigns.summary.thread

    reply_params =
      params
      |> Map.put("thread", Integer.to_string(thread.id))
      |> Map.put("board", board.uri)
      |> merge_upload_params(socket)

    request = %{
      referer: "http://#{socket.assigns.request_host}/#{board.uri}/res/#{thread.id}.html",
      remote_ip: {127, 0, 0, 1},
      forwarded_for: nil,
      moderator: socket.assigns.current_moderator
    }

    case Posts.create_post(board_record, reply_params, config: config, request: request) do
      {:ok, post, _meta} ->
        summary = load_summary!(board_record, thread.id)

        socket =
          socket
          |> assign(summary: summary, replies: summary.replies, reply_form: default_reply_form(config), update_secs: @poll_interval)
          |> push_event("reply-visible", %{id: post.id})

        {:noreply, socket}

      {:error, reason} when is_atom(reason) ->
        {:noreply,
         socket
         |> assign(reply_form: Map.merge(default_reply_form(config), params))
         |> put_flash(:error, error_message(reason, config))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(reply_form: Map.merge(default_reply_form(config), params)) |> put_flash(:error, inspect(changeset.errors))}
    end
  end

  @impl true
  def handle_event("update-now", _params, socket) do
    {:noreply, refresh_thread(socket)}
  end

  @impl true
  def handle_event("toggle-auto-update", %{"value" => value}, socket) do
    enabled = value == "true"
    {:noreply, assign(socket, auto_update: enabled, update_secs: @poll_interval)}
  end

  @impl true
  def handle_info(:tick, socket) do
    socket =
      if socket.assigns.auto_update do
        if socket.assigns.update_secs <= 1 do
          socket
          |> refresh_thread()
          |> assign(update_secs: @poll_interval)
        else
          assign(socket, update_secs: socket.assigns.update_secs - 1)
        end
      else
        socket
      end

    Process.send_after(self(), :tick, @tick_interval)
    {:noreply, socket}
  end

  defp refresh_thread(socket) do
    summary = load_summary!(socket.assigns.board_record, socket.assigns.summary.thread.id)
    assign(socket, summary: summary, replies: summary.replies)
  end

  defp load_summary!(board_record, thread_id) do
    case Posts.get_thread_view(board_record, thread_id) do
      {:ok, summary} -> summary
      {:error, :not_found} -> raise "thread not found"
    end
  end

  defp thread_page(board_record, thread_id, config) do
    case Posts.find_thread_page(board_record, thread_id, config: config) do
      {:ok, value} -> value
      _ -> 1
    end
  end

  defp merge_upload_params(params, socket) do
    uploads =
      consume_uploaded_entries(socket, :files, fn %{path: path, client_name: name, client_type: type}, _entry ->
        {:ok, %Plug.Upload{path: path, filename: name, content_type: type}}
      end)

    Enum.with_index(uploads)
    |> Enum.reduce(params, fn {upload, index}, acc ->
      key = if index == 0, do: "file", else: "file#{index + 1}"
      Map.put(acc, key, upload)
    end)
  end

  defp default_reply_form(config) do
    %{
      "name" => "",
      "email" => "",
      "subject" => "",
      "body" => "",
      "password" => "",
      "embed" => "",
      "user_flag" => config.default_user_flag || "",
      "tag" => "",
      "no_country" => false,
      "spoiler" => false
    }
  end

  defp error_message(reason, config) do
    case reason do
      :invalid_referer -> config.error.referer
      :file_required -> config.error.file_required
      :invalid_file_type -> config.error.filetype
      :invalid_embed -> config.error.invalid_embed
      :body_too_long -> config.error.toolong_body
      :too_many_lines -> config.error.toomanylines
      :thread_not_found -> "Thread not found"
      _ -> "Post failed"
    end
  end
end
