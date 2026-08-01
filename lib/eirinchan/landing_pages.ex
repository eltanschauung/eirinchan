defmodule Eirinchan.LandingPages do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts
  alias Eirinchan.Posts.{Post, PostFile, PublicIds}
  alias Eirinchan.Repo
  alias Eirinchan.StaticImageDimensions
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.BoardRuntime
  alias EirinchanWeb.PostView

  @max_sitemap_threads 49_000

  def board_ids(settings, boards) when is_map(settings) and is_list(boards) do
    excluded = board_uri_set(Map.get(settings, "exclude", ""))

    boards
    |> Enum.reject(&MapSet.member?(excluded, &1.uri))
    |> Enum.map(& &1.id)
  end

  def content(settings, board_ids) when is_map(settings) and is_list(board_ids) do
    image_limit = integer_setting(settings, "limit_images", 3, min: 0, max: 100)
    post_limit = integer_setting(settings, "limit_posts", 30, min: 0, max: 100)
    fetch_limit = Enum.max([post_limit, max(image_limit * 25, image_limit)])

    posts =
      if fetch_limit > 0,
        do: Posts.list_recent_posts(limit: fetch_limit, board_ids: board_ids),
        else: []

    noko50_paths = noko50_paths(posts)

    %{
      recent_images:
        posts
        |> Enum.filter(&image_post?/1)
        |> Enum.take(image_limit)
        |> Enum.map(&image_summary(&1, noko50_paths)),
      recent_posts:
        posts
        |> Enum.take(post_limit)
        |> Enum.map(&post_summary(&1, noko50_paths))
    }
  end

  def recent_posts(settings, board_ids) when is_map(settings) and is_list(board_ids) do
    limit = integer_setting(settings, "limit_posts", 30, min: 0, max: 100)

    posts =
      if limit > 0, do: Posts.list_recent_posts(limit: limit, board_ids: board_ids), else: []

    noko50_paths = noko50_paths(posts)
    Enum.map(posts, &post_summary(&1, noko50_paths))
  end

  def public_boards(boards, board_ids) when is_list(boards) and is_list(board_ids) do
    included_ids = MapSet.new(board_ids)
    cutoff = DateTime.utc_now() |> DateTime.add(-24 * 60 * 60, :second)

    posts_per_day =
      if board_ids == [] do
        %{}
      else
        Repo.all(
          from post in Post,
            where: post.board_id in ^board_ids and post.inserted_at > ^cutoff,
            group_by: post.board_id,
            select: {post.board_id, count(post.id)}
        )
        |> Map.new()
      end

    boards
    |> Enum.filter(&MapSet.member?(included_ids, &1.id))
    |> Enum.map(fn board ->
      total_posts = max((board.next_public_post_id || 1) - 1, 0)
      ppd = Map.get(posts_per_day, board.id, 0)

      %{
        uri: board.uri,
        title: board.title,
        link: "/#{board.uri}/",
        ppd: ppd,
        ppd_text: number_with_delimiters(ppd),
        total_posts: total_posts,
        total_posts_text: number_with_delimiters(total_posts)
      }
    end)
    |> Enum.sort_by(&{-&1.total_posts, &1.uri})
  end

  def stats(board_ids) when is_list(board_ids) do
    week_cutoff = DateTime.utc_now() |> DateTime.add(-7 * 24 * 60 * 60, :second)

    total_posts =
      Repo.one(
        from board in BoardRecord,
          where: board.id in ^board_ids,
          select:
            coalesce(
              sum(fragment("GREATEST(COALESCE(?, 1) - 1, 0)", board.next_public_post_id)),
              0
            )
      ) || 0

    posts_week =
      Repo.aggregate(
        from(post in Post,
          where: post.board_id in ^board_ids and post.inserted_at > ^week_cutoff
        ),
        :count,
        :id
      )

    primary_bytes =
      Repo.one(
        from post in Post,
          where: post.board_id in ^board_ids and not is_nil(post.file_size),
          select: sum(post.file_size)
      ) || 0

    extra_bytes =
      Repo.one(
        from file in PostFile,
          join: post in Post,
          on: post.id == file.post_id,
          where: post.board_id in ^board_ids and not is_nil(file.file_size),
          select: sum(file.file_size)
      ) || 0

    %{
      total_posts: number_with_delimiters(total_posts),
      posts_week: number_with_delimiters(posts_week),
      active_content: PostView.file_size_text(%{file_size: primary_bytes + extra_bytes})
    }
  end

  def sitemap_boards(settings, boards) when is_map(settings) and is_list(boards) do
    requested = Map.get(settings, "boards", "*") |> board_uri_set()

    if MapSet.member?(requested, "*") or MapSet.size(requested) == 0 do
      boards
    else
      Enum.filter(boards, &MapSet.member?(requested, &1.uri))
    end
  end

  def sitemap_thread_entries(boards) when is_list(boards) do
    board_ids = Enum.map(boards, & &1.id)
    boards_by_id = Map.new(boards, &{&1.id, &1})

    if board_ids == [] do
      []
    else
      Repo.all(
        from thread in Post,
          left_join: reply in Post,
          on: reply.thread_id == thread.id,
          where: is_nil(thread.thread_id) and thread.board_id in ^board_ids,
          group_by: [
            thread.id,
            thread.board_id,
            thread.public_id,
            thread.slug,
            thread.inserted_at
          ],
          order_by: [desc: max(reply.inserted_at), desc: thread.inserted_at],
          limit: @max_sitemap_threads,
          select: {
            thread.id,
            thread.board_id,
            thread.public_id,
            thread.slug,
            thread.inserted_at,
            max(reply.inserted_at)
          }
      )
      |> Enum.flat_map(fn {internal_id, board_id, public_id, slug, inserted_at, reply_at} ->
        case Map.get(boards_by_id, board_id) do
          nil ->
            []

          board ->
            config = BoardRuntime.board_config(board, nil)
            public_id = public_id || internal_id

            [
              %{
                path: ThreadPaths.thread_path_from_public_id(board.uri, public_id, slug, config),
                lastmod: latest_datetime(inserted_at, reply_at)
              }
            ]
        end
      end)
    end
  end

  def integer_setting(settings, key, default, opts \\ []) do
    min_value = Keyword.get(opts, :min, 0)
    max_value = Keyword.get(opts, :max, 100)

    case Integer.parse(to_string(Map.get(settings, key, default))) do
      {value, ""} -> value |> max(min_value) |> min(max_value)
      _ -> default
    end
  end

  defp image_post?(post) do
    is_binary(post.thumb_path) and media_file_type?(post.file_type)
  end

  defp media_file_type?(file_type) when is_binary(file_type) do
    String.starts_with?(file_type, "image/") or String.starts_with?(file_type, "video/")
  end

  defp media_file_type?(_file_type), do: false

  defp image_summary(post, noko50_paths) do
    {thumb_src, thumbwidth, thumbheight} = recent_thumb(post)

    %{
      link: post_link(post, noko50_paths),
      src: thumb_src,
      thumbwidth: thumbwidth,
      thumbheight: thumbheight,
      alt: post.subject || plain_snippet(post.body, 80)
    }
  end

  defp post_summary(post, noko50_paths) do
    plain_snippet = plain_snippet(post.body, 32)

    %{
      board_name: post.board.title,
      board_subtitle: post.board.subtitle,
      board_uri: post.board.uri,
      link: post_link(post, noko50_paths),
      snippet: emphasized_snippet(plain_snippet, post.body),
      plain_snippet: if(plain_snippet == "", do: "(no comment)", else: plain_snippet),
      inserted_at: post.inserted_at
    }
  end

  defp noko50_paths(posts) do
    thread_ids = posts |> Enum.map(&thread_root_id/1) |> Enum.uniq()

    reply_counts =
      if thread_ids == [] do
        %{}
      else
        Repo.all(
          from post in Post,
            where: post.thread_id in ^thread_ids,
            group_by: post.thread_id,
            select: {post.thread_id, count(post.id)}
        )
        |> Map.new()
      end

    posts
    |> Enum.map(fn post ->
      thread = post.thread || post
      config = BoardRuntime.board_config(post.board, nil)

      {thread.id,
       ThreadPaths.preferred_thread_path(post.board, thread, config,
         reply_count: Map.get(reply_counts, thread.id, 0)
       )}
    end)
    |> Map.new()
  end

  defp post_link(post, noko50_paths) do
    thread = post.thread || post
    Map.fetch!(noko50_paths, thread.id) <> "##{PublicIds.public_id(post)}"
  end

  defp thread_root_id(%{thread_id: thread_id}) when is_integer(thread_id), do: thread_id
  defp thread_root_id(%{id: id}), do: id

  defp emphasized_snippet("", _body), do: "<em>(no comment)</em>"

  defp emphasized_snippet(snippet, body) do
    escaped = Phoenix.HTML.html_escape(snippet) |> Phoenix.HTML.safe_to_string()
    suffix = if String.length(plain_text(body)) > String.length(snippet), do: "&hellip;", else: ""
    "<em>#{escaped}#{suffix}</em>"
  end

  defp plain_snippet(body, length) do
    body
    |> plain_text()
    |> String.slice(0, length)
  end

  defp plain_text(nil), do: ""

  defp plain_text(body) do
    body
    |> String.replace(~r/<br\s*\/?\s*>/i, " ")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp number_with_delimiters(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{1,3}/, "\\0,")
    |> String.trim_trailing(",")
    |> String.reverse()
  end

  defp recent_thumb(%{spoiler: true}), do: {"/static/spoiler_skillet.png", 128, 128}

  defp recent_thumb(post) do
    src = "/#{post.board.uri}/thumb/#{Path.basename(post.thumb_path)}"

    case thumb_dimensions(post) do
      {width, height} ->
        {src, width, height}

      nil ->
        {width, height} = fit_thumb(post.image_width, post.image_height)
        {src, width, height}
    end
  end

  defp fit_thumb(width, height)
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    scale = min(150 / width, 150 / height)

    if scale >= 1,
      do: {width, height},
      else: {max(trunc(width * scale), 1), max(trunc(height * scale), 1)}
  end

  defp fit_thumb(_, _), do: {125, 125}

  defp thumb_dimensions(%{thumb_path: thumb_path}) when is_binary(thumb_path) do
    path =
      thumb_path
      |> String.trim_leading("/")
      |> then(&Path.join(Application.fetch_env!(:eirinchan, :build_output_root), &1))

    case File.read(path) do
      {:ok, binary} -> StaticImageDimensions.from_binary(binary)
      _ -> nil
    end
  end

  defp thumb_dimensions(_), do: nil

  defp board_uri_set(value) do
    value
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end

  defp latest_datetime(left, nil), do: left
  defp latest_datetime(nil, right), do: right

  defp latest_datetime(left, right) do
    case DateTime.compare(left, right) do
      :lt -> right
      _ -> left
    end
  end
end
