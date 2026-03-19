defmodule Eirinchan.Moderation do
  @moduledoc """
  Minimal moderator user store and session authentication.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Moderation.{IpNote, ModBoardAccess, ModMessage, ModUser}
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo

  @spec create_user(map(), keyword()) :: {:ok, ModUser.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    %ModUser{}
    |> ModUser.create_changeset(attrs)
    |> repo.insert()
  end

  @spec get_user(integer(), keyword()) :: ModUser.t() | nil
  def get_user(id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    preload = List.wrap(Keyword.get(opts, :preload, []))

    case repo.get(ModUser, id) do
      nil -> nil
      user -> maybe_preload(user, preload, repo)
    end
  end

  @spec list_users(keyword()) :: [ModUser.t()]
  def list_users(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    preload = List.wrap(Keyword.get(opts, :preload, []))

    ModUser
    |> from(order_by: [asc: :username])
    |> repo.all()
    |> maybe_preload(preload, repo)
  end

  @spec update_user(ModUser.t(), map(), keyword()) :: {:ok, ModUser.t()} | {:error, Ecto.Changeset.t()}
  def update_user(%ModUser{} = user, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    user
    |> ModUser.update_changeset(attrs)
    |> repo.update()
  end

  @spec delete_user(ModUser.t(), keyword()) :: {:ok, ModUser.t()} | {:error, Ecto.Changeset.t()}
  def delete_user(%ModUser{} = user, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.delete(user)
  end

  @spec set_board_accesses(ModUser.t(), [BoardRecord.t()], keyword()) :: {:ok, ModUser.t()} | {:error, term()}
  def set_board_accesses(%ModUser{} = user, boards, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    board_ids = boards |> Enum.map(& &1.id) |> Enum.uniq()

    repo.transaction(fn ->
      repo.delete_all(from access in ModBoardAccess, where: access.mod_user_id == ^user.id)

      Enum.each(board_ids, fn board_id ->
        %ModBoardAccess{}
        |> ModBoardAccess.changeset(%{mod_user_id: user.id, board_id: board_id})
        |> repo.insert!()
      end)
    end)
    |> case do
      {:ok, _result} -> {:ok, user}
      error -> error
    end
  end

  @spec grant_board_access(ModUser.t(), BoardRecord.t(), keyword()) ::
          {:ok, ModBoardAccess.t()} | {:error, Ecto.Changeset.t()}
  def grant_board_access(%ModUser{} = user, %BoardRecord{} = board, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    %ModBoardAccess{}
    |> ModBoardAccess.changeset(%{mod_user_id: user.id, board_id: board.id})
    |> repo.insert(
      on_conflict: :nothing,
      conflict_target: [:mod_user_id, :board_id]
    )
  end

  @spec list_accessible_boards(ModUser.t() | nil, keyword()) :: [BoardRecord.t()]
  def list_accessible_boards(user), do: list_accessible_boards(user, [])

  def list_accessible_boards(nil, _opts), do: []

  def list_accessible_boards(%ModUser{role: "admin"}, opts) do
    Eirinchan.Boards.list_boards(opts)
  end

  def list_accessible_boards(%ModUser{all_boards: true}, opts) do
    Eirinchan.Boards.list_boards(opts)
  end

  def list_accessible_boards(%ModUser{} = user, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.all(
      from board in BoardRecord,
        join: access in ModBoardAccess,
        on: access.board_id == board.id,
        where: access.mod_user_id == ^user.id,
        order_by: [asc: board.uri]
    )
  end

  @spec board_access?(ModUser.t() | nil, BoardRecord.t(), keyword()) :: boolean()
  def board_access?(user, board), do: board_access?(user, board, [])

  def board_access?(nil, _board, _opts), do: false
  def board_access?(%ModUser{role: "admin"}, _board, _opts), do: true
  def board_access?(%ModUser{all_boards: true}, _board, _opts), do: true

  def board_access?(%ModUser{} = user, %BoardRecord{} = board, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.exists?(
      from access in ModBoardAccess,
        where: access.mod_user_id == ^user.id and access.board_id == ^board.id
    )
  end

  @spec authenticate(String.t(), String.t(), keyword()) ::
          {:ok, ModUser.t()} | {:error, :invalid_credentials}
  def authenticate(username, password, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case repo.get_by(ModUser, username: String.trim(username || "")) do
      nil ->
        {:error, :invalid_credentials}

      %ModUser{} = user ->
        if ModUser.verify_password(user, password) do
          user = maybe_upgrade_legacy_password(user, password, repo)
          {:ok, touch_login(user, repo)}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  defp maybe_upgrade_legacy_password(%ModUser{} = user, password, repo) do
    if ModUser.legacy_vichan_password?(user) do
      {:ok, upgraded} =
        user
        |> ModUser.upgrade_legacy_password_changeset(password)
        |> repo.update()

      upgraded
    else
      user
    end
  end

  defp touch_login(user, repo) do
    {:ok, updated} =
      user
      |> ModUser.login_changeset(%{
        last_login_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })
      |> repo.update()

    updated
  end

  @spec add_ip_note(String.t(), map(), keyword()) ::
          {:ok, IpNote.t()} | {:error, Ecto.Changeset.t()}
  def add_ip_note(ip_subnet, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    %IpNote{}
    |> IpNote.changeset(
      attrs
      |> Enum.into(%{})
      |> Map.put(:ip_subnet, normalize_ip(ip_subnet))
    )
    |> repo.insert()
  end

  @spec list_ip_notes(String.t(), keyword()) :: [IpNote.t()]
  def list_ip_notes(ip_subnet, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    board_id = Keyword.get(opts, :board_id)
    board_ids = Keyword.get(opts, :board_ids)

    query =
      from note in IpNote,
        where: note.ip_subnet == ^normalize_ip(ip_subnet),
        order_by: [asc: note.inserted_at],
        preload: [:board, :mod_user]

    query =
      cond do
        board_id ->
          from note in query, where: is_nil(note.board_id) or note.board_id == ^board_id

        is_list(board_ids) ->
          from note in query, where: is_nil(note.board_id) or note.board_id in ^board_ids

        true ->
          query
      end

    repo.all(query)
  end

  @spec list_ip_posts(String.t(), keyword()) :: [Post.t()]
  def list_ip_posts(ip_subnet, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    board_ids = Keyword.get(opts, :board_ids)

    query =
      from post in Post,
        where: post.ip_subnet == ^normalize_ip(ip_subnet),
        order_by: [desc: post.inserted_at, desc: post.id]

    query =
      case board_ids do
        ids when is_list(ids) -> from post in query, where: post.board_id in ^ids
        _ -> query
      end

    repo.all(query)
  end

  @spec update_ip_note(IpNote.t() | integer(), map(), keyword()) ::
          {:ok, IpNote.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_ip_note(note_or_id, attrs, opts \\ [])

  def update_ip_note(%IpNote{} = note, attrs, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    note
    |> IpNote.changeset(attrs)
    |> repo.update()
  end

  def update_ip_note(note_id, attrs, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    case repo.get(IpNote, note_id) do
      nil -> {:error, :not_found}
      note -> update_ip_note(note, attrs, opts)
    end
  end

  @spec delete_ip_note(IpNote.t() | integer(), keyword()) ::
          {:ok, IpNote.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_ip_note(note_or_id, opts \\ [])

  def delete_ip_note(%IpNote{} = note, opts) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.delete(note)
  end

  def delete_ip_note(note_id, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    case repo.get(IpNote, note_id) do
      nil -> {:error, :not_found}
      note -> delete_ip_note(note, opts)
    end
  end

  @spec send_message(ModUser.t(), map(), keyword()) ::
          {:ok, ModMessage.t()} | {:error, Ecto.Changeset.t()}
  def send_message(%ModUser{} = sender, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    %ModMessage{}
    |> ModMessage.changeset(
      attrs
      |> Enum.into(%{})
      |> Map.put(:sender_id, sender.id)
    )
    |> repo.insert()
    |> case do
      {:ok, message} -> {:ok, repo.preload(message, [:sender, :recipient, :reply_to])}
      error -> error
    end
  end

  @spec list_inbox(ModUser.t(), keyword()) :: [ModMessage.t()]
  def list_inbox(%ModUser{} = user, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.all(
      from message in ModMessage,
        where: message.recipient_id == ^user.id or message.sender_id == ^user.id,
        order_by: [desc: message.inserted_at, desc: message.id],
        preload: [:sender, :recipient, :reply_to]
    )
  end

  @spec list_recipients(ModUser.t(), keyword()) :: [ModUser.t()]
  def list_recipients(%ModUser{id: user_id}, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.all(from user in ModUser, where: user.id != ^user_id, order_by: [asc: user.username])
  end

  @spec count_unread_messages(ModUser.t(), keyword()) :: non_neg_integer()
  def count_unread_messages(user, opts \\ [])
  def count_unread_messages(nil, _opts), do: 0

  def count_unread_messages(%ModUser{} = user, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.aggregate(
      from(message in ModMessage,
        where: message.recipient_id == ^user.id and is_nil(message.read_at)
      ),
      :count
    )
  end

  @spec mark_inbox_read(ModUser.t(), keyword()) :: :ok
  def mark_inbox_read(%ModUser{} = user, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    _ =
      repo.update_all(
        from(message in ModMessage,
          where: message.recipient_id == ^user.id and is_nil(message.read_at)
        ),
        set: [read_at: now]
      )

    :ok
  end

  defp normalize_ip(ip) when is_binary(ip), do: String.trim(ip)

  defp normalize_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_ip(_ip), do: nil

  defp maybe_preload(records, [], _repo), do: records
  defp maybe_preload(records, preload, repo), do: repo.preload(records, preload)
end
