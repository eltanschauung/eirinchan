defmodule EirinchanWeb.IpManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.IpCrypt
  alias Eirinchan.Posts
  alias Eirinchan.Moderation
  alias EirinchanWeb.PostView

  action_fallback EirinchanWeb.FallbackController

  def board_show(conn, %{"uri" => uri, "ip" => ip}) do
    with {:ok, decoded_ip} <- decode_ip_param(ip),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         :ok <- authorize_ip_view(conn, board) do
      posts = Moderation.list_ip_posts(decoded_ip, board_ids: [board.id])
      notes = Moderation.list_ip_notes(decoded_ip, board_id: board.id)

      render(conn, :show,
        ip: decoded_ip,
        posts: posts,
        notes: notes,
        moderator: conn.assigns.current_moderator
      )
    else
      nil -> {:error, :not_found}
      {:error, :invalid_ip} -> {:error, :bad_request}
      error -> error
    end
  end

  def show(conn, %{"ip" => ip}) do
    with {:ok, decoded_ip} <- decode_ip_param(ip),
         :ok <- authorize_ip_view(conn, nil) do
      boards = Moderation.list_accessible_boards(conn.assigns.current_moderator)
      posts = Moderation.list_ip_posts(decoded_ip, board_ids: Enum.map(boards, & &1.id))
      notes = Moderation.list_ip_notes(decoded_ip, board_ids: Enum.map(boards, & &1.id))

      render(conn, :show,
        ip: decoded_ip,
        posts: posts,
        notes: notes,
        moderator: conn.assigns.current_moderator
      )
    end
  end

  def create_note(conn, %{"uri" => uri, "ip" => ip, "body" => body}) do
    with {:ok, decoded_ip} <- decode_ip_param(ip),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         :ok <- authorize_ip_view(conn, board),
         {:ok, note} <-
           Moderation.add_ip_note(decoded_ip, %{
             body: body,
             board_id: board.id,
             mod_user_id: conn.assigns.current_moderator.id
           }) do
      conn
      |> put_status(:created)
      |> render(:note, note: note, moderator: conn.assigns.current_moderator)
    else
      nil -> {:error, :not_found}
      {:error, :invalid_ip} -> {:error, :bad_request}
      error -> error
    end
  end

  def update_note(conn, %{"uri" => uri, "ip" => _ip, "id" => id, "body" => body}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         :ok <- authorize_ip_view(conn, board),
         {:ok, note} <- load_board_note(id, board.id),
         {:ok, note} <- Moderation.update_ip_note(note, %{body: body}) do
      render(conn, :note, note: note, moderator: conn.assigns.current_moderator)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete_note(conn, %{"uri" => uri, "ip" => _ip, "id" => id}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         :ok <- authorize_ip_view(conn, board),
         {:ok, note} <- load_board_note(id, board.id),
         {:ok, _note} <- Moderation.delete_ip_note(note) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete_posts(conn, %{"ip" => ip}) do
    with {:ok, decoded_ip} <- decode_ip_param(ip),
         :ok <- authorize_ip_view(conn, nil),
         {:ok, result} <-
           Moderation.list_accessible_boards(conn.assigns.current_moderator)
           |> then(
             &Posts.moderate_delete_posts_by_ip(&1, decoded_ip,
               config_by_board: config_map(&1, EirinchanWeb.RequestMeta.request_host(conn))
             )
           ) do
      json(conn, %{data: result})
    else
      {:error, :invalid_ip} -> {:error, :bad_request}
      error -> error
    end
  end

  def delete_board_posts(conn, %{"uri" => uri, "ip" => ip}) do
    with {:ok, decoded_ip} <- decode_ip_param(ip),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         :ok <- authorize_ip_view(conn, board),
         {:ok, result} <-
           Posts.moderate_delete_posts_by_ip(board, decoded_ip,
             config: board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      json(conn, %{data: result})
    else
      nil -> {:error, :not_found}
      {:error, :invalid_ip} -> {:error, :bad_request}
      error -> error
    end
  end

  defp authorize_board(conn, board) do
    if Moderation.board_access?(conn.assigns.current_moderator, board) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_ip_view(conn, board) do
    if PostView.can_view_ip?(conn.assigns.current_moderator, board) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp load_board_note(id, board_id) do
    case Eirinchan.Repo.get(Eirinchan.Moderation.IpNote, id) do
      %{board_id: ^board_id} = note -> {:ok, note}
      _ -> {:error, :not_found}
    end
  end

  defp decode_ip_param(ip) do
    case IpCrypt.uncloak_ip(ip) do
      nil -> {:error, :invalid_ip}
      decoded -> {:ok, decoded}
    end
  end

  defp config_map(boards, host) do
    Map.new(boards, fn board -> {board.id, board_config(board, host)} end)
  end

  defp board_config(board_record, request_host) do
    Eirinchan.Runtime.Config.compose(
      nil,
      Eirinchan.Settings.current_instance_config(),
      board_record.config_overrides,
      board: Eirinchan.Boards.BoardRecord.to_board(board_record),
      request_host: request_host
    )
  end
end
