defmodule Eirinchan.ModerationLog do
  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Moderation.LogEntry
  alias Eirinchan.Moderation.ModUser
  alias Eirinchan.Repo

  @default_page_size 15

  def default_page_size, do: @default_page_size

  def log_action(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    %LogEntry{}
    |> LogEntry.changeset(Enum.into(attrs, %{}))
    |> repo.insert()
  end

  def list_entries(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = max(Keyword.get(opts, :page_size, @default_page_size), 1)
    offset = (page - 1) * page_size

    query =
      from [log, mod_user] in filtered_query(opts),
        order_by: [desc: log.inserted_at, desc: log.id],
        limit: ^page_size,
        offset: ^offset

    query
    |> repo.all()
    |> repo.preload(:mod_user)
  end

  def count_entries(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    opts
    |> filtered_query()
    |> repo.aggregate(:count, :id)
  end

  def list_recent_entries_by_text(text, opts \\ []) when is_binary(text) do
    repo = Keyword.get(opts, :repo, Repo)
    limit = max(Keyword.get(opts, :limit, 50), 1)

    query =
      from [log, _mod_user] in filtered_query(Keyword.put(opts, :text, text)),
        order_by: [desc: log.inserted_at, desc: log.id],
        limit: ^limit

    query
    |> repo.all()
    |> repo.preload(:mod_user)
  end

  defp filtered_query(opts) do
    username =
      opts
      |> Keyword.get(:username)
      |> normalize_filter()

    board_uri =
      opts
      |> Keyword.get(:board_uri)
      |> normalize_filter()

    text =
      opts
      |> Keyword.get(:text)
      |> normalize_filter()

    query =
      from log in LogEntry,
        left_join: mod_user in ModUser,
        on: mod_user.id == log.mod_user_id

    query =
      if is_binary(username) do
        from [log, mod_user] in query, where: mod_user.username == ^username
      else
        query
      end

    query =
      if is_binary(board_uri) do
        from [log, mod_user] in query, where: log.board_uri == ^board_uri
      else
        query
      end

    if is_binary(text) do
      pattern = "%" <> text <> "%"
      from [log, mod_user] in query, where: ilike(log.text, ^pattern)
    else
      query
    end
  end

  defp normalize_filter(nil), do: nil

  defp normalize_filter(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
