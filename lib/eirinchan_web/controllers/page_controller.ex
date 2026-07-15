defmodule EirinchanWeb.PageController do
  use EirinchanWeb, :controller
  import Phoenix.Template, only: [render_to_string: 4]

  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.CustomPages
  alias Eirinchan.PublicPages
  alias Eirinchan.LandingPages
  alias Eirinchan.NewsBlotter
  alias Eirinchan.Posts
  alias Eirinchan.Settings
  alias Eirinchan.SiteContact
  alias Eirinchan.StaticImageDimensions
  alias Eirinchan.Themes
  alias EirinchanWeb.ErrorPages
  alias EirinchanWeb.BoardRuntime
  alias EirinchanWeb.FragmentCache
  alias EirinchanWeb.HtmlSanitizer
  alias EirinchanWeb.PostView
  alias EirinchanWeb.PublicControllerHelpers
  alias Eirinchan.ThreadPaths

  @recent_theme_cache_bucket_seconds 30

  def home(conn, _params) do
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
            PublicControllerHelpers.public_page_assigns(conn, "active-page", "index",
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

  def news(conn, _params) do
    config = Settings.current_instance_config()
    news_entries = NewsBlotter.entries(config, limit: 100)

    conn
    |> put_public_document_etag({:news, news_entries})
    |> render(
      :news,
      Keyword.merge(
        PublicControllerHelpers.public_page_assigns(conn, "active-page", "news",
          include_global_message: false
        ),
        layout: false,
        news_entries: news_entries
      )
    )
  end

  def catalog(conn, _params) do
    render(
      conn,
      :catalog,
      Keyword.merge(
        PublicControllerHelpers.public_page_assigns(conn, "active-catalog", "catalog"),
        layout: false,
        threads: global_catalog_threads()
      )
    )
  end

  def ukko(conn, _params) do
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

  def recent(conn, _params) do
    if Themes.page_theme_enabled?("recent") do
      render_recent_theme(conn, "recent")
    else
      ErrorPages.not_found(conn)
    end
  end

  def rss(conn, _params) do
    if Themes.page_theme_enabled?("rss") do
      settings = Themes.theme_settings("rss")
      boards = Boards.list_boards()
      board_ids = LandingPages.board_ids(settings, boards)
      posts = LandingPages.recent_posts(settings, board_ids)
      xml = render_rss(settings, posts)

      conn
      |> put_public_document_etag({:rss, settings, Enum.map(posts, &{&1.link, &1.inserted_at})})
      |> put_resp_content_type("application/rss+xml")
      |> send_resp(200, xml)
    else
      ErrorPages.not_found(conn)
    end
  end

  def sitemap(conn, _params) do
    if Themes.page_theme_enabled?("sitemap") do
      settings = Themes.theme_settings("sitemap")
      boards = LandingPages.sitemap_boards(settings, Boards.list_boards())
      changefreq = Map.get(settings, "changefreq", "hourly")

      entries =
        global_sitemap_entries() ++
          board_sitemap_entries(boards) ++ LandingPages.sitemap_thread_entries(boards)

      xml = render_sitemap(entries, changefreq)

      conn
      |> put_public_document_etag({:sitemap, settings, entries})
      |> put_resp_content_type("application/xml")
      |> send_resp(200, xml)
    else
      ErrorPages.not_found(conn)
    end
  end

  def page(conn, %{"slug" => slug}) do
    case CustomPages.get_page_by_slug(slug) do
      nil ->
        ErrorPages.not_found(conn)

      page ->
        render_custom_page(conn, page)
    end
  end

  def watcher(conn, _params) do
    watcher_snapshot = PublicControllerHelpers.watcher_snapshot(conn, summaries: true)

    render(
      conn,
      :watcher,
      Keyword.merge(
        PublicControllerHelpers.public_page_assigns(conn, "active-page", "watcher",
          watcher_snapshot: watcher_snapshot
        ),
        layout: false,
        hide_theme_switcher: true,
        watch_summaries: watcher_summaries(watcher_snapshot)
      )
    )
  end

  def watcher_fragment(conn, _params) do
    watcher_snapshot = PublicControllerHelpers.watcher_snapshot(conn, summaries: true)
    watcher_metrics = PublicControllerHelpers.watcher_metrics(watcher_snapshot)

    conn =
      conn
      |> put_resp_header("cache-control", "no-store, max-age=0")
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("x-watcher-count", Integer.to_string(watcher_metrics.watcher_count))
      |> put_resp_header(
        "x-watcher-unread-count",
        Integer.to_string(watcher_metrics.watcher_unread_count)
      )
      |> put_resp_header(
        "x-watcher-you-count",
        Integer.to_string(watcher_metrics.watcher_you_count)
      )

    html(
      conn,
      render_to_string(EirinchanWeb.PageHTML, "watcher_fragment", "html",
        watch_summaries: watcher_summaries(watcher_snapshot)
      )
    )
  end

  def faq(conn, _params), do: render_custom_page(conn, PublicPages.fetch_named_page("faq"))

  def formatting(conn, _params) do
    render_custom_page(
      conn,
      PublicPages.fetch_named_page("formatting",
        stickers: sticker_entries(current_sticker_config())
      )
    )
  end

  def rules(conn, _params) do
    render_custom_page(
      conn,
      PublicPages.fetch_named_page("rules", contact_email: SiteContact.email())
    )
  end

  def feedback(conn, _params),
    do: render_custom_page(conn, PublicPages.fetch_named_page("feedback"))

  def render_overboard(conn, page \\ 1) do
    settings = Themes.theme_settings("ukko")
    boards = Boards.list_boards()

    case overboard_threads(settings, boards, page, conn) do
      {:ok, overboard_page} ->
        threads = overboard_page.threads
        watcher_snapshot = PublicControllerHelpers.watcher_snapshot(conn)

        posts =
          Enum.flat_map(threads, fn %{summary: summary} -> [summary.thread | summary.replies] end)

        conn
        |> put_view(EirinchanWeb.PageHTML)
        |> render(
          :ukko,
          Keyword.merge(
            PublicControllerHelpers.public_page_assigns(conn, "active-page", "ukko",
              watcher_snapshot: watcher_snapshot
            ),
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
            thread_watch_state_by_board: overboard_thread_watch_state(watcher_snapshot, threads),
            current_moderator: conn.assigns[:current_moderator],
            secure_manage_token: conn.assigns[:secure_manage_token]
          )
        )

      {:error, :not_found} ->
        ErrorPages.not_found(conn)
    end
  end

  def not_found(conn, _params), do: ErrorPages.not_found(conn)

  defp current_sticker_config do
    Settings.current_instance_config()
    |> Eirinchan.Stickers.entries()
  end

  defp sticker_entries(stickers) when is_list(stickers) do
    stickers
    |> Enum.map(fn
      %{"token" => token, "path" => path} -> %{token: token, path: path}
      %{token: token, path: path} -> %{token: token, path: path}
      %{"token" => token, "file" => file} -> %{token: token, path: "/stickers/#{file}"}
      %{token: token, file: file} -> %{token: token, path: "/stickers/#{file}"}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&with_static_image_dimensions/1)
  end

  defp sticker_entries(_), do: []

  defp with_static_image_dimensions(%{path: path} = entry) do
    case StaticImageDimensions.for_static_path(path) do
      {width, height} -> Map.merge(entry, %{width: width, height: height})
      nil -> Map.merge(entry, %{width: nil, height: nil})
    end
  end

  defp render_custom_page(conn, page, _opts \\ []) do
    current_stickers = sticker_entries(current_sticker_config())
    show_global_message = PublicPages.show_global_message?(page.slug)

    contact_email = SiteContact.email()

    page =
      PublicPages.normalize_page(page,
        stickers: current_stickers,
        contact_email: contact_email
      )

    sanitized_body = HtmlSanitizer.sanitize_fragment(page.body || "")

    public_page_assigns =
      PublicControllerHelpers.public_page_assigns(conn, "active-page", page.slug,
        include_global_message: show_global_message
      )

    extra_stylesheets =
      public_page_assigns
      |> Keyword.fetch!(:extra_stylesheets)
      |> maybe_add_page_stylesheet(page)

    assigns =
      Keyword.merge(
        public_page_assigns,
        layout: false,
        page: page,
        global_message_html:
          if(show_global_message,
            do: Keyword.get(public_page_assigns, :global_message_html),
            else: nil
          ),
        sanitized_body: sanitized_body,
        extra_stylesheets: extra_stylesheets,
        page_subtitle: PublicPages.page_subtitle(page.slug),
        show_global_message: show_global_message,
        params: %{},
        errors: nil,
        contact_email: contact_email
      )

    conn = put_public_document_etag(conn, {:custom_page, page_cache_key(page)})

    case page.slug do
      "feedback" -> render(conn, :feedback, assigns)
      "faq" -> render(conn, :faq, assigns)
      "formatting" -> render(conn, :formatting, assigns)
      "rules" -> render(conn, :rules, assigns)
      _ -> render(conn, :page, assigns)
    end
  end

  defp maybe_add_page_stylesheet(stylesheets, %{slug: slug})
       when slug in ["faq", "formatting", "rules"],
       do: stylesheets ++ ["/recent.css"]

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

  defp render_recent_theme(conn, active_page) do
    settings = Themes.theme_settings("recent")
    started_at = System.monotonic_time(:microsecond)
    boards = Boards.list_boards()
    board_ids = LandingPages.board_ids(settings, boards)
    content = cached_recent_theme_content(settings, board_ids)
    stats = cached_recent_theme_stats(board_ids)
    sanitized_home_body = HtmlSanitizer.sanitize_fragment(Map.get(settings, "body", ""))

    conn =
      conn
      |> put_public_document_etag({
        :recent_theme,
        active_page,
        recent_theme_content_cache_key(settings, board_ids),
        recent_theme_stats_cache_key(board_ids),
        settings
      })
      |> render(
        :recent,
        Keyword.merge(
          recent_theme_assigns(conn, active_page, boards, settings),
          layout: false,
          recent_settings: settings,
          recent_images: content.recent_images,
          recent_posts: content.recent_posts,
          stats: stats,
          sanitized_home_body: sanitized_home_body
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
      LandingPages.content(settings, board_ids)
    end)
  end

  defp cached_recent_theme_stats(board_ids) do
    FragmentCache.fetch_or_store(recent_theme_stats_cache_key(board_ids), fn ->
      LandingPages.stats(board_ids)
    end)
  end

  defp recent_theme_assigns(conn, active_page, boards, settings) do
    [
      boards: boards,
      global_boardlist_groups:
        PostView.boardlist_groups(boards, mobile_client?: conn.assigns[:mobile_client?] || false),
      show_footer: true,
      page_title: Map.get(settings, "title", "Recent Posts"),
      body_class: nil
    ] ++
      PublicControllerHelpers.public_shell_assigns(conn, active_page,
        extra_stylesheets: ["/recent.css"],
        show_nav_arrows_page: false
      )
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

  defp global_sitemap_entries do
    theme_entries =
      Themes.page_themes()
      |> Enum.filter(& &1.enabled)
      |> Enum.map(&Themes.public_path(&1.name))
      |> Enum.reject(&is_nil/1)

    custom_page_entries =
      CustomPages.list_pages()
      |> Enum.reject(&(&1.slug == "home"))
      |> Enum.map(&public_custom_page_path/1)

    (["/", "/news", "/catalog"] ++ theme_entries ++ custom_page_entries)
    |> Enum.uniq()
    |> Enum.map(&%{path: &1, lastmod: nil})
  end

  defp board_sitemap_entries(boards) do
    Enum.flat_map(boards, fn board ->
      [
        %{path: "/#{board.uri}", lastmod: nil},
        %{path: "/#{board.uri}/catalog.html", lastmod: nil}
      ]
    end)
  end

  defp public_custom_page_path(%{slug: slug})
       when slug in ["faq", "feedback", "formatting", "rules"],
       do: "/#{slug}"

  defp public_custom_page_path(%{slug: slug}), do: "/pages/#{slug}"

  defp render_sitemap(entries, changefreq) do
    origin = public_origin()

    urls =
      Enum.map_join(entries, "", fn entry ->
        lastmod =
          case entry.lastmod do
            %DateTime{} = value -> "<lastmod>#{DateTime.to_iso8601(value)}</lastmod>"
            _ -> ""
          end

        frequency =
          if entry.lastmod, do: "<changefreq>#{xml_escape(changefreq)}</changefreq>", else: ""

        "<url><loc>#{xml_escape(origin <> entry.path)}</loc>#{lastmod}#{frequency}</url>"
      end)

    ~s(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{urls}</urlset>)
  end

  defp render_rss(settings, posts) do
    origin = public_origin()
    title = xml_escape(Map.get(settings, "title", "Recent Posts RSS"))
    description = xml_escape(Map.get(settings, "subtitle", "Recent posts"))

    items =
      Enum.map_join(posts, "", fn post ->
        link = origin <> post.link
        pub_date = Calendar.strftime(post.inserted_at, "%a, %d %b %Y %H:%M:%S GMT")

        "<item>" <>
          "<title>#{xml_escape(post.board_name)}</title>" <>
          "<description>#{xml_escape(post.plain_snippet)}</description>" <>
          "<link>#{xml_escape(link)}</link>" <>
          "<guid isPermaLink=\"true\">#{xml_escape(link)}</guid>" <>
          "<pubDate>#{pub_date}</pubDate>" <>
          "</item>"
      end)

    ~s(<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>#{title}</title><description>#{description}</description><link>#{xml_escape(origin <> "/recent")}</link><generator>Eirinchan</generator>#{items}</channel></rss>)
  end

  defp public_origin do
    EirinchanWeb.Endpoint.url()
    |> String.trim_trailing("/")
  end

  defp board_config(%BoardRecord{} = board, request_host_or_conn \\ nil) do
    BoardRuntime.board_config(board, request_host_or_conn)
  end

  defp overboard_thread_limit(settings) do
    LandingPages.integer_setting(settings, "thread_limit", 15, min: 1, max: 100)
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

  defp overboard_thread_watch_state(watcher_snapshot, threads) do
    state_by_board = PublicControllerHelpers.watcher_state_by_board(watcher_snapshot)

    threads
    |> Enum.map(& &1.board.uri)
    |> Enum.uniq()
    |> Map.new(fn board_uri ->
      {board_uri, Map.get(state_by_board, board_uri, %{})}
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

  defp xml_escape(value) do
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

  defp watcher_summaries(%{summaries: summaries}) when is_list(summaries) do
    board_configs =
      Boards.list_boards()
      |> Map.new(fn board -> {board.uri, board_config(board)} end)

    Enum.map(summaries, fn summary ->
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
  end
  defp watcher_summaries(_watcher_snapshot), do: []
end
