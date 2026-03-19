defmodule EirinchanWeb.BrowserEntries do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Settings
  alias EirinchanWeb.BoardRuntime

  @spec post_entries([Post.t()], [BoardRecord.t()] | map(), String.t() | nil, keyword()) :: [map()]
  def post_entries(posts, boards, request_host, opts \\ []) when is_list(posts) do
    repo = Keyword.get(opts, :repo, Repo)
    posts = ensure_post_preloads(posts, repo)

    board_map = normalize_board_map(posts, boards, repo)
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

  defp normalize_board_map(posts, boards, repo) when is_list(boards) do
    boards
    |> Map.new(&{&1.id, &1})
    |> then(&normalize_board_map(posts, &1, repo))
  end

  defp normalize_board_map(posts, boards, repo) when is_map(boards) do
    boards =
      Enum.reduce(posts, boards, fn post, acc ->
        case loaded_assoc(post.board) do
          %BoardRecord{} = board -> Map.put(acc, board.id, board)
          _ -> acc
        end
      end)

    missing_ids =
      posts
      |> Enum.map(& &1.board_id)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(boards, &1))

    if missing_ids == [] do
      boards
    else
      fetched =
        repo.all(from board in BoardRecord, where: board.id in ^missing_ids)
        |> Map.new(&{&1.id, &1})

      Map.merge(boards, fetched)
    end
  end

  defp load_thread_map([], _repo), do: %{}

  defp load_thread_map(posts, repo) do
    thread_map =
      Enum.reduce(posts, %{}, fn post, acc ->
        cond do
          is_nil(post.thread_id) ->
            Map.put(acc, post.id, post)

          thread = ready_thread_assoc(post) ->
            Map.put(acc, thread.id, thread)

          true ->
            acc
        end
      end)

    missing_thread_ids =
      posts
      |> Enum.map(&(&1.thread_id || &1.id))
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(thread_map, &1))

    if missing_thread_ids == [] do
      thread_map
    else
      fetched =
        repo.all(from post in Post, where: post.id in ^missing_thread_ids)
        |> maybe_preload(repo, [:extra_files])
        |> Map.new(&{&1.id, &1})

      Map.merge(thread_map, fetched)
    end
  end

  defp build_config_map(board_map, request_host) do
    board_map
    |> Map.values()
    |> BoardRuntime.config_map(request_host, instance_config: Settings.current_instance_config())
  end

  defp ensure_post_preloads(posts, repo) do
    preloads =
      []
      |> maybe_add_preload(posts, :board)
      |> maybe_add_preload(posts, :extra_files)

    maybe_preload(posts, repo, preloads)
  end

  defp maybe_add_preload(preloads, posts, assoc) do
    if Enum.any?(posts, &(not assoc_loaded?(Map.get(&1, assoc)))) do
      [assoc | preloads]
    else
      preloads
    end
  end

  defp maybe_preload(records, _repo, []), do: records
  defp maybe_preload(records, repo, preloads), do: repo.preload(records, preloads)

  defp ready_thread_assoc(post) do
    case loaded_assoc(post.thread) do
      %Post{} = thread ->
        if assoc_loaded?(thread.extra_files), do: thread, else: nil

      _ ->
        nil
    end
  end

  defp loaded_assoc(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded_assoc(value), do: value

  defp assoc_loaded?(%Ecto.Association.NotLoaded{}), do: false
  defp assoc_loaded?(_value), do: true
end
