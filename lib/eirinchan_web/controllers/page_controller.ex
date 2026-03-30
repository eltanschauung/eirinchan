defmodule EirinchanWeb.PageController do
  use EirinchanWeb, :controller
  import Ecto.Query
  import Phoenix.Template, only: [render_to_string: 4]

  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.CustomPages
  alias Eirinchan.FaqPage
  alias Eirinchan.FormattingPage
  alias Eirinchan.Installation
  alias Eirinchan.NewsBlotter
  alias Eirinchan.Posts
  alias Eirinchan.RulesPage
  alias Eirinchan.ThreadWatcher
  alias Eirinchan.Posts.{Post, PostFile, PublicIds}
  alias Eirinchan.Repo
  alias Eirinchan.Settings
  alias Eirinchan.Themes
  alias EirinchanWeb.ErrorPages
  alias EirinchanWeb.{Announcements, BoardChrome, BoardRuntime}
  alias EirinchanWeb.FragmentCache
  alias EirinchanWeb.HtmlSanitizer
  alias EirinchanWeb.PostView
  alias EirinchanWeb.PublicControllerHelpers
  alias Eirinchan.ThreadPaths

  @recent_theme_cache_bucket_seconds 30

  def home(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      if Themes.page_theme_enabled?("recent") do
        render_recent_theme(conn, "index")
      else
        config = Settings.current_instance_config()
        started_at = System.monotonic_time(:microsecond)
        boards = Boards.list_boards()
        news_entries = NewsBlotter.entries(config, limit: 5)

        conn =
          conn
          |> put_public_document_etag({:home_default, home_board_etag_data(boards), news_entries})
          |> render(
            :home,
            Keyword.merge(
              public_page_assigns(conn, "active-page", "index",
                include_global_message: false,
                boards: boards
              ),
              layout: false,
              news_entries: news_entries
            )
          )

        PublicControllerHelpers.maybe_log_page_performance(
          "home",
          started_at,
          %{
            board_count: length(boards),
            news_entry_count: length(news_entries),
            theme: "default"
          },
          config
        )

        conn
      end
    end
  end

  def news(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      config = Settings.current_instance_config()
      news_entries = NewsBlotter.entries(config, limit: 100)

      conn
      |> put_public_document_etag({:news, news_entries})
      |> render(
        :news,
        Keyword.merge(
          public_page_assigns(conn, "active-page", "news", include_global_message: false),
          layout: false,
          news_entries: news_entries
        )
      )
    end
  end

  def catalog(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      if Themes.page_theme_enabled?("catalog") do
        render(
          conn,
          :catalog,
          Keyword.merge(
            public_page_assigns(conn, "active-catalog", "catalog"),
            layout: false,
            threads: global_catalog_threads()
          )
        )
      else
        ErrorPages.not_found(conn)
      end
    end
  end

  def ukko(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      if Themes.page_theme_enabled?("ukko") do
        if Themes.overboard_path() == "/ukko" do
          render_overboard(conn)
        else
          redirect(conn, to: Themes.overboard_path())
        end
      else
        ErrorPages.not_found(conn)
      end
    end
  end

  def recent(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      if Themes.page_theme_enabled?("recent") do
        render_recent_theme(conn, "recent")
      else
        ErrorPages.not_found(conn)
      end
    end
  end

  def banners(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      render(
        conn,
        :banners,
        Keyword.merge(
          public_page_assigns(conn, "active-page", "banners"),
          layout: false,
          banner_assets: banner_assets()
        )
      )
    end
  end

  def sitemap(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      if Themes.page_theme_enabled?("sitemap") do
        xml =
          [
            "/",
            "/news"
            | themed_global_paths() ++ sitemap_paths()
          ]
          |> Enum.uniq()
          |> render_sitemap()

        conn
        |> put_resp_content_type("application/xml")
        |> send_resp(200, xml)
      else
        ErrorPages.not_found(conn)
      end
    end
  end

  def page(conn, %{"slug" => slug}) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case CustomPages.get_page_by_slug(slug) do
        nil ->
          ErrorPages.not_found(conn)

        page ->
          render_custom_page(conn, page)
      end
    end
  end

  def watcher(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      render(
        conn,
        :watcher,
        Keyword.merge(
          public_page_assigns(conn, "active-page", "watcher"),
          layout: false,
          hide_theme_switcher: true,
          watch_summaries: watcher_summaries(conn)
        )
      )
    end
  end

  def watcher_fragment(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      html(
        conn,
        render_to_string(EirinchanWeb.PageHTML, "watcher_fragment", "html",
          watch_summaries: watcher_summaries(conn)
        )
      )
    end
  end

  def faq(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case CustomPages.get_page_by_slug("faq") do
        %CustomPages.Page{} = page ->
          render_custom_page(conn, %{page | body: FaqPage.normalize_body(page.body)})

        _ ->
          render_custom_page(conn, %{
            slug: "faq",
            title: "FAQ",
            body: FaqPage.default_body(),
            mod_user: nil
          })
      end
    end
  end

  def flags(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case CustomPages.get_page_by_slug("flags") do
        nil ->
          ErrorPages.not_found(conn)

        page ->
          render_custom_page(conn, page)
      end
    end
  end

  def formatting(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      sticker_entries = sticker_entries(current_sticker_config())

      case CustomPages.get_page_by_slug("formatting") do
        %CustomPages.Page{} = page ->
          render_custom_page(conn, %{page | body: FormattingPage.normalize_body(page.body, sticker_entries)})

        _ ->
          render_custom_page(conn, %{
            slug: "formatting",
            title: "Formatting",
            body: FormattingPage.default_body(sticker_entries),
            mod_user: nil
          })
      end
    end
  end

  def rules(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case CustomPages.get_page_by_slug("rules") do
        %CustomPages.Page{} = page ->
          render_custom_page(conn, %{page | body: RulesPage.normalize_body(page.body)})

        _ ->
          render_custom_page(conn, %{
            slug: "rules",
            title: "Rules",
            body: RulesPage.default_body(),
            mod_user: nil
          })
      end
    end
  end

  def legacy_flags(conn, _params), do: redirect(conn, to: ~p"/flags")

  def board_flag_legacy(conn, %{"board" => _uri}), do: redirect(conn, to: ~p"/flags")

  def render_overboard(conn, page \\ 1) do
    settings = Themes.theme_settings("ukko")
    boards = Boards.list_boards()
    case overboard_threads(settings, boards, page, conn) do
      {:ok, overboard_page} ->
        threads = overboard_page.threads
        posts = Enum.flat_map(threads, fn %{summary: summary} -> [summary.thread | summary.replies] end)

        conn
        |> put_view(EirinchanWeb.PageHTML)
        |> render(
          :ukko,
          Keyword.merge(
            public_page_assigns(conn, "active-page", "ukko"),
            layout: false,
            page_title: "#{Themes.overboard_uri()} - #{overboard_title(settings)}",
            body_class: PublicControllerHelpers.moderator_body_class(conn, "active-page"),
            threads: threads,
            overboard_uri: Themes.overboard_uri(),
            overboard_title: overboard_title(settings),
            overboard_subtitle: overboard_subtitle(settings),
            overboard_page_data: %{
              page: overboard_page.page,
              total_pages: overboard_page.total_pages,
              pages: build_overboard_pages(overboard_page.total_pages)
            },
            overboard_next_page:
              if(overboard_page.page < overboard_page.total_pages,
                do: overboard_page_link(overboard_page.page + 1),
                else: nil
              ),
            backlinks_map: Posts.backlinks_map_for_posts(posts),
            thread_watch_state_by_board: overboard_thread_watch_state(conn, threads),
            current_moderator: conn.assigns[:current_moderator],
            secure_manage_token: conn.assigns[:secure_manage_token]
          )
        )

      {:error, :not_found} ->
        ErrorPages.not_found(conn)
    end
  end

  def board_flag(conn, %{"board" => uri}) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case Boards.get_board_by_uri(uri) do
        nil ->
          ErrorPages.not_found(conn)

        _board ->
          redirect(conn, to: ~p"/flags")
      end
    end
  end

  def not_found(conn, _params), do: ErrorPages.not_found(conn)

  defp public_page_assigns(conn, page_kind, active_page, opts \\ []) do
    boards = Keyword.get_lazy(opts, :boards, &Boards.list_boards/0)
    primary_board = Enum.find(boards, &(&1.uri == "bant")) || %{uri: "bant"}
    common_assigns =
      PublicControllerHelpers.public_shell_assigns(conn, active_page,
        extra_stylesheets: PublicControllerHelpers.extra_stylesheets()
      )

    [
      boards: boards,
      primary_board: primary_board,
      board_chrome: BoardChrome.for_board(primary_board),
      global_message_html: maybe_global_message_html(boards, opts),
      custom_pages: CustomPages.list_pages(),
      global_boardlist_groups: PostView.boardlist_groups(boards),
      body_class: public_body_class(page_kind)
    ] ++ common_assigns
  end

  defp public_body_class("active-catalog"),
    do: "8chan vichan is-not-moderator theme-catalog active-catalog"

  defp public_body_class(page_kind), do: "8chan vichan is-not-moderator #{page_kind}"

  defp current_global_message_html(boards) do
    board_ids = Enum.map(boards, & &1.id)
    Announcements.global_message_html(Settings.current_instance_config(), surround_hr: true, board_ids: board_ids)
  end

  defp maybe_global_message_html(boards, opts) do
    if Keyword.get(opts, :include_global_message, true), do: current_global_message_html(boards)
  end

  defp current_sticker_config do
    Settings.current_instance_config()
    |> Eirinchan.WhaleStickers.entries()
  end

  defp sticker_entries(stickers) when is_list(stickers) do
    stickers
    |> Enum.map(fn
      %{"token" => token, "path" => path} -> %{token: token, path: path}
      %{token: token, path: path} -> %{token: token, path: path}
      %{"token" => token, "file" => file} -> %{token: token, path: "/whalestickers/#{file}"}
      %{token: token, file: file} -> %{token: token, path: "/whalestickers/#{file}"}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp sticker_entries(_), do: []

  defp render_custom_page(conn, page, opts \\ []) do
    board = Keyword.get(opts, :board)
    current_stickers = sticker_entries(current_sticker_config())

    page =
      case page.slug do
        "faq" -> %{page | body: FaqPage.normalize_body(page.body)}
        "formatting" -> %{page | body: FormattingPage.normalize_body(page.body, current_stickers)}
        "rules" -> %{page | body: RulesPage.normalize_body(page.body)}
        _ -> page
      end

    extra_stylesheets =
      public_page_assigns(conn, "active-page", "page")
      |> Keyword.fetch!(:extra_stylesheets)
      |> maybe_add_page_stylesheet(page)

    assigns =
      Keyword.merge(
        public_page_assigns(conn, "active-page", "page"),
        layout: false,
        page: page,
        sanitized_body: HtmlSanitizer.sanitize_fragment(page.body || ""),
        flag_board: board,
        flag_assets: flag_assets(),
        flag_storage_key: "flag_",
        extra_stylesheets: extra_stylesheets
      )

    conn = put_public_document_etag(conn, {:custom_page, page_cache_key(page)})

    case page.slug do
      "flags" -> render(conn, :flag, assigns)
      "faq" -> render(conn, :faq, assigns)
      "formatting" -> render(conn, :formatting, assigns)
      "rules" -> render(conn, :rules, assigns)
      _ -> render(conn, :page, assigns)
    end
  end

  defp maybe_add_page_stylesheet(stylesheets, %{slug: slug})
       when slug in ["faq", "formatting", "rules"],
    do: stylesheets ++ ["/faq/recent.css"]

  defp maybe_add_page_stylesheet(stylesheets, _page), do: stylesheets

  defp put_public_document_etag(conn, term) do
    hash =
      term
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)

    Plug.Conn.put_private(conn, :public_document_etag, hash)
  end

  defp home_board_etag_data(boards) do
    Enum.map(boards, &{&1.id, &1.uri, &1.title, &1.next_public_post_id})
  end

  defp page_cache_key(page) do
    {page.slug, page.title, page.body, Map.get(page, :updated_at), Map.get(page, :inserted_at)}
  end

  defp flag_assets do
    compiled_dir = Path.join([:code.priv_dir(:eirinchan), "static", "flags", "compiled"])

    compiled_dir
    |> File.ls!()
    |> Enum.filter(&String.match?(&1, ~r/\.(png|gif|jpe?g)$/i))
    |> Enum.sort()
    |> Enum.map(fn file ->
      %{
        name: Path.rootname(file),
        url: "/flags/compiled/#{URI.encode(file)}"
      }
    end)
  end

  defp render_recent_theme(conn, active_page) do
    settings = Themes.theme_settings("recent")
    started_at = System.monotonic_time(:microsecond)
    boards = Boards.list_boards()
    board_ids = recent_board_ids(settings, boards)
    content = cached_recent_theme_content(settings, board_ids)
    stats = cached_recent_theme_stats(board_ids)

    conn =
      conn
      |> put_public_document_etag({
        :recent_theme,
        active_page,
        recent_theme_content_cache_key(settings, board_ids),
        recent_theme_stats_cache_key(board_ids)
      })
      |> render(
        :recent,
        Keyword.merge(
          recent_theme_assigns(conn, active_page, boards),
          layout: false,
          recent_settings: settings,
          recent_images: content.recent_images,
          recent_posts: content.recent_posts,
          stats: stats
        )
      )

    PublicControllerHelpers.maybe_log_page_performance(
      if(active_page == "index", do: "home", else: "recent"),
      started_at,
      %{
        active_page: active_page,
        board_count: length(boards),
        board_ids_count: length(board_ids),
        recent_image_count: length(content.recent_images),
        recent_post_count: length(content.recent_posts),
        theme: "recent"
      }
    )

    conn
  end

  defp cached_recent_theme_content(settings, board_ids) do
    FragmentCache.fetch_or_store(recent_theme_content_cache_key(settings, board_ids), fn ->
      recent_theme_content(settings, board_ids)
    end)
  end

  defp cached_recent_theme_stats(board_ids) do
    FragmentCache.fetch_or_store(recent_theme_stats_cache_key(board_ids), fn ->
      recent_theme_stats(board_ids)
    end)
  end

  defp recent_theme_assigns(conn, active_page, boards) do
    [
      boards: boards,
      global_boardlist_groups: PostView.boardlist_groups(boards),
      show_footer: true,
      page_title: "Recent Posts",
      body_class: nil
    ] ++ PublicControllerHelpers.public_shell_assigns(conn, active_page,
      extra_stylesheets: ["/recent.css"],
      show_nav_arrows_page: false
    )
  end

  defp recent_theme_content(settings, board_ids) do
    image_limit = recent_integer_setting(settings, "limit_images", 3)
    post_limit = recent_integer_setting(settings, "limit_posts", 30)
    fetch_limit = Enum.max([post_limit, max(image_limit * 25, image_limit)])
    posts = Posts.list_recent_posts(limit: fetch_limit, board_ids: board_ids)
    noko50_paths = recent_noko50_paths(posts)

    %{
      recent_images:
        posts
        |> Enum.filter(&recent_image_post?/1)
        |> Enum.take(image_limit)
        |> Enum.map(&recent_image_summary(&1, noko50_paths)),
      recent_posts:
        posts
        |> Enum.take(post_limit)
        |> Enum.map(&recent_post_summary(&1, noko50_paths))
    }
  end

  defp recent_theme_stats(board_ids) do
    week_cutoff = DateTime.utc_now() |> DateTime.add(-7 * 24 * 60 * 60, :second)

    total_posts =
      Repo.one(
        from board in BoardRecord,
          where: board.id in ^board_ids,
          select: coalesce(sum(fragment("GREATEST(COALESCE(?, 1) - 1, 0)", board.next_public_post_id)), 0)
      ) || 0

    posts_week =
      Repo.aggregate(
        from(post in Post, where: post.board_id in ^board_ids and post.inserted_at > ^week_cutoff),
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

  defp recent_theme_content_cache_key(settings, board_ids) do
    {
      :recent_theme_content,
      :erlang.phash2(settings),
      board_ids,
      div(System.system_time(:second), @recent_theme_cache_bucket_seconds)
    }
  end

  defp recent_theme_stats_cache_key(board_ids) do
    {
      :recent_theme_stats,
      board_ids,
      div(System.system_time(:second), @recent_theme_cache_bucket_seconds)
    }
  end

  defp recent_board_ids(settings, boards) do
    excluded =
      settings
      |> Map.get("exclude", "")
      |> to_string()
      |> String.split(~r/\s+/, trim: true)
      |> MapSet.new()

    boards
    |> Enum.reject(&MapSet.member?(excluded, &1.uri))
    |> Enum.map(& &1.id)
  end

  defp recent_image_post?(post) do
    is_binary(post.thumb_path) and recent_media_file_type?(post.file_type)
  end

  defp recent_media_file_type?(file_type) when is_binary(file_type) do
    String.starts_with?(file_type, "image/") or String.starts_with?(file_type, "video/")
  end

  defp recent_media_file_type?(_file_type), do: false

  defp recent_image_summary(post, noko50_paths) do
    {thumb_src, thumbwidth, thumbheight} = recent_thumb(post)

    %{
      link: recent_post_link(post, noko50_paths),
      src: thumb_src,
      thumbwidth: thumbwidth,
      thumbheight: thumbheight,
      alt: post.subject || post.body || ""
    }
  end

  defp recent_post_summary(post, noko50_paths) do
    %{
      board_name: post.board.title,
      link: recent_post_link(post, noko50_paths),
      snippet: recent_snippet(post.body)
    }
  end

  defp recent_noko50_paths(posts) do
    thread_ids =
      posts
      |> Enum.map(&thread_root_id/1)
      |> Enum.uniq()

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
      config = board_config(post.board)
      {thread.id,
       ThreadPaths.preferred_thread_path(post.board, thread, config,
         reply_count: Map.get(reply_counts, thread.id, 0)
       )}
    end)
    |> Map.new()
  end

  defp recent_post_link(post, noko50_paths) do
    thread = post.thread || post
    Map.fetch!(noko50_paths, thread.id) <> "##{PublicIds.public_id(post)}"
  end

  defp thread_root_id(%{thread_id: thread_id}) when is_integer(thread_id), do: thread_id
  defp thread_root_id(%{id: id}), do: id

  defp recent_snippet(nil), do: "<em>(no comment)</em>"

  defp recent_snippet(body) do
    len = 32

    body
    |> String.replace(~r/<br\/?>/i, "  ")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" ->
        "<em>(no comment)</em>"

      cleaned ->
        strlen = String.length(cleaned)
        snippet = String.slice(cleaned, 0, len)
        escaped = Phoenix.HTML.html_escape(snippet) |> Phoenix.HTML.safe_to_string()
        "<em>" <> escaped <> if(strlen > len, do: "&hellip;", else: "") <> "</em>"
    end
  end

  defp recent_integer_setting(settings, key, default) do
    case Integer.parse(to_string(Map.get(settings, key, default))) do
      {value, _} when value >= 0 -> value
      _ -> default
    end
  end

  defp number_with_delimiters(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{1,3}/, "\\0,")
    |> String.trim_trailing(",")
    |> String.reverse()
  end

  defp fit_recent_thumb(width, height)
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    max_width = 150
    max_height = 150
    scale = min(max_width / width, max_height / height)

    if scale >= 1 do
      {width, height}
    else
      {max(trunc(width * scale), 1), max(trunc(height * scale), 1)}
    end
  end

  defp fit_recent_thumb(_, _), do: {125, 125}

  defp recent_thumb(%{spoiler: true}) do
    {"/static/spoiler_skillet.png", 128, 128}
  end

  defp recent_thumb(post) do
    src = "/#{post.board.uri}/thumb/#{Path.basename(post.thumb_path)}"

    case thumb_dimensions(post) do
      {width, height} -> {src, width, height}
      nil ->
        {width, height} = fit_recent_thumb(post.image_width, post.image_height)
        {src, width, height}
    end
  end

  defp thumb_dimensions(%{thumb_path: thumb_path}) when is_binary(thumb_path) do
    path =
      thumb_path
      |> String.trim_leading("/")
      |> then(&Path.join(Application.fetch_env!(:eirinchan, :build_output_root), &1))

    case File.read(path) do
      {:ok, binary} ->
        case :binary.match(binary, <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>) do
          {0, _} -> png_dimensions(binary)
          :nomatch -> jpeg_dimensions(binary)
        end

      _ ->
        nil
    end
  end

  defp thumb_dimensions(_), do: nil

  defp png_dimensions(<<
         0x89,
         0x50,
         0x4E,
         0x47,
         0x0D,
         0x0A,
         0x1A,
         0x0A,
         _len::32,
         "IHDR",
         width::32,
         height::32,
         _rest::binary
       >>),
       do: {width, height}

  defp png_dimensions(_), do: nil

  defp jpeg_dimensions(<<0xFF, 0xD8, rest::binary>>), do: jpeg_dimensions_scan(rest)
  defp jpeg_dimensions(_), do: nil

  defp jpeg_dimensions_scan(<<0xFF, marker, _len::16, rest::binary>>)
       when marker in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE,
                       0xCF] do
    <<_precision, height::16, width::16, _rest::binary>> = rest
    {width, height}
  end

  defp jpeg_dimensions_scan(<<0xFF, marker, len::16, rest::binary>>)
       when marker not in [0xD8, 0xD9, 0x01] and marker not in 0xD0..0xD7 do
    skip = max(len - 2, 0)

    if byte_size(rest) >= skip do
      <<_segment::binary-size(skip), tail::binary>> = rest
      jpeg_dimensions_scan(tail)
    else
      nil
    end
  end

  defp jpeg_dimensions_scan(<<_byte, rest::binary>>), do: jpeg_dimensions_scan(rest)
  defp jpeg_dimensions_scan(_), do: nil

  defp global_catalog_threads do
    Boards.list_boards()
    |> Enum.flat_map(fn board ->
      config = board_config(board)

      case Posts.list_page_data(board, config: config) do
        {:ok, pages} ->
          Enum.flat_map(pages, fn page ->
            Enum.map(page.threads, &%{board: board, config: config, summary: &1})
          end)

        _ ->
          []
      end
    end)
  end

  defp overboard_threads(settings, boards, page, conn) do
    config_by_board =
      boards
      |> Enum.map(fn board -> {board.id, board_config(board, conn)} end)
      |> Map.new()

    Posts.list_overboard_page(boards, page,
      config_by_board: config_by_board,
      exclude: overboard_excluded_boards(settings),
      thread_limit: overboard_thread_limit(settings)
    )
  end

  defp sitemap_paths do
    board_paths =
      Boards.list_boards()
      |> Enum.flat_map(fn board ->
        thread_paths =
          Posts.list_recent_posts(limit: 100, board_ids: [board.id])
          |> Enum.map(&PublicIds.thread_public_id/1)
          |> Enum.uniq()
          |> Enum.map(&"/#{board.uri}/res/#{&1}.html")

        catalog_paths =
          if Themes.page_theme_enabled?("catalog"),
            do: ["/#{board.uri}/catalog.html"],
            else: []

        ["/#{board.uri}" | catalog_paths ++ thread_paths]
      end)

    page_paths = Enum.map(CustomPages.list_pages(), &"/pages/#{&1.slug}")

    board_paths ++ page_paths
  end

  defp render_sitemap(paths) do
    entries =
      Enum.map_join(paths, "", fn path ->
        "<url><loc>#{html_escape(path)}</loc></url>"
      end)

    ~s(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</urlset>)
  end

  defp themed_global_paths do
    []
    |> maybe_add_path(Themes.page_theme_enabled?("catalog"), "/catalog")
    |> maybe_add_path(Themes.page_theme_enabled?("ukko"), Themes.overboard_path())
    |> maybe_add_path(Themes.page_theme_enabled?("recent"), "/recent")
  end

  defp maybe_add_path(paths, true, path), do: paths ++ [path]
  defp maybe_add_path(paths, false, _path), do: paths

  defp board_config(%BoardRecord{} = board, request_host_or_conn \\ nil) do
    BoardRuntime.board_config(board, request_host_or_conn)
  end

  defp overboard_thread_limit(settings) do
    case Integer.parse(to_string(Map.get(settings, "thread_limit", "15"))) do
      {value, _} when value >= 0 -> value
      _ -> 15
    end
  end

  defp overboard_title(settings) do
    settings
    |> Map.get("title", "Ukko")
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "Ukko"
      title -> title
    end
  end

  defp overboard_subtitle(settings) do
    subtitle =
      settings
      |> Map.get("subtitle", "")
      |> to_string()
      |> String.trim()

    if subtitle == "" do
      ""
    else
      String.replace(subtitle, "%s", Integer.to_string(overboard_thread_limit(settings)))
    end
  end

  defp overboard_excluded_boards(settings) do
    settings
    |> Map.get("exclude", "")
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
  end

  defp overboard_thread_watch_state(conn, threads) do
    threads
    |> Enum.map(& &1.board.uri)
    |> Enum.uniq()
    |> Map.new(fn board_uri ->
      {board_uri, PublicControllerHelpers.thread_watch_state(conn, board_uri)}
    end)
  end

  defp build_overboard_pages(total_pages) do
    for num <- 1..total_pages do
      %{
        num: num,
        link: overboard_page_link(num)
      }
    end
  end

  defp overboard_page_link(1), do: Themes.overboard_path()
  defp overboard_page_link(page), do: "#{Themes.overboard_path()}/#{page}.html"

  defp html_escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp thread_watcher_path(summary, board_configs) do
    config = Map.get(board_configs, summary.board_uri, Settings.current_instance_config())

    ThreadPaths.preferred_thread_path_from_public_id(
      summary.board_uri,
      summary.thread_id,
      summary.slug,
      config,
      post_count: summary.post_count
    )
  end

  defp watcher_summaries(conn) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) ->
        ThreadWatcher.purge_missing_watches(token)

        board_configs =
          Boards.list_boards()
          |> Map.new(fn board -> {board.uri, board_config(board)} end)

        ThreadWatcher.list_watch_summaries(token)
        |> Enum.map(fn summary ->
          thread_path = thread_watcher_path(summary, board_configs)

          summary
          |> Map.put(:thread_path, thread_path)
          |> Map.put(
            :you_unread_path,
            if(is_integer(summary.you_unread_post_id),
              do: thread_path <> "#" <> Integer.to_string(summary.you_unread_post_id),
              else: thread_path
            )
          )
        end)

      _ ->
        []
    end
  end

  defp banner_assets do
    Path.join(:code.priv_dir(:eirinchan), "static/static/banners")
    |> File.ls!()
    |> Enum.sort()
    |> Enum.map(fn filename ->
      %{
        name: Path.rootname(filename),
        url: "/static/banners/#{filename}"
      }
    end)
  end

end
