defmodule EirinchanWeb.PageController do
  use EirinchanWeb, :controller
  import Ecto.Query

  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.CustomPages
  alias Eirinchan.Installation
  alias Eirinchan.News
  alias Eirinchan.Posts
  alias Eirinchan.Posts.{Post, PostFile}
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias Eirinchan.Themes
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PostView
  alias EirinchanWeb.PublicShell

  def home(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      if Themes.page_theme_enabled?("recent") do
        render_recent_theme(conn, "index")
      else
        render(
          conn,
          :home,
          Keyword.merge(
            public_page_assigns(conn, "active-page", "index"),
            layout: false,
            news_entries: News.list_entries(limit: 5)
          )
        )
      end
    end
  end

  def news(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      render(
        conn,
        :news,
        Keyword.merge(
          public_page_assigns(conn, "active-page", "news"),
          layout: false,
          news_entries: News.list_entries()
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
        send_resp(conn, :not_found, "Page not found")
      end
    end
  end

  def ukko(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      if Themes.page_theme_enabled?("ukko") do
        render(
          conn,
          :ukko,
          Keyword.merge(
            public_page_assigns(conn, "active-page", "ukko"),
            layout: false,
            threads: ukko_threads()
          )
        )
      else
        send_resp(conn, :not_found, "Page not found")
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
        send_resp(conn, :not_found, "Page not found")
      end
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
        send_resp(conn, :not_found, "Page not found")
      end
    end
  end

  def page(conn, %{"slug" => slug}) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case CustomPages.get_page_by_slug(slug) do
        nil ->
          send_resp(conn, :not_found, "Page not found")

        page ->
          render_custom_page(conn, page)
      end
    end
  end

  def faq(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case CustomPages.get_page_by_slug("faq") do
        %CustomPages.Page{body: body} when is_binary(body) and body != "" ->
          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, body)

        _ ->
          render_custom_page(conn, %{
            slug: "faq",
            title: "FAQ",
            body: "",
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
          send_resp(conn, :not_found, "Page not found")

        page ->
          render_custom_page(conn, page)
      end
    end
  end

  def formatting(conn, _params) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case CustomPages.get_page_by_slug("formatting") do
        %CustomPages.Page{body: body} when is_binary(body) and body != "" ->
          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, body)

        _ ->
          render(
            conn,
            :formatting,
            Keyword.merge(
              public_page_assigns(conn, "active-page", "page"),
              layout: false,
              page: %{slug: "formatting", title: "Formatting", body: "", mod_user: nil},
              sticker_entries: sticker_entries(current_sticker_config())
            )
          )
      end
    end
  end

  def legacy_flags(conn, _params), do: redirect(conn, to: ~p"/flags")

  def board_flag_legacy(conn, %{"board" => _uri}), do: redirect(conn, to: ~p"/flags")

  def board_flag(conn, %{"board" => uri}) do
    if Installation.setup_required?() do
      redirect(conn, to: ~p"/setup")
    else
      case Boards.get_board_by_uri(uri) do
        nil ->
          send_resp(conn, :not_found, "Page not found")

        _board ->
          redirect(conn, to: ~p"/flags")
      end
    end
  end

  defp public_page_assigns(conn, page_kind, active_page) do
    boards = Boards.list_boards()
    primary_board = Enum.find(boards, &(&1.uri == "bant")) || %{uri: "bant"}
    chrome = BoardChrome.for_board(primary_board)

    [
      boards: boards,
      primary_board: primary_board,
      board_chrome: chrome,
      global_message: current_global_message(),
      custom_pages: CustomPages.list_pages(),
      global_boardlist_html: PostView.boardlist_html(PostView.boardlist_groups(boards)),
      public_shell: true,
      viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
      base_stylesheet: "/stylesheets/style.css",
      body_class: public_body_class(page_kind),
      body_data_stylesheet: public_data_stylesheet(conn),
      head_html:
        PublicShell.head_html(active_page,
          resource_version: conn.assigns[:asset_version],
          theme_label: conn.assigns[:theme_label],
          theme_options: conn.assigns[:theme_options]
        ),
      javascript_urls: PublicShell.javascript_urls(active_page),
      body_end_html: PublicShell.body_end_html(),
      primary_stylesheet: public_primary_stylesheet(conn),
      primary_stylesheet_id: "stylesheet",
      extra_stylesheets: public_extra_stylesheets(primary_board),
      hide_theme_switcher: true,
      skip_app_stylesheet: true
    ]
  end

  defp public_body_class("active-catalog"),
    do: "8chan vichan is-not-moderator theme-catalog active-catalog"

  defp public_body_class(page_kind), do: "8chan vichan is-not-moderator #{page_kind}"

  defp public_data_stylesheet(conn) do
    public_primary_stylesheet(conn)
    |> Path.basename()
  end

  defp public_primary_stylesheet(conn),
    do: conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"

  defp public_extra_stylesheets(_board),
    do: ["/stylesheets/eirinchan-public.css", "/stylesheets/eirinchan-bant.css"]

  defp current_global_message do
    case Settings.current_instance_config() |> Map.get(:global_message) do
      value when is_binary(value) -> value
      _ -> ""
    end
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

    extra_stylesheets =
      public_page_assigns(conn, "active-page", "page")
      |> Keyword.fetch!(:extra_stylesheets)
      |> maybe_add_page_stylesheet(page)

    assigns =
      Keyword.merge(
        public_page_assigns(conn, "active-page", "page"),
        layout: false,
        page: page,
        flag_board: board,
        flag_assets: flag_assets(),
        flag_storage_key: "flag_" <> if(board, do: board.uri, else: "bant"),
        extra_stylesheets: extra_stylesheets
      )

    case page.slug do
      "flags" -> render(conn, :flag, assigns)
      "faq" -> render(conn, :faq, assigns)
      _ -> render(conn, :page, assigns)
    end
  end

  defp maybe_add_page_stylesheet(stylesheets, %{slug: "faq"}),
    do: stylesheets ++ ["/faq/recent.css"]

  defp maybe_add_page_stylesheet(stylesheets, _page), do: stylesheets

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

    render(
      conn,
      :recent,
      Keyword.merge(
        recent_theme_assigns(conn, active_page, settings),
        layout: false,
        recent_settings: settings,
        recent_images: recent_theme_images(settings),
        recent_posts: recent_theme_posts(settings),
        stats: recent_theme_stats(settings)
      )
    )
  end

  defp recent_theme_assigns(conn, active_page, _settings) do
    boards = Boards.list_boards()

    [
      boards: boards,
      global_boardlist_html: PostView.boardlist_html(PostView.boardlist_groups(boards)),
      footer_html: EirinchanWeb.BoardChrome.footer_html(),
      public_shell: true,
      viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
      base_stylesheet: "/stylesheets/style.css",
      body_class: nil,
      body_data_stylesheet: public_data_stylesheet(conn),
      head_html:
        PublicShell.head_html(active_page,
          resource_version: conn.assigns[:asset_version],
          theme_label: conn.assigns[:theme_label],
          theme_options: conn.assigns[:theme_options]
        ),
      javascript_urls: PublicShell.javascript_urls(active_page),
      body_end_html: PublicShell.body_end_html(),
      primary_stylesheet: public_primary_stylesheet(conn),
      primary_stylesheet_id: "stylesheet",
      extra_stylesheets: ["/recent.css"],
      hide_theme_switcher: true,
      skip_app_stylesheet: true
    ]
  end

  defp recent_theme_images(settings) do
    limit = recent_integer_setting(settings, "limit_images", 3)
    board_ids = recent_board_ids(settings)

    Posts.list_recent_posts(limit: max(limit * 25, limit), board_ids: board_ids)
    |> Enum.filter(&recent_image_post?/1)
    |> Enum.take(limit)
    |> Enum.map(&recent_image_summary/1)
  end

  defp recent_theme_posts(settings) do
    limit = recent_integer_setting(settings, "limit_posts", 30)
    board_ids = recent_board_ids(settings)

    Posts.list_recent_posts(limit: limit, board_ids: board_ids)
    |> Enum.map(&recent_post_summary/1)
  end

  defp recent_theme_stats(settings) do
    board_ids = recent_board_ids(settings)

    total_posts =
      Repo.aggregate(from(post in Post, where: post.board_id in ^board_ids), :count, :id)

    unique_posters =
      Repo.one(
        from post in Post,
          where: post.board_id in ^board_ids and not is_nil(post.ip_subnet),
          select: count(post.ip_subnet, :distinct)
      ) || 0

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
      unique_posters: number_with_delimiters(unique_posters),
      active_content: PostView.file_size_text(%{file_size: primary_bytes + extra_bytes})
    }
  end

  defp recent_board_ids(settings) do
    excluded =
      settings
      |> Map.get("exclude", "")
      |> to_string()
      |> String.split(~r/\s+/, trim: true)
      |> MapSet.new()

    Boards.list_boards()
    |> Enum.reject(&MapSet.member?(excluded, &1.uri))
    |> Enum.map(& &1.id)
  end

  defp recent_image_post?(post) do
    is_binary(post.thumb_path) and String.starts_with?(post.file_type || "", "image/")
  end

  defp recent_image_summary(post) do
    {thumbwidth, thumbheight} = fit_recent_thumb(post.image_width, post.image_height)

    %{
      link: "/#{post.board.uri}/res/#{post.thread_id || post.id}.html##{post.id}",
      src: "/#{post.board.uri}/thumb/#{Path.basename(post.thumb_path)}",
      thumbwidth: thumbwidth,
      thumbheight: thumbheight,
      alt: post.subject || post.body || ""
    }
  end

  defp recent_post_summary(post) do
    %{
      board_name: post.board.title,
      link: "/#{post.board.uri}/res/#{post.thread_id || post.id}.html##{post.id}",
      snippet: recent_snippet(post.body)
    }
  end

  defp recent_snippet(nil), do: "<em>(no comment)</em>"

  defp recent_snippet(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.split(" ", trim: true)
    |> Enum.take(30)
    |> Enum.join(" ")
    |> case do
      "" -> "<em>(no comment)</em>"
      snippet -> Phoenix.HTML.html_escape(snippet) |> Phoenix.HTML.safe_to_string()
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

  defp global_catalog_threads do
    Boards.list_boards()
    |> Enum.flat_map(fn board ->
      config = board_config(board)

      case Posts.list_page_data(board, config: config) do
        {:ok, pages} ->
          Enum.flat_map(pages, fn page ->
            Enum.map(page.threads, &%{board: board, summary: &1})
          end)

        _ ->
          []
      end
    end)
  end

  defp ukko_threads do
    Boards.list_boards()
    |> Enum.flat_map(fn board ->
      config = board_config(board)

      case Posts.list_threads_page(board, 1, config: config) do
        {:ok, page} -> Enum.map(page.threads, &%{board: board, summary: &1})
        _ -> []
      end
    end)
  end

  defp sitemap_paths do
    board_paths =
      Boards.list_boards()
      |> Enum.flat_map(fn board ->
        thread_paths =
          Posts.list_recent_posts(limit: 100, board_ids: [board.id])
          |> Enum.map(&(&1.thread_id || &1.id))
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
    |> maybe_add_path(Themes.page_theme_enabled?("ukko"), "/ukko")
    |> maybe_add_path(Themes.page_theme_enabled?("recent"), "/recent")
  end

  defp maybe_add_path(paths, true, path), do: paths ++ [path]
  defp maybe_add_path(paths, false, _path), do: paths

  defp board_config(%BoardRecord{} = board) do
    Config.compose(nil, Settings.current_instance_config(), board.config_overrides || %{},
      board: BoardRecord.to_board(board)
    )
  end

  defp html_escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
