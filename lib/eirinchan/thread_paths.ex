defmodule Eirinchan.ThreadPaths do
  @moduledoc """
  Helpers for vichan-style thread filenames and board-relative paths.
  """

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PublicIds

  @spec parse_thread_id(String.t() | integer()) :: {:ok, integer()} | :error
  def parse_thread_id(value) when is_integer(value), do: {:ok, value}

  def parse_thread_id(value) when is_binary(value) do
    case Regex.run(~r/^(\d+)/, String.trim(value)) do
      [_, id] -> {:ok, String.to_integer(id)}
      _ -> :error
    end
  end

  @spec thread_filename(Post.t(), map(), keyword()) :: String.t()
  def thread_filename(%Post{slug: slug} = thread, config, opts \\ []) do
    thread_filename_from_public_id(PublicIds.public_id(thread), slug, config, opts)
  end

  @spec legacy_thread_filename(Post.t(), map()) :: String.t()
  def legacy_thread_filename(%Post{} = thread, config) do
    String.replace(config.file_page, "%d", Integer.to_string(PublicIds.public_id(thread)))
  end

  @spec thread_path(BoardRecord.t(), Post.t(), map(), keyword()) :: String.t()
  def thread_path(%BoardRecord{uri: board_uri}, %Post{} = thread, config, opts \\ []) do
    thread_path_from_public_id(board_uri, PublicIds.public_id(thread), thread.slug, config, opts)
  end

  @spec thread_filename_from_public_id(integer(), String.t() | nil, map(), keyword()) :: String.t()
  def thread_filename_from_public_id(public_id, slug, config, opts \\ []) when is_integer(public_id) do
    noko50? = Keyword.get(opts, :noko50, false)

    template =
      if is_binary(slug) and slug != "" do
        if noko50?, do: config.file_page50_slug, else: config.file_page_slug
      else
        if noko50?, do: config.file_page50, else: config.file_page
      end

    template
    |> String.replace("%d", Integer.to_string(public_id))
    |> String.replace("%s", slug || "")
  end

  @spec thread_path_from_public_id(String.t(), integer(), String.t() | nil, map(), keyword()) ::
          String.t()
  def thread_path_from_public_id(board_uri, public_id, slug, config, opts \\ [])
      when is_binary(board_uri) and is_integer(public_id) do
    "/#{board_uri}/#{config.dir.res}#{thread_filename_from_public_id(public_id, slug, config, opts)}"
  end

  @spec preferred_thread_path(BoardRecord.t(), Post.t(), map(), keyword()) :: String.t()
  def preferred_thread_path(%BoardRecord{} = board, %Post{} = thread, config, opts \\ []) do
    thread_path(board, thread, config, noko50: noko50?(config, opts))
  end

  @spec preferred_thread_path_from_public_id(
          String.t(),
          integer(),
          String.t() | nil,
          map(),
          keyword()
        ) ::
          String.t()
  def preferred_thread_path_from_public_id(board_uri, public_id, slug, config, opts \\ [])
      when is_binary(board_uri) and is_integer(public_id) do
    thread_path_from_public_id(board_uri, public_id, slug, config, noko50: noko50?(config, opts))
  end

  @spec noko50?(map(), keyword()) :: boolean()
  def noko50?(config, opts \\ []) do
    cond do
      is_boolean(opts[:has_noko50]) ->
        opts[:has_noko50]

      is_integer(opts[:reply_count]) ->
        opts[:reply_count] >= Map.get(config, :noko50_min, 0)

      is_integer(opts[:post_count]) ->
        max(opts[:post_count] - 1, 0) >= Map.get(config, :noko50_min, 0)

      true ->
        false
    end
  end

  @spec board_page_path(BoardRecord.t(), pos_integer(), map()) :: String.t()
  def board_page_path(%BoardRecord{uri: board_uri}, page_num, _config) when page_num <= 1 do
    "/#{board_uri}"
  end

  def board_page_path(%BoardRecord{uri: board_uri}, page_num, config) do
    filename = String.replace(config.file_page, "%d", Integer.to_string(page_num))
    "/#{board_uri}/#{filename}"
  end

  @spec catalog_page_path(BoardRecord.t(), pos_integer(), map()) :: String.t()
  def catalog_page_path(%BoardRecord{uri: board_uri}, page_num, _config) when page_num <= 1 do
    "/#{board_uri}/catalog.html"
  end

  def catalog_page_path(%BoardRecord{uri: board_uri}, page_num, config) do
    filename = String.replace(config.file_catalog_page, "%d", Integer.to_string(page_num))
    "/#{board_uri}/#{filename}"
  end
end
