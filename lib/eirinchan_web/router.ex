defmodule EirinchanWeb.Router do
  use EirinchanWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_cookies
    plug EirinchanWeb.Plugs.FetchCurrentModerator
    plug EirinchanWeb.Plugs.FetchTheme
    plug EirinchanWeb.Plugs.FetchSiteAssets
    plug EirinchanWeb.Plugs.AutoMaintenance
    plug :fetch_live_flash
    plug :put_root_layout, html: {EirinchanWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug EirinchanWeb.Plugs.FetchCurrentModerator
  end

  pipeline :manage_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug EirinchanWeb.Plugs.FetchCurrentModerator
    plug EirinchanWeb.Plugs.RequireModerator
  end

  pipeline :manage_janitor do
    plug :accepts, ["json"]
    plug :fetch_session
    plug EirinchanWeb.Plugs.FetchCurrentModerator
    plug EirinchanWeb.Plugs.RequireModerator
    plug EirinchanWeb.Plugs.RequireModeratorRole, role: "janitor"
  end

  pipeline :manage_mod do
    plug :accepts, ["json"]
    plug :fetch_session
    plug EirinchanWeb.Plugs.FetchCurrentModerator
    plug EirinchanWeb.Plugs.RequireModerator
    plug EirinchanWeb.Plugs.RequireModeratorRole, role: "mod"
    plug EirinchanWeb.Plugs.RequireSecureManageToken
  end

  pipeline :manage_admin do
    plug :accepts, ["json"]
    plug :fetch_session
    plug EirinchanWeb.Plugs.FetchCurrentModerator
    plug EirinchanWeb.Plugs.RequireModerator
    plug EirinchanWeb.Plugs.RequireModeratorRole, role: "admin"
    plug EirinchanWeb.Plugs.RequireSecureManageToken
  end

  scope "/manage", EirinchanWeb do
    pipe_through :browser

    get "/login", ManagePageController, :login
    post "/login/browser", ManagePageController, :create_session
    get "/", ManagePageController, :dashboard
    get "/config/browser", ManagePageController, :config
    patch "/config/browser", ManagePageController, :update_config
    get "/boardlist/browser", ManagePageController, :boardlist
    patch "/boardlist/browser", ManagePageController, :update_boardlist
    get "/dnsbl/browser", ManagePageController, :dnsbl
    patch "/dnsbl/browser", ManagePageController, :update_dnsbl
    get "/flags/browser", ManagePageController, :flags
    patch "/flags/browser", ManagePageController, :update_flags
    get "/themes/browser", ManagePageController, :themes
    get "/themes/browser/:name", ManagePageController, :theme
    post "/themes/browser/:name", ManagePageController, :install_theme
    post "/themes/browser/:name/rebuild", ManagePageController, :rebuild_theme
    delete "/themes/browser/:name", ManagePageController, :delete_theme
    get "/announcement/browser", ManagePageController, :announcement
    post "/announcement/browser", ManagePageController, :upsert_announcement
    delete "/announcement/browser", ManagePageController, :delete_announcement
    get "/pages/browser", ManagePageController, :pages
    post "/pages/browser", ManagePageController, :create_page
    patch "/pages/browser/:id", ManagePageController, :update_page
    delete "/pages/browser/:id", ManagePageController, :delete_page
    get "/news/browser", ManagePageController, :news
    post "/news/browser", ManagePageController, :create_news
    patch "/news/browser/:id", ManagePageController, :update_news
    delete "/news/browser/:id", ManagePageController, :delete_news
    get "/messages/browser", ManagePageController, :messages
    post "/messages/browser", ManagePageController, :create_message
    get "/recent-posts/browser", ManagePageController, :recent_posts
    get "/feedback/browser", ManagePageController, :feedback
    get "/boards/:uri/posts/:post_id/ban/browser", ManagePageController, :ban_post
    post "/boards/:uri/posts/:post_id/ban/browser", ManagePageController, :create_post_ban
    get "/boards/:uri/posts/:post_id/edit/browser", ManagePageController, :edit_post
    patch "/boards/:uri/posts/:post_id/edit/browser", ManagePageController, :update_post_browser
    get "/boards/:uri/threads/:thread_id/move/browser", ManagePageController, :move_thread_form
    get "/boards/:uri/posts/:post_id/move/browser", ManagePageController, :move_reply_form
    get "/reports/browser", ManagePageController, :reports
    delete "/reports/browser/:id", ManagePageController, :dismiss_report
    delete "/reports/browser/post/:post_id", ManagePageController, :dismiss_reports_for_post
    get "/ban-appeals/browser", ManagePageController, :ban_appeals
    patch "/ban-appeals/browser/:id", ManagePageController, :resolve_ban_appeal
    patch "/boards/:uri/threads/:thread_id/browser/move", ManagePageController, :move_thread
    patch "/boards/:uri/posts/:post_id/browser/move", ManagePageController, :move_reply
    get "/ip/:ip/browser", ManagePageController, :ip_history
    delete "/ip/:ip/browser/posts", ManagePageController, :delete_ip_posts
    get "/boards/:uri/ip/:ip/browser", ManagePageController, :board_ip_history
    post "/boards/:uri/ip/:ip/browser/notes", ManagePageController, :create_ip_note
    patch "/boards/:uri/ip/:ip/browser/notes/:id", ManagePageController, :update_ip_note
    delete "/boards/:uri/ip/:ip/browser/notes/:id", ManagePageController, :delete_ip_note
    delete "/boards/:uri/ip/:ip/browser/posts", ManagePageController, :delete_board_ip_posts
    get "/boards/:uri/reports/browser", ManagePageController, :reports
    delete "/boards/:uri/reports/browser/:id", ManagePageController, :dismiss_report

    delete "/boards/:uri/reports/browser/post/:post_id",
           ManagePageController,
           :dismiss_reports_for_post

    get "/boards/:uri/ban-appeals/browser", ManagePageController, :ban_appeals
    patch "/boards/:uri/ban-appeals/browser/:id", ManagePageController, :resolve_ban_appeal
    get "/boards/:uri/config/browser", ManagePageController, :board_config
    patch "/boards/:uri/config/browser", ManagePageController, :update_board_config
    post "/boards/browser", ManagePageController, :create_board
    patch "/boards/:uri/browser", ManagePageController, :update_board
    delete "/boards/:uri/browser", ManagePageController, :delete_board
    post "/boards/:uri/browser/rebuild", ManagePageController, :rebuild_board
    delete "/logout/browser", ManagePageController, :delete_session
  end

  scope "/", EirinchanWeb do
    pipe_through :browser

    get "/mod.php", LegacyModController, :show
    get "/b.php", BannerController, :show
    get "/search.php", SearchController, :show
    post "/post.php", PostController, :create
    post "/theme", ThemeController, :update
    get "/auth", IpAccessAuthController, :show
    post "/auth", IpAccessAuthController, :create
    get "/setup", SetupController, :show
    post "/setup", SetupController, :create
  end

  scope "/manage", EirinchanWeb do
    pipe_through :api

    post "/login", ManageSessionController, :create
    get "/session", ManageSessionController, :show
    get "/secure-token", ManageSessionController, :secure_token
    delete "/logout", ManageSessionController, :delete
  end

  scope "/manage", EirinchanWeb do
    pipe_through :manage_api

    get "/dashboard", ModDashboardController, :show
    get "/recent-posts", ModDashboardController, :recent
    get "/ip/:ip", IpManagementController, :show
    get "/boards/:uri/threads/:thread_id", ThreadManagementController, :show
    get "/boards/:uri/ip/:ip", IpManagementController, :board_show
    get "/boards/:uri/posts/:post_id", PostManagementController, :show
    get "/boards/:uri/bans", BanManagementController, :index
    get "/boards/:uri/ban-appeals", BanAppealManagementController, :index
    get "/boards/:uri/reports", ReportManagementController, :index
    get "/feedback", FeedbackManagementController, :index
    get "/boards", BoardManagementController, :index
    get "/boards/:uri", BoardManagementController, :show
  end

  scope "/manage", EirinchanWeb do
    pipe_through :manage_mod

    patch "/feedback/:id/read", FeedbackManagementController, :mark_read
    post "/feedback/:id/comments", FeedbackManagementController, :create_comment
    delete "/feedback/:id", FeedbackManagementController, :delete
    delete "/ip/:ip/posts", IpManagementController, :delete_posts
    post "/boards/:uri/rebuild", BuildManagementController, :create
    patch "/boards/:uri/threads/:thread_id/move", ThreadManagementController, :move
    patch "/boards/:uri/threads/:thread_id", ThreadManagementController, :update
    post "/boards/:uri/ip/:ip/notes", IpManagementController, :create_note
    patch "/boards/:uri/ip/:ip/notes/:id", IpManagementController, :update_note
    delete "/boards/:uri/ip/:ip/notes/:id", IpManagementController, :delete_note
    delete "/boards/:uri/ip/:ip/posts", IpManagementController, :delete_board_posts
    patch "/boards/:uri/posts/:post_id/move", PostManagementController, :move
    patch "/boards/:uri/posts/:post_id", PostManagementController, :update
    delete "/boards/:uri/posts/:post_id", PostManagementController, :delete
    delete "/boards/:uri/posts/:post_id/file", PostManagementController, :delete_file
    patch "/boards/:uri/posts/:post_id/spoiler", PostManagementController, :spoiler
    post "/boards/:uri/bans", BanManagementController, :create
    patch "/boards/:uri/bans/:id", BanManagementController, :update
    patch "/boards/:uri/ban-appeals/:id", BanAppealManagementController, :update
    delete "/boards/:uri/reports/post/:post_id", ReportManagementController, :delete_post
    delete "/boards/:uri/reports/:id", ReportManagementController, :delete
  end

  scope "/manage", EirinchanWeb do
    pipe_through :manage_admin

    post "/boards", BoardManagementController, :create
    patch "/boards/:uri", BoardManagementController, :update
    delete "/boards/:uri", BoardManagementController, :delete
  end

  scope "/api", EirinchanWeb do
    pipe_through :api

    get "/boards.json", ApiController, :boards
    get "/:board/catalog.json", ApiController, :catalog
    get "/:board/threads.json", ApiController, :threads
    get "/:board/res/:thread_id", ApiController, :thread
    get "/:board/pages/:page_num", ApiController, :page
  end

  scope "/", EirinchanWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/faq", PageController, :faq
    get "/news", PageController, :news
    get "/catalog", PageController, :catalog
    get "/ukko", PageController, :ukko
    get "/recent", PageController, :recent
    get "/sitemap.xml", PageController, :sitemap
    get "/search", SearchController, :show
    get "/pages/:slug", PageController, :page
    get "/feedback", FeedbackController, :show
    post "/feedback", FeedbackController, :create
    get "/:board/thumb/:filename", UploadedFileController, :show_thumb
    get "/:board/src/:filename", UploadedFileController, :show
    get "/:board/catalog.json", ApiController, :catalog
    get "/:board/threads.json", ApiController, :threads
    get "/:board/catalog/:page_num_html", BoardController, :catalog_page
    get "/:board/catalog.html", BoardController, :catalog
    get "/:board/flag", PageController, :board_flag
    get "/:board/:page_num_html", BoardController, :show_page
    get "/:board", BoardController, :show
    post "/:board/post", PostController, :create
    get "/:board/res/:thread_id", ThreadController, :show
  end
end
