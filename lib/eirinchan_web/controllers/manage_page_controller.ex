defmodule EirinchanWeb.ManagePageController do
  use EirinchanWeb, :controller
  import Ecto.Query, only: [from: 2]
  import Phoenix.Template, only: [render_to_string: 4]

  alias Eirinchan.Announcement
  alias Eirinchan.Boardlist
  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Bans
  alias Eirinchan.CustomPages
  alias Eirinchan.DNSBLConfig
  alias Eirinchan.Feedback
  alias Eirinchan.FlagsConfig
  alias Eirinchan.Installation
  alias Eirinchan.Moderation
  alias Eirinchan.News
  alias Eirinchan.Posts.Post
  alias Eirinchan.Reports
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias Eirinchan.Themes
  alias EirinchanWeb.{ManageSecurity, PostView}

  plug :assign_manage_shell

  def login(conn, _params) do
    cond do
      Installation.setup_required?() ->
        redirect(conn, to: ~p"/setup")

      conn.assigns[:current_moderator] ->
        redirect(conn, to: ~p"/manage")

      true ->
        render(conn, :login, error: nil, username: nil)
    end
  end

  def create_session(conn, %{"username" => username, "password" => password}) do
    case Moderation.authenticate(username, password) do
      {:ok, moderator} ->
        secure_token = ManageSecurity.generate_token()

        conn
        |> put_session(:moderator_user_id, moderator.id)
        |> put_session(:secure_manage_token, secure_token)
        |> redirect(to: ~p"/manage")

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> render(:login, error: "Invalid credentials.", username: username)
    end
  end

  def dashboard(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      render(conn, :dashboard,
        moderator: moderator,
        boards: Moderation.list_accessible_boards(moderator),
        report_count: accessible_report_count(moderator),
        appeal_count: accessible_appeal_count(moderator),
        feedback_count: Feedback.unread_count(),
        unread_messages: Moderation.count_unread_messages(moderator),
        announcement: Announcement.current(),
        custom_pages: CustomPages.list_pages(),
        news_entries: News.list_entries(limit: 10),
        error: nil,
        params: %{"uri" => nil, "title" => nil, "subtitle" => nil}
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")
    end
  end

  def config(conn, _params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      render(conn, :config,
        moderator: moderator,
        config_json: Settings.encode_for_edit(Settings.current_instance_config()),
        error: nil
      )
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
      {:error, :forbidden} -> render_config_error(conn, "Administrator access required.")
    end
  end

  def boardlist(conn, _params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      render(conn, :boardlist,
        moderator: moderator,
        boardlist_json: Boardlist.encode_for_edit(Boards.list_boards()),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_boardlist_error(conn, "Administrator access required.")
    end
  end

  def dnsbl(conn, _params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      render(conn, :dnsbl,
        moderator: moderator,
        dnsbl_json: DNSBLConfig.encode_entries_for_edit(),
        dnsbl_exceptions: DNSBLConfig.encode_exceptions_for_edit(),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dnsbl_error(conn, "Administrator access required.")
    end
  end

  def flags(conn, _params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      render(conn, :flags,
        moderator: moderator,
        form: FlagsConfig.form_values(),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_flags_error(conn, "Administrator access required.")
    end
  end

  def faq_editor(conn, _params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      render(conn, :faq_editor,
        moderator: moderator,
        faq_html: current_faq_editor_html(conn),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_faq_editor_error(conn, "Administrator access required.")
    end
  end

  def update_faq(conn, %{"faq_html" => faq_html}) do
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, _page} <- upsert_faq_page(faq_html, moderator.id) do
      conn
      |> put_flash(:info, "FAQ updated.")
      |> redirect(to: ~p"/manage/faq/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_faq_editor_error(conn, "Administrator access required.")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_faq_editor_error(
          conn,
          format_changeset(changeset),
          :unprocessable_entity,
          faq_html
        )
    end
  end

  def update_flags(conn, params) do
    with {:ok, _moderator} <- ensure_admin(conn),
         {:ok, _config} <- FlagsConfig.update(params) do
      conn
      |> put_flash(:info, "Flags configuration updated.")
      |> redirect(to: ~p"/manage/flags/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_flags_error(conn, "Administrator access required.")

      {:error, :invalid_json} ->
        render_flags_error(
          conn,
          "User flags must be valid JSON.",
          :unprocessable_entity,
          %{
            country_flags: Map.get(params, "country_flags", "false") in ["true", "1", "on"],
            allow_no_country: Map.get(params, "allow_no_country", "false") in ["true", "1", "on"],
            country_flags_condensed:
              Map.get(params, "country_flags_condensed", "false") in ["true", "1", "on"],
            country_flags_condensed_css: Map.get(params, "country_flags_condensed_css", ""),
            display_flags: Map.get(params, "display_flags", "false") in ["true", "1", "on"],
            uri_flags: Map.get(params, "uri_flags", ""),
            flag_style: Map.get(params, "flag_style", ""),
            user_flag: Map.get(params, "user_flag", "false") in ["true", "1", "on"],
            multiple_flags: Map.get(params, "multiple_flags", "false") in ["true", "1", "on"],
            default_user_flag: Map.get(params, "default_user_flag", ""),
            user_flags_json: Map.get(params, "user_flags_json", "")
          }
        )
    end
  end

  def update_dnsbl(conn, %{"dnsbl_json" => dnsbl_json, "dnsbl_exceptions" => dnsbl_exceptions}) do
    with {:ok, _moderator} <- ensure_admin(conn),
         {:ok, _config} <- DNSBLConfig.update(dnsbl_json, dnsbl_exceptions) do
      conn
      |> put_flash(:info, "DNSBL configuration updated.")
      |> redirect(to: ~p"/manage/dnsbl/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dnsbl_error(conn, "Administrator access required.")

      {:error, :invalid_json} ->
        render_dnsbl_error(
          conn,
          "DNSBL entries must be valid JSON.",
          :unprocessable_entity,
          dnsbl_json,
          dnsbl_exceptions
        )
    end
  end

  def update_boardlist(conn, %{"boardlist_json" => boardlist_json}) do
    with {:ok, _moderator} <- ensure_admin(conn),
         {:ok, _groups} <- Boardlist.update_from_json(boardlist_json, Boards.list_boards()) do
      conn
      |> put_flash(:info, "Boardlist updated.")
      |> redirect(to: ~p"/manage/boardlist/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_boardlist_error(conn, "Administrator access required.")

      {:error, :invalid_json} ->
        render_boardlist_error(
          conn,
          "Boardlist must be valid JSON.",
          :unprocessable_entity,
          boardlist_json
        )
    end
  end

  def messages(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      _ = Moderation.mark_inbox_read(moderator)

      render(conn, :messages,
        moderator: moderator,
        messages: Moderation.list_inbox(moderator),
        recipients: Moderation.list_recipients(moderator),
        error: nil
      )
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
    end
  end

  def feedback(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      render(conn, :feedback,
        moderator: moderator,
        feedback:
          feedback_entries(
            Feedback.list_feedback(),
            moderator,
            conn.assigns[:secure_manage_token]
          ),
        unread_count: Feedback.unread_count()
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")
    end
  end

  def create_message(conn, params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, _message} <-
           Moderation.send_message(moderator, %{
             recipient_id: params["recipient_id"],
             subject: params["subject"],
             body: params["body"],
             reply_to_id: params["reply_to_id"]
           }) do
      conn
      |> put_flash(:info, "Message sent.")
      |> redirect(to: ~p"/manage/messages/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:messages,
          moderator: conn.assigns[:current_moderator],
          messages: Moderation.list_inbox(conn.assigns.current_moderator),
          recipients: Moderation.list_recipients(conn.assigns.current_moderator),
          error: format_changeset(changeset)
        )
    end
  end

  def update_config(conn, %{"config_json" => config_json}) do
    with {:ok, _moderator} <- ensure_admin(conn),
         {:ok, _config} <- Settings.update_instance_config_from_json(config_json) do
      conn
      |> put_flash(:info, "Instance config updated.")
      |> redirect(to: ~p"/manage/config/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_config_error(conn, "Administrator access required.")

      {:error, :invalid_json} ->
        render_config_error(
          conn,
          "Config must be valid JSON.",
          :unprocessable_entity,
          config_json
        )
    end
  end

  def board_config(conn, %{"uri" => uri}) do
    with {:ok, moderator} <- ensure_admin(conn),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri) do
      render(conn, :board_config,
        moderator: moderator,
        board: board,
        config_json: Settings.encode_for_edit(board.config_overrides || %{}),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      nil ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)
    end
  end

  def update_board_config(conn, %{"uri" => uri, "config_json" => config_json}) do
    with {:ok, _moderator} <- ensure_admin(conn),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         {:ok, overrides} <- parse_config_json(config_json),
         {:ok, _board} <- Boards.update_board(board, %{"config_overrides" => overrides}) do
      conn
      |> put_flash(:info, "Board config updated.")
      |> redirect(to: "/manage/boards/#{uri}/config/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      nil ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)

      {:error, :invalid_json} ->
        render_board_config_error(conn, uri, "Config must be valid JSON.", config_json)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_board_config_error(conn, uri, format_changeset(changeset), config_json)
    end
  end

  def news(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      render(conn, :news,
        moderator: moderator,
        news_entries: News.list_entries(),
        error: nil
      )
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
    end
  end

  def themes(conn, _params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      render(conn, :themes,
        moderator: moderator,
        themes: Themes.all_themes(),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)
    end
  end

  def theme(conn, %{"name" => name}) do
    with {:ok, moderator} <- ensure_admin(conn),
         %{} = theme <- Enum.find(Themes.all_themes(), &(&1.name == String.trim(name))) do
      render(conn, :theme,
        moderator: moderator,
        theme: theme,
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      nil ->
        render_themes_error(conn, "Theme not found.", :not_found)
    end
  end

  def install_theme(conn, %{"name" => name} = params) do
    with {:ok, _moderator} <- ensure_admin(conn),
         {:ok, _theme} <- Themes.install_theme(name, params) do
      conn
      |> put_flash(:info, "Theme installed.")
      |> redirect(to: "/manage/themes/browser/#{name}")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :unsupported} ->
        render_theme_error(
          conn,
          name,
          "This theme is not implemented in Eirinchan.",
          :unprocessable_entity
        )

      {:error, :not_found} ->
        render_themes_error(conn, "Theme not found.", :not_found)
    end
  end

  def delete_theme(conn, %{"name" => name}) do
    with {:ok, _moderator} <- ensure_admin(conn),
         :ok <- Themes.uninstall_theme(name) do
      conn
      |> put_flash(:info, "Theme uninstalled.")
      |> redirect(to: ~p"/manage/themes/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :unsupported} ->
        render_theme_error(
          conn,
          name,
          "This theme is not implemented in Eirinchan.",
          :unprocessable_entity
        )

      {:error, :not_found} ->
        render_themes_error(conn, "Theme not found.", :not_found)
    end
  end

  def rebuild_theme(conn, %{"name" => name}) do
    with {:ok, _moderator} <- ensure_admin(conn),
         :ok <- Themes.rebuild_theme(name) do
      conn
      |> put_flash(:info, "Theme rebuilt.")
      |> redirect(to: "/manage/themes/browser/#{name}")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :unsupported} ->
        render_theme_error(
          conn,
          name,
          "This theme does not support rebuilds in Eirinchan.",
          :unprocessable_entity
        )

      {:error, :not_found} ->
        render_themes_error(conn, "Theme not found.", :not_found)
    end
  end

  defp assign_manage_shell(conn, _opts) do
    conn
    |> assign(:global_boardlist_html, shell_boardlist_html())
    |> assign(:javascript_urls, ["/main.js", "/js/jquery.min.js", "/js/options.js"])
    |> assign(:base_stylesheet, "/stylesheets/style.css")
    |> assign(:primary_stylesheet, "/stylesheets/yotsuba.css")
    |> assign(:primary_stylesheet_id, "stylesheet")
    |> assign(:body_class, "8chan vichan is-not-moderator mod-page")
    |> assign(:body_data_stylesheet, "yotsuba.css")
    |> assign(:extra_stylesheets, ["/stylesheets/eirinchan-mod.css"])
    |> assign(:skip_app_stylesheet, true)
    |> assign(:skip_flash_group, true)
    |> assign(:hide_theme_switcher, true)
  end

  def create_news(conn, %{"title" => title, "body" => body}) do
    with {:ok, moderator} <- ensure_news_editor(conn),
         {:ok, _entry} <-
           News.create_entry(%{title: title, body: body, mod_user_id: moderator.id}) do
      conn
      |> put_flash(:info, "News entry created.")
      |> redirect(to: ~p"/manage/news/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_news_error(conn, "Moderator access required.")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_news_error(conn, format_changeset(changeset), :unprocessable_entity)
    end
  end

  def update_news(conn, %{"id" => id, "title" => title, "body" => body}) do
    with {:ok, _moderator} <- ensure_news_editor(conn),
         %News.Entry{} = entry <- News.get_entry(id),
         {:ok, _entry} <- News.update_entry(entry, %{title: title, body: body}) do
      conn
      |> put_flash(:info, "News entry updated.")
      |> redirect(to: ~p"/manage/news/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_news_error(conn, "Moderator access required.")

      nil ->
        render_news_error(conn, "News entry not found.", :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_news_error(conn, format_changeset(changeset), :unprocessable_entity)
    end
  end

  def delete_news(conn, %{"id" => id}) do
    with {:ok, _moderator} <- ensure_news_editor(conn),
         %News.Entry{} = entry <- News.get_entry(id),
         {:ok, _entry} <- News.delete_entry(entry) do
      conn
      |> put_flash(:info, "News entry deleted.")
      |> redirect(to: ~p"/manage/news/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_news_error(conn, "Moderator access required.")

      nil ->
        render_news_error(conn, "News entry not found.", :not_found)
    end
  end

  def announcement(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      render(conn, :announcement,
        moderator: moderator,
        announcement: Announcement.current(),
        error: nil
      )
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
    end
  end

  def upsert_announcement(conn, %{"title" => title, "body" => body}) do
    with {:ok, moderator} <- ensure_news_editor(conn),
         {:ok, _announcement} <-
           Announcement.upsert(%{title: title, body: body, mod_user_id: moderator.id}) do
      conn
      |> put_flash(:info, "Announcement updated.")
      |> redirect(to: ~p"/manage/announcement/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_announcement_error(conn, "Moderator access required.")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_announcement_error(conn, format_changeset(changeset), :unprocessable_entity)
    end
  end

  def delete_announcement(conn, _params) do
    with {:ok, _moderator} <- ensure_news_editor(conn),
         {:ok, _announcement} <- Announcement.delete_current() do
      conn
      |> put_flash(:info, "Announcement removed.")
      |> redirect(to: ~p"/manage/announcement/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_announcement_error(conn, "Moderator access required.")
    end
  end

  def pages(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      render(conn, :pages,
        moderator: moderator,
        pages: CustomPages.list_pages(),
        error: nil
      )
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
    end
  end

  def create_page(conn, %{"slug" => slug, "title" => title, "body" => body}) do
    with {:ok, moderator} <- ensure_news_editor(conn),
         {:ok, _page} <-
           CustomPages.create_page(%{
             slug: slug,
             title: title,
             body: body,
             mod_user_id: moderator.id
           }) do
      conn
      |> put_flash(:info, "Custom page created.")
      |> redirect(to: ~p"/manage/pages/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_pages_error(conn, "Moderator access required.")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_pages_error(conn, format_changeset(changeset), :unprocessable_entity)
    end
  end

  def update_page(conn, %{"id" => id, "slug" => slug, "title" => title, "body" => body}) do
    with {:ok, _moderator} <- ensure_news_editor(conn),
         %CustomPages.Page{} = page <- load_custom_page(id),
         {:ok, _page} <- CustomPages.update_page(page, %{slug: slug, title: title, body: body}) do
      conn
      |> put_flash(:info, "Custom page updated.")
      |> redirect(to: ~p"/manage/pages/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_pages_error(conn, "Moderator access required.")

      nil ->
        render_pages_error(conn, "Custom page not found.", :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_pages_error(conn, format_changeset(changeset), :unprocessable_entity)
    end
  end

  def delete_page(conn, %{"id" => id}) do
    with {:ok, _moderator} <- ensure_news_editor(conn),
         %CustomPages.Page{} = page <- load_custom_page(id),
         {:ok, _page} <- CustomPages.delete_page(page) do
      conn
      |> put_flash(:info, "Custom page deleted.")
      |> redirect(to: ~p"/manage/pages/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_pages_error(conn, "Moderator access required.")

      nil ->
        render_pages_error(conn, "Custom page not found.", :not_found)
    end
  end

  def recent_posts(conn, params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      boards = Moderation.list_accessible_boards(moderator)
      board_filter = params["board"]

      board_ids =
        case board_filter do
          nil -> Enum.map(boards, & &1.id)
          "" -> Enum.map(boards, & &1.id)
          uri -> boards |> Enum.filter(&(&1.uri == uri)) |> Enum.map(& &1.id)
        end

      limit =
        case Integer.parse(to_string(params["limit"] || "25")) do
          {value, _} -> max(value, 1)
          :error -> 25
        end

      posts =
        Eirinchan.Posts.list_recent_posts(
          limit: limit,
          board_ids: board_ids,
          query: params["query"],
          ip_subnet: params["ip"]
        )

      conn
      |> assign(:javascript_urls, ["/js/mod/recent-posts.js"])
      |> render(:recent_posts,
        moderator: moderator,
        boards: boards,
        entries: recent_post_entries(posts, boards, EirinchanWeb.RequestMeta.request_host(conn)),
        filters: %{
          "board" => params["board"],
          "query" => params["query"],
          "ip" => params["ip"],
          "limit" => Integer.to_string(limit)
        }
      )
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
    end
  end

  def reports(conn, params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      case Map.get(params, "uri") do
        nil ->
          render(conn, :reports,
            moderator: moderator,
            entries:
              report_entries(
                accessible_reports(moderator),
                Moderation.list_accessible_boards(moderator),
                EirinchanWeb.RequestMeta.request_host(conn),
                conn.assigns[:secure_manage_token],
                moderator
              )
          )

        _uri ->
          conn
          |> put_flash(:info, "Reports are managed from the global report queue.")
          |> redirect(to: ~p"/manage/reports/browser")
      end
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")
    end
  end

  def ip_history(conn, %{"ip" => ip}) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      boards = Moderation.list_accessible_boards(moderator)
      board_ids = Enum.map(boards, & &1.id)

      render(conn, :ip_history,
        moderator: moderator,
        boards: boards,
        ip: ip,
        board: nil,
        posts: Moderation.list_ip_posts(ip, board_ids: board_ids),
        notes: Moderation.list_ip_notes(ip, board_ids: board_ids)
      )
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
    end
  end

  def board_ip_history(conn, %{"uri" => uri, "ip" => ip}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri) do
      render(conn, :ip_history,
        moderator: moderator,
        boards: Moderation.list_accessible_boards(moderator),
        ip: ip,
        board: board,
        posts: Moderation.list_ip_posts(ip, board_ids: [board.id]),
        notes: Moderation.list_ip_notes(ip, board_id: board.id)
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)
    end
  end

  def create_ip_note(conn, %{"uri" => uri, "ip" => ip, "body" => body}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         {:ok, _note} <-
           Moderation.add_ip_note(ip, %{
             body: body,
             board_id: board.id,
             mod_user_id: moderator.id
           }) do
      conn
      |> put_flash(:info, "IP note added.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{ip}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def update_ip_note(conn, %{"uri" => uri, "ip" => ip, "id" => id, "body" => body}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         {:ok, note} <- load_board_note(id, board.id),
         {:ok, _note} <- Moderation.update_ip_note(note, %{body: body}) do
      conn
      |> put_flash(:info, "IP note updated.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{ip}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "IP note not found.", %{}, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def delete_ip_note(conn, %{"uri" => uri, "ip" => ip, "id" => id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         {:ok, note} <- load_board_note(id, board.id),
         {:ok, _note} <- Moderation.delete_ip_note(note) do
      conn
      |> put_flash(:info, "IP note deleted.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{ip}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "IP note not found.", %{}, :not_found)
    end
  end

  def delete_ip_posts(conn, %{"ip" => ip}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, _result} <-
           Moderation.list_accessible_boards(moderator)
           |> then(
             &Eirinchan.Posts.moderate_delete_posts_by_ip(&1, ip,
               config_by_board: config_map(&1, EirinchanWeb.RequestMeta.request_host(conn))
             )
           ) do
      conn
      |> put_flash(:info, "Posts deleted for IP.")
      |> redirect(to: "/manage/ip/#{ip}/browser")
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
    end
  end

  def delete_board_ip_posts(conn, %{"uri" => uri, "ip" => ip}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         {:ok, _result} <-
           Eirinchan.Posts.moderate_delete_posts_by_ip(board, ip,
             config: effective_board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      conn
      |> put_flash(:info, "Posts deleted for IP.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{ip}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)
    end
  end

  def dismiss_report(conn, %{"id" => id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         report when not is_nil(report) <- Reports.get_report(id),
         :ok <- authorize_report(moderator, report),
         {:ok, _report} <- Reports.dismiss_report(report.board, id) do
      conn
      |> put_flash(:info, "Report dismissed.")
      |> redirect(to: report_redirect_path(params))
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      nil ->
        render_dashboard_error(conn, "Report not found.", %{}, :not_found)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Report not found.", %{}, :not_found)
    end
  end

  def dismiss_reports_for_post(conn, %{"post_id" => post_id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         report when not is_nil(report) <- accessible_report_for_post(moderator, post_id),
         {:ok, _count} <- Reports.dismiss_reports_for_post(report.board, post_id) do
      conn
      |> put_flash(:info, "Reports dismissed.")
      |> redirect(to: report_redirect_path(params))
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      nil ->
        render_dashboard_error(conn, "Post not found.", %{}, :not_found)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Post not found.", %{}, :not_found)
    end
  end

  def dismiss_reports_for_ip(conn, %{"report_id" => report_id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         report when not is_nil(report) <- Reports.get_report(report_id),
         :ok <- authorize_report(moderator, report),
         {:ok, _count} <-
           Reports.dismiss_reports_for_ip(accessible_report_scope(moderator), report.ip) do
      conn
      |> put_flash(:info, "Reports dismissed.")
      |> redirect(to: report_redirect_path(params))
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      nil ->
        render_dashboard_error(conn, "Report not found.", %{}, :not_found)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Report not found.", %{}, :not_found)
    end
  end

  def ban_post(conn, %{"uri" => uri, "post_id" => post_id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         {:ok, post} <- Eirinchan.Posts.get_post(board, post_id) do
      render(conn, :ban_post,
        moderator: moderator,
        board: board,
        post: post,
        boards: Moderation.list_accessible_boards(moderator),
        error: nil,
        params: %{
          "ip" => Map.get(params, "ip", post.ip_subnet || ""),
          "reason" => Map.get(params, "reason", ""),
          "public_message" => Map.get(params, "public_message", "0"),
          "message" => Map.get(params, "message", "USER WAS BANNED FOR THIS POST"),
          "length" => Map.get(params, "length", ""),
          "board" => Map.get(params, "board", "*"),
          "delete" => Map.get(params, "delete", "0")
        }
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Post not found.", %{}, :not_found)
    end
  end

  def create_post_ban(conn, %{"uri" => uri, "post_id" => post_id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         {:ok, post} <- Eirinchan.Posts.get_post(board, post_id),
         {:ok, target_board_id} <- target_ban_board_id(moderator, params["board"]),
         {:ok, _ban} <-
           Bans.create_ban(%{
             board_id: target_board_id,
             mod_user_id: moderator.id,
             ip_subnet: Map.get(params, "ip", post.ip_subnet),
             reason: params["reason"],
             length: params["length"],
             active: true
           }),
         :ok <-
           maybe_attach_public_ban_message(
             board,
             post,
             params,
             EirinchanWeb.RequestMeta.request_host(conn)
           ),
         {:ok, _deleted} <-
           maybe_moderator_delete_post(
             board,
             post,
             params,
             EirinchanWeb.RequestMeta.request_host(conn)
           ) do
      conn
      |> put_flash(:info, "Ban created.")
      |> redirect(to: moderation_return_path(board, post))
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Post not found.", %{}, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_ban_post_error(conn, uri, post_id, format_changeset(changeset), params)
    end
  end

  def edit_post(conn, %{"uri" => uri, "post_id" => post_id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- moderator.role == "admin",
         {:ok, post} <- Eirinchan.Posts.get_post(board, post_id) do
      render(conn, :edit_post,
        moderator: moderator,
        board: board,
        post: post,
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Post not found.", %{}, :not_found)
    end
  end

  def update_post_browser(conn, %{"uri" => uri, "post_id" => post_id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- moderator.role == "admin",
         {:ok, post} <-
           Eirinchan.Posts.update_post(
             board,
             post_id,
             Map.take(params, ["name", "email", "subject", "body"]),
             config: effective_board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      conn
      |> put_flash(:info, "Post updated.")
      |> redirect(to: moderation_return_path(board, post))
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Post not found.", %{}, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_edit_post_error(conn, uri, post_id, format_changeset(changeset), params)
    end
  end

  def move_thread_form(conn, %{"uri" => uri, "thread_id" => thread_id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         {:ok, thread} <- Eirinchan.Posts.get_post(board, thread_id),
         true <- is_nil(thread.thread_id) do
      render(conn, :move_thread,
        moderator: moderator,
        board: board,
        thread: thread,
        boards: Moderation.list_accessible_boards(moderator),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Thread not found.", %{}, :not_found)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Thread not found.", %{}, :not_found)
    end
  end

  def move_reply_form(conn, %{"uri" => uri, "post_id" => post_id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         {:ok, post} <- Eirinchan.Posts.get_post(board, post_id),
         false <- is_nil(post.thread_id) do
      render(conn, :move_reply,
        moderator: moderator,
        board: board,
        post: post,
        boards: Moderation.list_accessible_boards(moderator),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      true ->
        render_dashboard_error(conn, "Reply not found.", %{}, :not_found)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Reply not found.", %{}, :not_found)
    end
  end

  def move_thread(conn, %{
        "uri" => uri,
        "thread_id" => thread_id,
        "target_board_uri" => target_uri
      }) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, source_board} <- load_accessible_board(moderator, uri),
         {:ok, target_board} <- load_accessible_board(moderator, target_uri),
         {:ok, moved_thread} <-
           Eirinchan.Posts.move_thread(
             source_board,
             thread_id,
             target_board,
             source_config:
               effective_board_config(source_board, EirinchanWeb.RequestMeta.request_host(conn)),
             target_config:
               effective_board_config(target_board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      conn
      |> put_flash(:info, "Thread moved.")
      |> redirect(
        to:
          Eirinchan.ThreadPaths.thread_path(
            target_board,
            moved_thread,
            effective_board_config(target_board, EirinchanWeb.RequestMeta.request_host(conn))
          )
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Move target not found.", %{}, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def move_reply(
        conn,
        %{
          "uri" => uri,
          "post_id" => post_id,
          "target_board_uri" => target_uri,
          "target_thread_id" => target_thread_id
        }
      ) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, source_board} <- load_accessible_board(moderator, uri),
         {:ok, target_board} <- load_accessible_board(moderator, target_uri),
         {:ok, moved_reply} <-
           Eirinchan.Posts.move_reply(
             source_board,
             post_id,
             target_board,
             target_thread_id,
             source_config:
               effective_board_config(source_board, EirinchanWeb.RequestMeta.request_host(conn)),
             target_config:
               effective_board_config(target_board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      conn
      |> put_flash(:info, "Reply moved.")
      |> redirect(
        to:
          Eirinchan.ThreadPaths.thread_path(
            target_board,
            %Eirinchan.Posts.Post{id: moved_reply.thread_id, slug: nil},
            effective_board_config(target_board, EirinchanWeb.RequestMeta.request_host(conn))
          )
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Move target not found.", %{}, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def ban_appeals(conn, params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      case Map.get(params, "uri") do
        nil ->
          render(conn, :ban_appeals,
            moderator: moderator,
            appeals: accessible_appeals(moderator)
          )

        _uri ->
          conn
          |> put_flash(:info, "Ban appeals are managed from the global appeals queue.")
          |> redirect(to: ~p"/manage/ban-appeals/browser")
      end
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")
    end
  end

  def resolve_ban_appeal(conn, %{"id" => id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         appeal when not is_nil(appeal) <- Bans.get_appeal(id),
         :ok <- authorize_appeal(moderator, appeal),
         {:ok, _appeal} <-
           Bans.resolve_appeal(appeal.id, %{
             status: Map.get(params, "status", "resolved"),
             resolution_note: params["resolution_note"]
           }) do
      conn
      |> put_flash(:info, "Appeal updated.")
      |> redirect(to: appeal_redirect_path(params))
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      nil ->
        render_dashboard_error(conn, "Appeal not found.", %{}, :not_found)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Appeal not found.", %{}, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def create_board(conn, params) do
    with {:ok, _moderator} <- ensure_admin(conn),
         {:ok, board} <- Boards.create_board(Map.take(params, ["uri", "title", "subtitle"])) do
      conn
      |> put_flash(:info, "Board created.")
      |> redirect(to: "/#{board.uri}")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> render(:dashboard,
          moderator: conn.assigns[:current_moderator],
          boards: Moderation.list_accessible_boards(conn.assigns[:current_moderator]),
          report_count: accessible_report_count(conn.assigns[:current_moderator]),
          appeal_count: accessible_appeal_count(conn.assigns[:current_moderator]),
          unread_messages: Moderation.count_unread_messages(conn.assigns[:current_moderator]),
          announcement: Announcement.current(),
          custom_pages: CustomPages.list_pages(),
          news_entries: News.list_entries(limit: 10),
          error: "Administrator access required.",
          params: Map.take(stringify(params), ["uri", "title", "subtitle"])
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:dashboard,
          moderator: conn.assigns.current_moderator,
          boards: Moderation.list_accessible_boards(conn.assigns.current_moderator),
          report_count: accessible_report_count(conn.assigns.current_moderator),
          appeal_count: accessible_appeal_count(conn.assigns.current_moderator),
          unread_messages: Moderation.count_unread_messages(conn.assigns.current_moderator),
          announcement: Announcement.current(),
          custom_pages: CustomPages.list_pages(),
          news_entries: News.list_entries(limit: 10),
          error: format_changeset(changeset),
          params: Map.take(stringify(params), ["uri", "title", "subtitle"])
        )
    end
  end

  def update_board(conn, %{"uri" => uri} = params) do
    with {:ok, _moderator} <- ensure_admin(conn),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         {:ok, _board} <- Boards.update_board(board, Map.take(params, ["title", "subtitle"])) do
      conn
      |> put_flash(:info, "Board updated.")
      |> redirect(to: ~p"/manage")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", params)

      nil ->
        render_dashboard_error(conn, "Board not found.", params, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), params, :unprocessable_entity)
    end
  end

  def delete_board(conn, %{"uri" => uri}) do
    with {:ok, _moderator} <- ensure_admin(conn),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         {:ok, _board} <- Boards.delete_board(board) do
      conn
      |> put_flash(:info, "Board deleted.")
      |> redirect(to: ~p"/manage")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      nil ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)
    end
  end

  def rebuild_board(conn, %{"uri" => uri}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         true <- Moderation.board_access?(moderator, board) or moderator.role == "admin" do
      config = effective_board_config(board, EirinchanWeb.RequestMeta.request_host(conn))

      _result =
        case config.generation_strategy do
          "defer" -> Build.process_pending(board: board, config: config)
          _ -> Build.rebuild_board(board, config: config)
        end

      conn
      |> put_flash(:info, "Board rebuilt.")
      |> redirect(to: ~p"/manage")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      nil ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)
    end
  end

  def delete_session(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/manage/login")
  end

  defp ensure_moderator(%Plug.Conn{assigns: %{current_moderator: nil}}),
    do: {:error, :unauthorized}

  defp ensure_moderator(%Plug.Conn{assigns: %{current_moderator: moderator}}),
    do: {:ok, moderator}

  defp ensure_admin(conn) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      if moderator.role == "admin", do: {:ok, moderator}, else: {:error, :forbidden}
    end
  end

  defp ensure_news_editor(conn) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      if moderator.role in ["admin", "mod"], do: {:ok, moderator}, else: {:error, :forbidden}
    end
  end

  defp stringify(params), do: Enum.into(params, %{}, fn {k, v} -> {to_string(k), v} end)

  defp render_dashboard_error(conn, message, params, status \\ :forbidden) do
    conn
    |> put_status(status)
    |> render(:dashboard,
      moderator: conn.assigns[:current_moderator],
      boards: Moderation.list_accessible_boards(conn.assigns[:current_moderator]),
      report_count: accessible_report_count(conn.assigns[:current_moderator]),
      appeal_count: accessible_appeal_count(conn.assigns[:current_moderator]),
      unread_messages: Moderation.count_unread_messages(conn.assigns[:current_moderator]),
      announcement: Announcement.current(),
      custom_pages: CustomPages.list_pages(),
      news_entries: News.list_entries(limit: 10),
      error: message,
      params: Map.take(stringify(params), ["uri", "title", "subtitle"])
    )
  end

  defp render_news_error(conn, message, status \\ :forbidden) do
    conn
    |> put_status(status)
    |> render(:news,
      moderator: conn.assigns[:current_moderator],
      news_entries: News.list_entries(),
      error: message
    )
  end

  defp render_announcement_error(conn, message, status \\ :forbidden) do
    conn
    |> put_status(status)
    |> render(:announcement,
      moderator: conn.assigns[:current_moderator],
      announcement: Announcement.current(),
      error: message
    )
  end

  defp render_pages_error(conn, message, status \\ :forbidden) do
    conn
    |> put_status(status)
    |> render(:pages,
      moderator: conn.assigns[:current_moderator],
      pages: CustomPages.list_pages(),
      error: message
    )
  end

  defp render_themes_error(conn, message, status) do
    conn
    |> put_status(status)
    |> render(:themes,
      moderator: conn.assigns[:current_moderator],
      themes: Themes.all_themes(),
      error: message
    )
  end

  defp render_theme_error(conn, name, message, status) do
    case Enum.find(Themes.all_themes(), &(&1.name == String.trim(to_string(name)))) do
      nil ->
        render_themes_error(conn, message, status)

      theme ->
        conn
        |> put_status(status)
        |> render(:theme,
          moderator: conn.assigns[:current_moderator],
          theme: theme,
          error: message
        )
    end
  end

  defp render_config_error(conn, message, status \\ :forbidden, config_json \\ "{}") do
    conn
    |> put_status(status)
    |> render(:config,
      moderator: conn.assigns[:current_moderator],
      config_json: config_json,
      error: message
    )
  end

  defp render_boardlist_error(conn, message, status \\ :forbidden, boardlist_json \\ "[]") do
    conn
    |> put_status(status)
    |> render(:boardlist,
      moderator: conn.assigns[:current_moderator],
      boardlist_json: boardlist_json,
      error: message
    )
  end

  defp render_dnsbl_error(
         conn,
         message,
         status \\ :forbidden,
         dnsbl_json \\ "[]",
         dnsbl_exceptions \\ ""
       ) do
    conn
    |> put_status(status)
    |> render(:dnsbl,
      moderator: conn.assigns[:current_moderator],
      dnsbl_json: dnsbl_json,
      dnsbl_exceptions: dnsbl_exceptions,
      error: message
    )
  end

  defp render_flags_error(conn, message, status \\ :forbidden, form \\ FlagsConfig.form_values()) do
    conn
    |> put_status(status)
    |> render(:flags,
      moderator: conn.assigns[:current_moderator],
      form: form,
      error: message
    )
  end

  defp render_faq_editor_error(conn, message, status \\ :forbidden, faq_html \\ "") do
    conn
    |> put_status(status)
    |> render(:faq_editor,
      moderator: conn.assigns[:current_moderator],
      faq_html: faq_html,
      error: message
    )
  end

  defp render_board_config_error(conn, uri, message, config_json, status \\ :unprocessable_entity) do
    conn
    |> put_status(status)
    |> render(:board_config,
      moderator: conn.assigns[:current_moderator],
      board: Boards.get_board_by_uri(uri),
      config_json: config_json,
      error: message
    )
  end

  defp load_accessible_board(moderator, uri) do
    case Boards.get_board_by_uri(uri) do
      nil ->
        {:error, :not_found}

      board ->
        if moderator.role == "admin" or Moderation.board_access?(moderator, board) do
          {:ok, board}
        else
          {:error, :forbidden}
        end
    end
  end

  defp load_board_note(id, board_id) do
    case Eirinchan.Repo.get(Eirinchan.Moderation.IpNote, id) do
      %{board_id: ^board_id} = note -> {:ok, note}
      _ -> {:error, :not_found}
    end
  end

  defp config_map(boards, host) do
    Map.new(boards, fn board -> {board.id, effective_board_config(board, host)} end)
  end

  defp accessible_reports(%{role: "admin"}), do: Reports.list_reports()

  defp accessible_reports(moderator) do
    board_ids =
      moderator
      |> Moderation.list_accessible_boards()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    Reports.list_reports()
    |> Enum.filter(&MapSet.member?(board_ids, &1.board_id))
  end

  defp accessible_report_count(nil), do: 0
  defp accessible_report_count(moderator), do: moderator |> accessible_reports() |> length()

  defp accessible_report_for_post(moderator, post_id) do
    accessible_reports(moderator)
    |> Enum.find(fn report ->
      Integer.to_string(report.post_id) == String.trim(to_string(post_id))
    end)
  end

  defp authorize_report(%{role: "admin"}, _report), do: :ok

  defp authorize_report(moderator, %{board: board}) when not is_nil(board) do
    if Moderation.board_access?(moderator, board), do: :ok, else: {:error, :forbidden}
  end

  defp authorize_report(_moderator, _report), do: {:error, :not_found}

  defp accessible_appeals(%{role: "admin"}), do: Bans.list_appeals(status: "open")

  defp accessible_appeals(moderator) do
    board_ids =
      moderator
      |> Moderation.list_accessible_boards()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    Bans.list_appeals(status: "open")
    |> Enum.filter(fn appeal ->
      appeal.ban && MapSet.member?(board_ids, appeal.ban.board_id)
    end)
  end

  defp accessible_appeal_count(nil), do: 0
  defp accessible_appeal_count(moderator), do: moderator |> accessible_appeals() |> length()

  defp recent_post_entries(posts, boards, host) do
    posts = Repo.preload(posts, :extra_files)

    thread_ids =
      posts
      |> Enum.map(&(&1.thread_id || &1.id))
      |> Enum.uniq()

    thread_map =
      Repo.all(from post in Post, where: post.id in ^thread_ids)
      |> Repo.preload(:extra_files)
      |> Map.new(&{&1.id, &1})

    config_by_board = config_map(boards, host)

    Enum.map(posts, fn post ->
      board = post.board
      thread = Map.get(thread_map, post.thread_id || post.id, post)

      %{
        post: post,
        board: board,
        thread: thread,
        config: Map.fetch!(config_by_board, board.id)
      }
    end)
  end

  defp report_entries(reports, boards, host, session_token, moderator) do
    reports = Repo.preload(reports, [:board, post: [:extra_files], thread: [:extra_files]])
    config_by_board = config_map(boards, host)

    Enum.map(reports, fn report ->
      board = report.board
      post = report.post
      thread = report.thread || post

      %{
        report: report,
        board: board,
        post: post,
        thread: thread,
        config: Map.fetch!(config_by_board, board.id),
        displayed_ip: EirinchanWeb.IpPresentation.display_ip(report.ip, moderator),
        dismiss_token: ManageSecurity.sign_action(session_token, "reports/#{report.id}/dismiss"),
        dismiss_all_token:
          ManageSecurity.sign_action(session_token, "reports/#{report.id}/dismiss&all"),
        dismiss_post_token:
          ManageSecurity.sign_action(session_token, "reports/#{report.id}/dismiss&post")
      }
    end)
  end

  defp feedback_entries(entries, moderator, session_token) do
    Enum.map(entries, fn entry ->
      %{
        feedback: entry,
        displayed_ip: EirinchanWeb.IpPresentation.display_ip(entry.ip_subnet, moderator),
        delete_token: ManageSecurity.sign_action(session_token, "feedback/#{entry.id}/delete"),
        mark_read_token:
          ManageSecurity.sign_action(session_token, "feedback/#{entry.id}/mark_read")
      }
    end)
  end

  defp authorize_appeal(%{role: "admin"}, _appeal), do: :ok

  defp authorize_appeal(moderator, %{ban: %{board: board}}) when not is_nil(board) do
    if Moderation.board_access?(moderator, board), do: :ok, else: {:error, :forbidden}
  end

  defp authorize_appeal(_moderator, _appeal), do: {:error, :not_found}

  defp report_redirect_path(%{"uri" => uri}), do: "/manage/boards/#{uri}/reports/browser"
  defp report_redirect_path(_params), do: "/manage/reports/browser"

  defp accessible_report_scope(%{role: "admin"}), do: nil
  defp accessible_report_scope(moderator), do: Moderation.list_accessible_boards(moderator)

  defp appeal_redirect_path(%{"uri" => uri}), do: "/manage/boards/#{uri}/ban-appeals/browser"
  defp appeal_redirect_path(_params), do: "/manage/ban-appeals/browser"

  defp load_custom_page(id), do: Eirinchan.Repo.get(Eirinchan.CustomPages.Page, id)

  defp current_faq_editor_html(conn) do
    case CustomPages.get_page_by_slug("faq") do
      %CustomPages.Page{body: body} when is_binary(body) and body != "" ->
        body

      _ ->
        default_faq_editor_html(conn)
    end
  end

  defp default_faq_editor_html(conn) do
    page = %{slug: "faq", title: "FAQ", body: "", mod_user: nil}

    assigns =
      [
        page: page,
        flag_board: nil,
        flag_assets: [],
        flag_storage_key: "flag_bant",
        page_title: "FAQ",
        layout: false,
        inner_content: nil
      ] ++ faq_public_assigns(conn)

    inner_content = render_to_string(EirinchanWeb.PageHTML, "faq", "html", assigns)

    render_to_string(
      EirinchanWeb.Layouts,
      "root",
      "html",
      Keyword.put(assigns, :inner_content, Phoenix.HTML.raw(inner_content))
    )
  end

  defp faq_public_assigns(conn) do
    boards = Boards.list_boards()
    primary_board = Enum.find(boards, &(&1.uri == "bant")) || %{uri: "bant"}

    [
      boards: boards,
      primary_board: primary_board,
      board_chrome: EirinchanWeb.BoardChrome.for_board(primary_board),
      global_boardlist_html: PostView.boardlist_html(PostView.boardlist_groups(boards)),
      public_shell: true,
      viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
      base_stylesheet: "/stylesheets/style.css",
      body_class: "8chan vichan is-not-moderator active-page",
      body_data_stylesheet:
        Path.basename(conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"),
      head_html:
        EirinchanWeb.PublicShell.head_html("page",
          resource_version: conn.assigns[:asset_version],
          theme_label: conn.assigns[:theme_label],
          theme_options: conn.assigns[:theme_options]
        ),
      javascript_urls: EirinchanWeb.PublicShell.javascript_urls("page"),
      custom_javascript_urls: [],
      analytics_html: nil,
      body_end_html: EirinchanWeb.PublicShell.body_end_html(),
      primary_stylesheet: conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css",
      primary_stylesheet_id: "stylesheet",
      extra_stylesheets: [
        "/stylesheets/eirinchan-public.css",
        "/stylesheets/eirinchan-bant.css",
        "/faq/recent.css"
      ],
      hide_theme_switcher: true,
      skip_app_stylesheet: true
    ]
  end

  defp upsert_faq_page(faq_html, mod_user_id) do
    case CustomPages.get_page_by_slug("faq") do
      nil ->
        CustomPages.create_page(%{
          slug: "faq",
          title: "FAQ",
          body: faq_html,
          mod_user_id: mod_user_id
        })

      page ->
        CustomPages.update_page(page, %{
          slug: "faq",
          title: page.title || "FAQ",
          body: faq_html,
          mod_user_id: mod_user_id
        })
    end
  end

  defp format_changeset(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp effective_board_config(board_record, request_host) do
    Config.compose(nil, Settings.current_instance_config(), board_record.config_overrides || %{},
      board: Eirinchan.Boards.BoardRecord.to_board(board_record),
      request_host: request_host
    )
  end

  defp parse_config_json(raw_json) when is_binary(raw_json) do
    with {:ok, decoded} <- Jason.decode(raw_json),
         true <- is_map(decoded) do
      {:ok, Config.normalize_override_keys(decoded)}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      false -> {:error, :invalid_json}
    end
  end

  defp maybe_moderator_delete_post(board, post, params, host) do
    if Map.get(params, "delete_post") in ["1", "true", "on"] or
         Map.get(params, "delete") in ["1", "true", "on"] do
      Eirinchan.Posts.moderate_delete_post(board, post.id,
        config: effective_board_config(board, host)
      )
    else
      {:ok, post}
    end
  end

  defp moderation_return_path(board, post) do
    if is_nil(post.thread_id) do
      "/#{board.uri}/res/#{post.id}.html"
    else
      "/#{board.uri}/res/#{post.thread_id}.html##{post.id}"
    end
  end

  defp render_ban_post_error(conn, uri, post_id, message, params, status \\ :unprocessable_entity) do
    board = Boards.get_board_by_uri(uri)
    {:ok, post} = Eirinchan.Posts.get_post(board, post_id)
    moderator = conn.assigns[:current_moderator]

    conn
    |> put_status(status)
    |> render(:ban_post,
      moderator: moderator,
      board: board,
      post: post,
      boards: Moderation.list_accessible_boards(moderator),
      error: message,
      params: %{
        "ip" => Map.get(params, "ip", post.ip_subnet || ""),
        "reason" => Map.get(params, "reason", ""),
        "public_message" => Map.get(params, "public_message", "0"),
        "message" => Map.get(params, "message", "USER WAS BANNED FOR THIS POST"),
        "length" => Map.get(params, "length", ""),
        "board" => Map.get(params, "board", "*"),
        "delete" => Map.get(params, "delete", "0")
      }
    )
  end

  defp target_ban_board_id(_moderator, nil), do: {:ok, nil}
  defp target_ban_board_id(_moderator, ""), do: {:ok, nil}
  defp target_ban_board_id(_moderator, "*"), do: {:ok, nil}

  defp target_ban_board_id(moderator, uri) do
    case load_accessible_board(moderator, uri) do
      {:ok, board} -> {:ok, board.id}
      error -> error
    end
  end

  defp maybe_attach_public_ban_message(board, post, params, host) do
    enabled? = Map.get(params, "public_message", "0") in ["1", "true", "on"]

    message =
      Map.get(params, "message", "")
      |> to_string()
      |> String.replace(~r/[\r\n]+/, " ")
      |> String.trim()

    cond do
      not enabled? ->
        :ok

      message == "" ->
        :ok

      true ->
        length_text =
          case Bans.parse_length(Map.get(params, "length")) do
            {:ok, nil} -> "permanently"
            {:ok, expires_at} -> "for " <> human_ban_until(expires_at)
            {:error, :invalid_length} -> "permanently"
          end

        public_message =
          message
          |> String.replace("%length%", length_text)
          |> String.replace("%LENGTH%", String.upcase(length_text))

        updated_body =
          [post.body, "[Ban message] #{public_message}"]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n")

        case Eirinchan.Posts.update_post(
               board,
               post.id,
               %{"body" => updated_body},
               config: board_config(board, host)
             ) do
          {:ok, _updated_post} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp human_ban_until(expires_at) do
    seconds = max(DateTime.diff(expires_at, DateTime.utc_now(), :second), 0)

    cond do
      seconds >= 365 * 24 * 60 * 60 -> "#{div(seconds, 365 * 24 * 60 * 60)} years"
      seconds >= 30 * 24 * 60 * 60 -> "#{div(seconds, 30 * 24 * 60 * 60)} months"
      seconds >= 7 * 24 * 60 * 60 -> "#{div(seconds, 7 * 24 * 60 * 60)} weeks"
      seconds >= 24 * 60 * 60 -> "#{div(seconds, 24 * 60 * 60)} days"
      seconds >= 60 * 60 -> "#{div(seconds, 60 * 60)} hours"
      seconds >= 60 -> "#{div(seconds, 60)} minutes"
      true -> "#{seconds} seconds"
    end
  end

  defp render_edit_post_error(
         conn,
         uri,
         post_id,
         message,
         params,
         status \\ :unprocessable_entity
       ) do
    board = Boards.get_board_by_uri(uri)
    {:ok, post} = Eirinchan.Posts.get_post(board, post_id)

    post = %{
      post
      | name: Map.get(params, "name", post.name),
        email: Map.get(params, "email", post.email),
        subject: Map.get(params, "subject", post.subject),
        body: Map.get(params, "body", post.body)
    }

    conn
    |> put_status(status)
    |> render(:edit_post,
      moderator: conn.assigns[:current_moderator],
      board: board,
      post: post,
      error: message
    )
  end

  defp shell_boardlist_html do
    Boards.list_boards()
    |> PostView.default_boardlist_groups()
    |> PostView.boardlist_html()
  end
end
