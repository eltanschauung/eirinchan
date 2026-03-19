defmodule EirinchanWeb.BrowserEntries do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings

  @spec post_entries([Post.t()], [BoardRecord.t()] | map(), String.t() | nil, keyword()) :: [map()]
  def post_entries(posts, boards, request_host, opts \\ []) when is_list(posts) do
    repo = Keyword.get(opts, :repo, Repo)
    posts = repo.preload(posts, [:board, :extra_files])

    board_map = normalize_board_map(posts, boards)
    thread_map = load_thread_map(posts, repo)
    config_map = build_config_map(board_map, request_host)

    Enum.map(posts, fn post ->
      board = Map.fetch!(board_map, post.board_id)

      %{
        post: post,
        board: board,
        thread: Map.get(thread_map, post.thread_id || post.id, post),
        config: Map.fetch!(config_map, board.id)
      }
    end)
  end

  @spec grouped_post_entries([Post.t()], [BoardRecord.t()] | map(), String.t() | nil, keyword()) ::
          [%{board: BoardRecord.t(), entries: [map()]}]
  def grouped_post_entries(posts, boards, request_host, opts \\ []) do
    posts
    |> post_entries(boards, request_host, opts)
    |> Enum.group_by(& &1.board.id)
    |> Enum.sort_by(fn {board_id, _entries} -> board_id end)
    |> Enum.map(fn {_board_id, entries} ->
      %{board: hd(entries).board, entries: entries}
    end)
  end

  defp normalize_board_map(posts, boards) when is_list(boards) do
    boards
    |> Map.new(&{&1.id, &1})
    |> then(&normalize_board_map(posts, &1))
  end

  defp normalize_board_map(posts, boards) when is_map(boards) do
    Enum.reduce(posts, boards, fn post, acc ->
      board =
        Map.get(acc, post.board_id) ||
          post.board ||
          Boards.get_board!(post.board_id)

      Map.put(acc, board.id, board)
    end)
  end

  defp load_thread_map([], _repo), do: %{}

  defp load_thread_map(posts, repo) do
    thread_ids =
      posts
      |> Enum.map(&(&1.thread_id || &1.id))
      |> Enum.uniq()

    repo.all(from post in Post, where: post.id in ^thread_ids)
    |> repo.preload(:extra_files)
    |> Map.new(&{&1.id, &1})
  end

  defp build_config_map(board_map, request_host) do
    Map.new(board_map, fn {board_id, board} ->
      {board_id, effective_board_config(board, request_host)}
    end)
  end

  defp effective_board_config(board_record, request_host) do
    Config.compose(nil, Settings.current_instance_config(), board_record.config_overrides || %{},
      board: BoardRecord.to_board(board_record),
      request_host: request_host
    )
  end
end
