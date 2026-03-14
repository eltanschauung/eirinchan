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
    public_id = PublicIds.public_id(thread)
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

  @spec legacy_thread_filename(Post.t(), map()) :: String.t()
  def legacy_thread_filename(%Post{} = thread, config) do
    String.replace(config.file_page, "%d", Integer.to_string(PublicIds.public_id(thread)))
  end

  @spec thread_path(BoardRecord.t(), Post.t(), map(), keyword()) :: String.t()
  def thread_path(%BoardRecord{uri: board_uri}, %Post{} = thread, config, opts \\ []) do
    "/#{board_uri}/#{config.dir.res}#{thread_filename(thread, config, opts)}"
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
