defmodule EirinchanWeb.ManagePageController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boardlist
  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Bans
  alias Eirinchan.CustomPages
  alias Eirinchan.DNSBLConfig
  alias Eirinchan.Feedback
  alias Eirinchan.IpCrypt
  alias Eirinchan.FlagsConfig
  alias Eirinchan.Installation
  alias Eirinchan.ManageLoginThrottle
  alias Eirinchan.Moderation
  alias Eirinchan.ModerationLog
  alias Eirinchan.Noticeboard
  alias Eirinchan.Reports
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias Eirinchan.Themes
  alias Eirinchan.WhaleStickers
  alias EirinchanWeb.{BoardRuntime, BrowserEntries}
  alias EirinchanWeb.{ManageSecurity, ModerationAudit, PostView, RequestMeta}

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
    config = Settings.current_instance_config()
    remote_ip = RequestMeta.effective_remote_ip(conn)

    case ManageLoginThrottle.allowed?(username, remote_ip, config) do
      :ok ->
        case Moderation.authenticate(username, password) do
          {:ok, moderator} ->
            ManageLoginThrottle.clear(username, remote_ip)
            ModerationAudit.log(conn, "Logged in", moderator: moderator)

            conn
            |> establish_moderator_session(moderator, remote_ip)
            |> redirect(to: ~p"/manage")

          {:error, :invalid_credentials} ->
            handle_failed_browser_login(conn, username, remote_ip, config)
        end

      {:error, _retry_after} ->
        conn
        |> put_status(:too_many_requests)
        |> render(:login, error: "Too many login attempts. Try again later.", username: username)
    end
  end

  def dashboard(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      render(conn, :dashboard, dashboard_assigns(moderator))
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")
    end
  end

  def noticeboard(conn, params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      config = Settings.current_instance_config()
      page = positive_integer_param(params["page"], 1)
      per_page = positive_integer_param(Map.get(config, :noticeboard_page, 50), Noticeboard.page_size_default())
      entries = Noticeboard.list_entries(page: page, per_page: per_page)
      total_entries = Noticeboard.count_entries()

      if entries == [] and page > 1 do
        render_noticeboard_error(conn, moderator, "Noticeboard page not found.", page, :not_found)
      else
        render(conn, :noticeboard,
          moderator: moderator,
          noticeboard: entries,
          count: total_entries,
          page: page,
          page_count: Noticeboard.page_count(total_entries, per_page),
          error: nil,
          can_post_noticeboard?: moderator.role in ["admin", "mod"],
          can_delete_noticeboard?: moderator.role == "admin"
        )
      end
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")
    end
  end

  def create_noticeboard(conn, params) do
    with {:ok, moderator} <- ensure_noticeboard_poster(conn),
         {:ok, entry} <-
           Noticeboard.create_entry(%{
             subject: params["subject"],
             body: params["body"],
             author_name: moderator.username,
             mod_user_id: moderator.id,
             posted_at: NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second)
           }) do
      ModerationAudit.log(conn, "Posted a noticeboard entry", moderator: moderator)

      conn
      |> put_flash(:info, "Noticeboard entry posted.")
      |> redirect(to: ~p"/manage/noticeboard" <> "##{entry.id}")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Moderator access required.", %{}, :forbidden)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_noticeboard_error(
          conn,
          conn.assigns[:current_moderator],
          format_changeset(changeset),
          1,
          :unprocessable_entity
        )
    end
  end

  def delete_noticeboard(conn, %{"id" => id, "token" => token}) do
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, entry_id} <- verify_noticeboard_delete_token(token),
         true <- Integer.to_string(entry_id) == to_string(id),
         %Noticeboard.Entry{} = entry <- Noticeboard.get_entry(id),
         {:ok, _entry} <- Noticeboard.delete_entry(entry) do
      ModerationAudit.log(conn, "Deleted a noticeboard entry", moderator: moderator)

      conn
      |> put_flash(:info, "Noticeboard entry deleted.")
      |> redirect(to: ~p"/manage/noticeboard")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :invalid_token} ->
        render_dashboard_error(conn, "Invalid noticeboard delete token.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Invalid noticeboard delete token.", %{}, :forbidden)

      nil ->
        render_dashboard_error(conn, "Noticeboard entry not found.", %{}, :not_found)
    end
  end

  def moderation_log(conn, params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      page = positive_integer_param(params["page"], 1)
      username = normalize_filter(params["username"])
      board_uri = normalize_filter(params["board"])
      page_size = ModerationLog.default_page_size()

      total_entries =
        ModerationLog.count_entries(username: username, board_uri: board_uri)

      render(conn, :log,
        moderator: moderator,
        entries:
          ModerationLog.list_entries(
            page: page,
            page_size: page_size,
            username: username,
            board_uri: board_uri
          ),
        page: page,
        page_count: max(div(total_entries + page_size - 1, page_size), 1),
        username: username,
        board_uri: board_uri,
        show_ip: PostView.can_view_ip?(moderator),
        config: Settings.current_instance_config()
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)
    end
  end

  def bans(conn, params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      boards = Moderation.list_accessible_boards(moderator)
      filters = ban_list_filters(params, moderator)

      conn
      |> assign(:extra_stylesheets, (conn.assigns[:extra_stylesheets] || []) ++ [
        "/stylesheets/longtable/longtable.css",
        "/stylesheets/mod/ban-list.css"
      ])
      |> assign(:custom_javascript_urls, [
        "/js/strftime.min.js",
        "/js/longtable/longtable.js",
        "/js/mod/ban-list.js"
      ])
      |> render(:bans,
        moderator: moderator,
        boards: boards,
        filters: filters,
        only_mine_available?: moderator.role != "admin",
        config: Settings.current_instance_config()
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")
    end
  end

  def bans_json(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      boards = Moderation.list_accessible_boards(moderator)
      board_ids = Enum.map(boards, & &1.id)
      boards_by_id = Map.new(boards, &{&1.id, &1})

      json(
        conn,
        Bans.list_bans()
        |> Enum.filter(& &1.active)
        |> Enum.filter(&accessible_ban?(board_ids, &1))
        |> Enum.map(&ban_list_row(&1, boards_by_id))
      )
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  def update_bans(conn, params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      case params["action"] do
        "filter" ->
          filters = ban_list_filters(params, moderator)

          redirect(conn,
            to:
              ~p"/manage/bans/browser?#{%{
                only_mine: filters["only_mine"],
                only_not_expired: filters["only_not_expired"],
                search: filters["search"]
              }}"
          )

        _ ->
          boards = Moderation.list_accessible_boards(moderator)
          board_ids = Enum.map(boards, & &1.id)

          ban_ids =
            selected_ban_ids(params)

          bans =
            Bans.list_bans()
            |> Enum.filter(&accessible_ban?(board_ids, &1))
            |> Enum.filter(&(&1.id in ban_ids))

          Enum.each(bans, fn ban ->
            {:ok, _ban} = Bans.update_ban(ban, %{active: false})
          end)

          if bans != [] do
            ModerationAudit.log(
              conn,
              "Removed #{length(bans)} ban" <> if(length(bans) == 1, do: "", else: "s"),
              moderator: moderator
            )
          end

          conn
          |> put_flash(:info, if(bans == [], do: "No bans selected.", else: "Ban(s) removed."))
          |> redirect(to: ~p"/manage/bans/browser")
      end
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")
    end
  end

  def ban_browser(conn, %{"id" => id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, ban} <- load_accessible_ban(id, moderator) do
      render(conn, :ban,
        moderator: moderator,
        ban: Repo.preload(ban, [:board, :mod_user]),
        boards: Moderation.list_accessible_boards(moderator),
        ban_form: maybe_apply_edit_ban(%{}, ban),
        config: Settings.current_instance_config()
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Ban not found.", %{}, :not_found)
    end
  end

  def update_ban_browser(conn, %{"id" => id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, ban} <- load_accessible_ban(id, moderator),
         {:ok, target_board_id} <- target_ban_board_id(moderator, params["board"]),
         {:ok, _ban} <-
           Bans.update_ban(ban, %{
             board_id: target_board_id,
             ip_subnet: normalize_ban_ip_mask(Map.get(params, "ip_mask", ban.ip_subnet)),
             reason: params["reason"],
             length: params["length"],
             active: true
           }) do
      ModerationAudit.log(conn, "Updated ban ##{ban.id}", moderator: moderator)

      conn
      |> put_flash(:info, "Ban updated.")
      |> redirect(to: "/manage/bans/#{ban.id}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Ban not found.", %{}, :not_found)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_ban_browser_error(conn, id, format_changeset(changeset), params)
    end
  end

  def delete_ban_browser(conn, %{"id" => id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, ban} <- load_accessible_ban(id, moderator),
         {:ok, _ban} <- Bans.update_ban(ban, %{active: false}) do
      ModerationAudit.log(conn, "Removed ban ##{ban.id}", moderator: moderator)

      conn
      |> put_flash(:info, "Ban removed.")
      |> redirect(to: "/manage/bans/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Ban not found.", %{}, :not_found)
    end
  end

  def config(conn, _params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      render(conn, :config,
        moderator: moderator,
        config_json:
          Settings.raw_instance_config_json() ||
            Settings.encode_for_edit(Settings.current_instance_config()),
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

  def stickers(conn, _params) do
    with {:ok, moderator} <- ensure_admin(conn) do
      render(conn, :stickers,
        moderator: moderator,
        stickers_json: WhaleStickers.encode_for_edit(),
        error: nil
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_stickers_error(conn, "Administrator access required.")
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

  def update_flags(conn, params) do
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, _config} <- FlagsConfig.update(params) do
      ModerationAudit.log(conn, "Updated flags configuration", moderator: moderator)

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
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, _config} <- DNSBLConfig.update(dnsbl_json, dnsbl_exceptions) do
      ModerationAudit.log(conn, "Updated DNSBL configuration", moderator: moderator)

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

  def update_stickers(conn, %{"stickers_json" => stickers_json}) do
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, _stickers} <- WhaleStickers.update(stickers_json) do
      ModerationAudit.log(conn, "Updated sticker configuration", moderator: moderator)

      conn
      |> put_flash(:info, "Sticker configuration updated.")
      |> redirect(to: ~p"/manage/stickers/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_stickers_error(conn, "Administrator access required.")

      {:error, :invalid_json} ->
        render_stickers_error(
          conn,
          "Sticker entries must be valid JSON.",
          :unprocessable_entity,
          stickers_json
        )
    end
  end

  def update_boardlist(conn, %{"boardlist_json" => boardlist_json}) do
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, _groups} <- Boardlist.update_from_json(boardlist_json, Boards.list_boards()) do
      ModerationAudit.log(conn, "Updated boardlist configuration", moderator: moderator)

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
      ModerationAudit.log(
        conn,
        "Sent staff message" <>
          case Moderation.get_user(params["recipient_id"]) do
            %{username: username} -> " to #{username}"
            _ -> ""
          end,
        moderator: moderator
      )

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
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, _config} <- Settings.update_instance_config_from_json(config_json) do
      ModerationAudit.log(conn, "Updated instance configuration", moderator: moderator)

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
    with {:ok, moderator} <- ensure_admin(conn),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         {:ok, overrides} <- parse_config_json(config_json),
         {:ok, _board} <- Boards.update_board(board, %{"config_overrides" => overrides}) do
      ModerationAudit.log(conn, "Updated board configuration for /#{uri}/",
        moderator: moderator,
        board: board
      )

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
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, _theme} <- Themes.install_theme(name, Map.put(params, "mod_user_id", moderator.id)) do
      ModerationAudit.log(conn, "Installed theme #{name}", moderator: moderator)

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
    with {:ok, moderator} <- ensure_admin(conn),
         :ok <- Themes.uninstall_theme(name) do
      ModerationAudit.log(conn, "Uninstalled theme #{name}", moderator: moderator)

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
    with {:ok, moderator} <- ensure_admin(conn),
         :ok <- Themes.rebuild_theme(name) do
      ModerationAudit.log(conn, "Rebuilt theme #{name}", moderator: moderator)

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
    |> assign(:global_boardlist_groups, shell_boardlist_groups())
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

  defp append_manage_custom_javascript(conn, urls) when is_list(urls) do
    existing = conn.assigns[:custom_javascript_urls] || []
    assign(conn, :custom_javascript_urls, existing ++ urls)
  end

  def blotter(conn, _params) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      config = Settings.current_instance_config()

      render(conn, :announcement,
        moderator: moderator,
        global_message: current_global_message(),
        global_message_preview_html: current_global_message_preview_html(),
        history: global_message_history(),
        entries: Eirinchan.NewsBlotter.entries(config),
        button_label: Eirinchan.NewsBlotter.button_label(config),
        limit: max_blotter_limit(Map.get(config, :news_blotter_limit, 100)),
        blotter_preview_html: EirinchanWeb.Announcements.news_blotter_html(config),
        error: nil
      )
    else
      {:error, :unauthorized} -> redirect(conn, to: ~p"/manage/login")
    end
  end

  def update_blotter(conn, params) do
    with {:ok, moderator} <- ensure_news_editor(conn),
         {:ok, _config} <- persist_announcement_editor(params) do
      action =
        case params["editor"] do
          "global_message" -> "Updated global message"
          "news_blotter" -> "Updated news blotter"
          _ -> "Updated announcement editor"
        end

      ModerationAudit.log(conn, action, moderator: moderator)

      conn
      |> put_flash(:info, "Announcement updated.")
      |> redirect(to: ~p"/manage/announcement/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_blotter_error(conn, "Moderator access required.")

      {:error, :invalid_config} ->
        render_blotter_error(conn, "Failed to update announcement.", :unprocessable_entity)
    end
  end

  def delete_announcement(conn, _params) do
    with {:ok, moderator} <- ensure_news_editor(conn),
         {:ok, _config} <- update_global_message("") do
      ModerationAudit.log(conn, "Removed global message", moderator: moderator)

      conn
      |> put_flash(:info, "Global message removed.")
      |> redirect(to: ~p"/manage/announcement/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_blotter_error(conn, "Moderator access required.")
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
      ModerationAudit.log(conn, "Created custom page /#{slug}", moderator: moderator)

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
    with {:ok, moderator} <- ensure_news_editor(conn),
         %CustomPages.Page{} = page <- load_custom_page(id),
         {:ok, _page} <- CustomPages.update_page(page, %{slug: slug, title: title, body: body}) do
      ModerationAudit.log(conn, "Updated custom page /#{slug}", moderator: moderator)

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
    with {:ok, moderator} <- ensure_news_editor(conn),
         %CustomPages.Page{} = page <- load_custom_page(id),
         {:ok, _page} <- CustomPages.delete_page(page) do
      ModerationAudit.log(conn, "Deleted custom page /#{page.slug}", moderator: moderator)

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

      inserted_before = recent_posts_cutoff(params["last"])

      posts =
        Eirinchan.Posts.list_recent_posts(
          limit: limit,
          board_ids: board_ids,
          query: params["query"],
          ip_subnet: params["ip"],
          inserted_before: inserted_before
        )

      last_time =
        case List.last(posts) do
          %{inserted_at: %NaiveDateTime{} = inserted_at} ->
            DateTime.from_naive!(inserted_at, "Etc/UTC") |> DateTime.to_unix()

          %{inserted_at: %DateTime{} = inserted_at} ->
            DateTime.to_unix(inserted_at)

          _ -> nil
        end

      conn
      |> append_manage_custom_javascript(["/js/mod/recent-posts.js"])
      |> render(:recent_posts,
        moderator: moderator,
        boards: boards,
        entries: recent_post_entries(posts, boards, EirinchanWeb.RequestMeta.request_host(conn)),
        filters: %{
          "board" => params["board"],
          "query" => params["query"],
          "ip" => params["ip"],
          "limit" => Integer.to_string(limit)
        },
        last_time: last_time
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

  def ip_history(conn, %{"ip" => ip} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         true <- PostView.can_view_ip?(moderator),
         {:ok, decoded_ip} <- decode_ip_param(ip) do
      boards = Moderation.list_accessible_boards(moderator)
      board_ids = Enum.map(boards, & &1.id)
      posts = Moderation.list_ip_posts(decoded_ip, board_ids: board_ids)
      config = Settings.current_instance_config()
      ban_form = ip_ban_form_params(decoded_ip, nil, params)
      matching_bans = Bans.list_matching_bans(decoded_ip, board_ids: board_ids)
      edit_ban = selected_ip_ban(matching_bans, params)
      ban_form = maybe_apply_edit_ban(ban_form, edit_ban)

      render(conn, :ip_history,
        moderator: moderator,
        boards: boards,
        ip: IpCrypt.cloak_ip(decoded_ip),
        displayed_ip: EirinchanWeb.IpPresentation.display_ip(decoded_ip, moderator),
        board: nil,
        config: config,
        post_groups: ip_history_post_groups(posts, boards, EirinchanWeb.RequestMeta.request_host(conn)),
        notes: Moderation.list_ip_notes(decoded_ip, board_ids: board_ids),
        bans: matching_bans,
        logs: ip_history_logs(decoded_ip, board_ids),
        ban_form: ban_form,
        editing_ban: edit_ban
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)
    end
  end

  def board_ip_history(conn, %{"uri" => uri, "ip" => ip} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- PostView.can_view_ip?(moderator, board),
         {:ok, decoded_ip} <- decode_ip_param(ip) do
      posts = Moderation.list_ip_posts(decoded_ip, board_ids: [board.id])
      config = Settings.current_instance_config()
      matching_bans = Bans.list_matching_bans(decoded_ip, board_id: board.id)
      edit_ban = selected_ip_ban(matching_bans, params)
      ban_form = ip_ban_form_params(decoded_ip, board.uri, params) |> maybe_apply_edit_ban(edit_ban)

      render(conn, :ip_history,
        moderator: moderator,
        boards: Moderation.list_accessible_boards(moderator),
        ip: IpCrypt.cloak_ip(decoded_ip),
        displayed_ip: EirinchanWeb.IpPresentation.display_ip(decoded_ip, moderator),
        board: board,
        config: config,
        post_groups:
          ip_history_post_groups(posts, [board], EirinchanWeb.RequestMeta.request_host(conn)),
        notes: Moderation.list_ip_notes(decoded_ip, board_id: board.id),
        bans: matching_bans,
        logs: ip_history_logs(decoded_ip, [board.id], board.uri),
        ban_form: ban_form,
        editing_ban: edit_ban
      )
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Moderator IP access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)
    end
  end

  def create_ip_note(conn, %{"uri" => uri, "ip" => ip, "body" => body}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- PostView.can_view_ip?(moderator, board),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, _note} <-
           Moderation.add_ip_note(decoded_ip, %{
             body: body,
             board_id: board.id,
             mod_user_id: moderator.id
           }) do
      ModerationAudit.log(conn, "Added IP note for #{IpCrypt.cloak_ip(decoded_ip)}",
        moderator: moderator,
        board: board
      )

      conn
      |> put_flash(:info, "IP note added.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Moderator IP access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def create_global_ip_note(conn, %{"ip" => ip, "body" => body}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         true <- PostView.can_view_ip?(moderator),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, _note} <-
           Moderation.add_ip_note(decoded_ip, %{
             body: body,
             mod_user_id: moderator.id
           }) do
      ModerationAudit.log(conn, "Added a note for #{IpCrypt.cloak_ip(decoded_ip)}",
        moderator: moderator
      )

      conn
      |> put_flash(:info, "IP note added.")
      |> redirect(to: "/manage/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser#notes")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def update_ip_note(conn, %{"uri" => uri, "ip" => ip, "id" => id, "body" => body}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- PostView.can_view_ip?(moderator, board),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, note} <- load_board_note(id, board.id),
         {:ok, _note} <- Moderation.update_ip_note(note, %{body: body}) do
      ModerationAudit.log(conn, "Updated IP note for #{IpCrypt.cloak_ip(decoded_ip)}",
        moderator: moderator,
        board: board
      )

      conn
      |> put_flash(:info, "IP note updated.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Moderator IP access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "IP note not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def delete_ip_note(conn, %{"uri" => uri, "ip" => ip, "id" => id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- PostView.can_view_ip?(moderator, board),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, note} <- load_board_note(id, board.id),
         {:ok, _note} <- Moderation.delete_ip_note(note) do
      ModerationAudit.log(conn, "Deleted IP note for #{IpCrypt.cloak_ip(decoded_ip)}",
        moderator: moderator,
        board: board
      )

      conn
      |> put_flash(:info, "IP note deleted.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Moderator IP access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "IP note not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)
    end
  end

  def delete_global_ip_note(conn, %{"ip" => ip, "id" => id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         true <- PostView.can_view_ip?(moderator),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, note} <- load_global_note(id, decoded_ip, moderator),
         {:ok, _note} <- Moderation.delete_ip_note(note) do
      ModerationAudit.log(conn, "Removed a note for #{IpCrypt.cloak_ip(decoded_ip)}",
        moderator: moderator
      )

      conn
      |> put_flash(:info, "IP note deleted.")
      |> redirect(to: "/manage/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser#notes")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "IP note not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)
    end
  end

  def create_ip_ban(conn, %{"ip" => ip} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         true <- PostView.can_view_ip?(moderator),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, target_board_id} <- target_ban_board_id(moderator, params["board"]),
         {:ok, _ban} <-
           Bans.create_ban(%{
             board_id: target_board_id,
             mod_user_id: moderator.id,
             ip_subnet: normalize_ban_ip_mask(Map.get(params, "ip_mask", ip)),
             reason: params["reason"],
             length: params["length"],
             active: true
           }) do
      ModerationAudit.log(conn, "Banned #{display_ip_for_log(decoded_ip)}",
        moderator: moderator
      )

      conn
      |> put_flash(:info, "Ban created.")
      |> redirect(to: "/manage/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser#bans")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def update_ip_ban(conn, %{"ip" => ip, "id" => id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         true <- PostView.can_view_ip?(moderator),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, ban} <- load_accessible_ban(id, moderator),
         {:ok, target_board_id} <- target_ban_board_id(moderator, params["board"]),
         {:ok, _ban} <-
           Bans.update_ban(ban, %{
             board_id: target_board_id,
             ip_subnet: normalize_ban_ip_mask(Map.get(params, "ip_mask", ban.ip_subnet)),
             reason: params["reason"],
             length: params["length"],
             active: true
           }) do
      ModerationAudit.log(conn, "Updated ban ##{ban.id} for #{display_ip_for_log(decoded_ip)}",
        moderator: moderator
      )

      conn
      |> put_flash(:info, "Ban updated.")
      |> redirect(to: "/manage/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser#bans")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Ban not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def delete_ip_ban(conn, %{"ip" => ip, "id" => id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         true <- PostView.can_view_ip?(moderator),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, ban} <- load_accessible_ban(id, moderator),
         {:ok, _ban} <- Bans.update_ban(ban, %{active: false}) do
      ModerationAudit.log(conn, "Removed ban ##{ban.id} for #{display_ip_for_log(decoded_ip)}",
        moderator: moderator
      )

      conn
      |> put_flash(:info, "Ban removed.")
      |> redirect(to: "/manage/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser#bans")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Ban not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)
    end
  end

  def create_board_ip_ban(conn, %{"uri" => uri, "ip" => ip} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- PostView.can_view_ip?(moderator, board),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, target_board_id} <- target_ban_board_id(moderator, params["board"]),
         {:ok, _ban} <-
           Bans.create_ban(%{
             board_id: target_board_id,
             mod_user_id: moderator.id,
             ip_subnet: normalize_ban_ip_mask(Map.get(params, "ip_mask", ip)),
             reason: params["reason"],
             length: params["length"],
             active: true
           }) do
      ModerationAudit.log(conn, "Banned #{display_ip_for_log(decoded_ip)}",
        moderator: moderator,
        board: board
      )

      conn
      |> put_flash(:info, "Ban created.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser#bans")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Moderator IP access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def update_board_ip_ban(conn, %{"uri" => uri, "ip" => ip, "id" => id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- PostView.can_view_ip?(moderator, board),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, ban} <- load_accessible_ban(id, moderator),
         {:ok, target_board_id} <- target_ban_board_id(moderator, params["board"]),
         {:ok, _ban} <-
           Bans.update_ban(ban, %{
             board_id: target_board_id,
             ip_subnet: normalize_ban_ip_mask(Map.get(params, "ip_mask", ban.ip_subnet)),
             reason: params["reason"],
             length: params["length"],
             active: true
           }) do
      ModerationAudit.log(conn, "Updated ban ##{ban.id} for #{display_ip_for_log(decoded_ip)}",
        moderator: moderator,
        board: board
      )

      conn
      |> put_flash(:info, "Ban updated.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser#bans")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Moderator IP access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Ban not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_dashboard_error(conn, format_changeset(changeset), %{}, :unprocessable_entity)
    end
  end

  def delete_board_ip_ban(conn, %{"uri" => uri, "ip" => ip, "id" => id}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- PostView.can_view_ip?(moderator, board),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, ban} <- load_accessible_ban(id, moderator),
         {:ok, _ban} <- Bans.update_ban(ban, %{active: false}) do
      ModerationAudit.log(conn, "Removed ban ##{ban.id} for #{display_ip_for_log(decoded_ip)}",
        moderator: moderator,
        board: board
      )

      conn
      |> put_flash(:info, "Ban removed.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser#bans")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Moderator IP access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Ban not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)
    end
  end

  def delete_ip_posts(conn, %{"ip" => ip}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         true <- PostView.can_view_ip?(moderator),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, _result} <-
           Moderation.list_accessible_boards(moderator)
           |> then(
             &Eirinchan.Posts.moderate_delete_posts_by_ip(&1, decoded_ip,
               config_by_board: config_map(&1, EirinchanWeb.RequestMeta.request_host(conn))
             )
           ) do
      ModerationAudit.log(conn, "Deleted posts by IP #{IpCrypt.cloak_ip(decoded_ip)}",
        moderator: moderator
      )

      conn
      |> put_flash(:info, "Posts deleted for IP.")
      |> redirect(to: "/manage/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      false ->
        render_dashboard_error(conn, "Administrator access required.", %{}, :forbidden)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)
    end
  end

  def delete_board_ip_posts(conn, %{"uri" => uri, "ip" => ip}) do
    with {:ok, moderator} <- ensure_moderator(conn),
         {:ok, board} <- load_accessible_board(moderator, uri),
         true <- PostView.can_view_ip?(moderator, board),
         {:ok, decoded_ip} <- decode_ip_param(ip),
         {:ok, _result} <-
           Eirinchan.Posts.moderate_delete_posts_by_ip(board, decoded_ip,
             config: effective_board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      ModerationAudit.log(conn, "Deleted board posts by IP #{IpCrypt.cloak_ip(decoded_ip)}",
        moderator: moderator,
        board: board
      )

      conn
      |> put_flash(:info, "Posts deleted for IP.")
      |> redirect(to: "/manage/boards/#{board.uri}/ip/#{IpCrypt.cloak_ip(decoded_ip)}/browser")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        render_dashboard_error(conn, "Board access required.", %{}, :forbidden)

      false ->
        render_dashboard_error(conn, "Moderator IP access required.", %{}, :forbidden)

      {:error, :not_found} ->
        render_dashboard_error(conn, "Board not found.", %{}, :not_found)

      {:error, :invalid_ip} ->
        render_dashboard_error(conn, "Invalid IP address.", %{}, :bad_request)
    end
  end

  def dismiss_report(conn, %{"id" => id} = params) do
    with {:ok, moderator} <- ensure_moderator(conn),
         report when not is_nil(report) <- Reports.get_report(id),
         :ok <- authorize_report(moderator, report),
         {:ok, _report} <- Reports.dismiss_report(report.board, id) do
      ModerationAudit.log(conn, "Dismissed report ##{report.id}",
        moderator: moderator,
        board: report.board
      )

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
      ModerationAudit.log(conn, "Dismissed reports for post No. #{post_id}",
        moderator: moderator,
        board: report.board
      )

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
      ModerationAudit.log(conn, "Dismissed reports for IP #{display_ip_for_log(report.ip)}",
        moderator: moderator,
        board: report.board
      )

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
        show_ip: PostView.can_view_ip?(moderator, board),
        error: nil,
        params: %{
          "ip" =>
            if(PostView.can_view_ip?(moderator, board),
              do: Map.get(params, "ip", post.ip_subnet || ""),
              else: ""
            ),
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
      ModerationAudit.log(
        conn,
        "Banned #{display_ip_for_log(Map.get(params, "ip", post.ip_subnet))} for post No. #{PostView.public_post_id(post)}" <>
          if(Map.get(params, "delete") in ["1", "true", "on"], do: " and deleted the post", else: ""),
        moderator: moderator,
        board: board
      )

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
      ModerationAudit.log(conn, "Edited post No. #{PostView.public_post_id(post)}",
        moderator: moderator,
        board: board
      )

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
      ModerationAudit.log(
        conn,
        "Moved thread No. #{PostView.public_post_id(moved_thread)} from /#{source_board.uri}/ to /#{target_board.uri}/",
        moderator: moderator,
        board: target_board
      )

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
      ModerationAudit.log(
        conn,
        "Moved reply No. #{PostView.public_post_id(moved_reply)} from /#{source_board.uri}/ to /#{target_board.uri}/ thread No. #{target_thread_id}",
        moderator: moderator,
        board: target_board
      )

      conn
      |> put_flash(:info, "Reply moved.")
      |> redirect(
        to:
          Eirinchan.ThreadPaths.thread_path(
            target_board,
            %Eirinchan.Posts.Post{
              id: moved_reply.thread_id,
              public_id: String.to_integer(target_thread_id),
              slug: nil
            },
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
      ModerationAudit.log(conn, "Resolved ban appeal ##{appeal.id}",
        moderator: moderator,
        board: appeal.ban && appeal.ban.board
      )

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
    with {:ok, moderator} <- ensure_admin(conn),
         {:ok, board} <- Boards.create_board(Map.take(params, ["uri", "title", "subtitle"])) do
      ModerationAudit.log(conn, "Created board /#{board.uri}/", moderator: moderator, board: board)

      conn
      |> put_flash(:info, "Board created.")
      |> redirect(to: "/#{board.uri}")
    else
      {:error, :unauthorized} ->
        redirect(conn, to: ~p"/manage/login")

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> render(
          :dashboard,
          dashboard_assigns(conn.assigns[:current_moderator], %{
            error: "Administrator access required.",
            params: Map.take(stringify(params), ["uri", "title", "subtitle"])
          })
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(
          :dashboard,
          dashboard_assigns(conn.assigns.current_moderator, %{
            error: format_changeset(changeset),
            params: Map.take(stringify(params), ["uri", "title", "subtitle"])
          })
        )
    end
  end

  def update_board(conn, %{"uri" => uri} = params) do
    with {:ok, moderator} <- ensure_admin(conn),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         {:ok, _board} <- Boards.update_board(board, Map.take(params, ["title", "subtitle"])) do
      ModerationAudit.log(conn, "Updated board /#{uri}/", moderator: moderator, board: board)

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
    with {:ok, moderator} <- ensure_admin(conn),
         board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         {:ok, _board} <- Boards.delete_board(board) do
      ModerationAudit.log(conn, "Deleted board /#{uri}/", moderator: moderator, board_uri: uri)

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

      ModerationAudit.log(conn, "Rebuilt board /#{uri}/", moderator: moderator, board: board)

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
    ModerationAudit.log(conn, "Logged out")

    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> redirect(to: ~p"/manage/login")
  end

  defp establish_moderator_session(conn, moderator, remote_ip) do
    secure_token = ManageSecurity.generate_token()
    session_fingerprint = ManageSecurity.session_fingerprint(moderator)
    login_ip = ManageSecurity.ip_fingerprint(remote_ip)
    issued_at = ManageSecurity.current_session_issued_at()

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:moderator_user_id, moderator.id)
    |> put_session(:secure_manage_token, secure_token)
    |> put_session(:moderator_session_fingerprint, session_fingerprint)
    |> put_session(:moderator_login_ip, login_ip)
    |> put_session(:moderator_session_issued_at, issued_at)
    |> put_session(:moderator_session_last_seen_at, issued_at)
  end

  defp handle_failed_browser_login(conn, username, remote_ip, config) do
    case ManageLoginThrottle.record_failure(username, remote_ip, config) do
      {:error, _retry_after} ->
        conn
        |> put_status(:too_many_requests)
        |> render(:login, error: "Too many login attempts. Try again later.", username: username)

      :ok ->
        conn
        |> put_status(:unauthorized)
        |> render(:login, error: "Invalid credentials.", username: username)
    end
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

  defp ensure_noticeboard_poster(conn) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      if moderator.role in ["admin", "mod"], do: {:ok, moderator}, else: {:error, :forbidden}
    end
  end

  defp ensure_news_editor(conn) do
    with {:ok, moderator} <- ensure_moderator(conn) do
      if moderator.role in ["admin", "mod"], do: {:ok, moderator}, else: {:error, :forbidden}
    end
  end

  defp stringify(params), do: Enum.into(params, %{}, fn {k, v} -> {to_string(k), v} end)

  defp normalize_filter(nil), do: nil

  defp normalize_filter(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp positive_integer_param(value, default) do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp display_ip_for_log(nil), do: "hidden IP"
  defp display_ip_for_log(ip), do: IpCrypt.cloak_ip(ip)

  defp render_dashboard_error(conn, message, params, status \\ :forbidden) do
    conn
    |> put_status(status)
    |> render(
      :dashboard,
      dashboard_assigns(conn.assigns[:current_moderator], %{
        error: message,
        params: Map.take(stringify(params), ["uri", "title", "subtitle"])
      })
    )
  end

  defp render_noticeboard_error(conn, moderator, message, page, status) do
    config = Settings.current_instance_config()
    per_page = positive_integer_param(Map.get(config, :noticeboard_page, 50), Noticeboard.page_size_default())
    entries = Noticeboard.list_entries(page: page, per_page: per_page)
    total_entries = Noticeboard.count_entries()

    conn
    |> put_status(status)
    |> render(:noticeboard,
      moderator: moderator,
      noticeboard: entries,
      count: total_entries,
      page: page,
      page_count: Noticeboard.page_count(total_entries, per_page),
      error: message,
      can_post_noticeboard?: moderator && moderator.role in ["admin", "mod"],
      can_delete_noticeboard?: moderator && moderator.role == "admin"
    )
  end

  defp render_blotter_error(conn, message, status \\ :forbidden) do
    config = Settings.current_instance_config()

    conn
    |> put_status(status)
    |> render(:announcement,
      moderator: conn.assigns[:current_moderator],
      global_message: current_global_message(),
      global_message_preview_html: current_global_message_preview_html(),
      history: global_message_history(),
      entries: Eirinchan.NewsBlotter.entries(config),
      button_label: Eirinchan.NewsBlotter.button_label(config),
      limit: max_blotter_limit(Map.get(config, :news_blotter_limit, 100)),
      blotter_preview_html: EirinchanWeb.Announcements.news_blotter_html(config),
      error: message
    )
  end

  defp persist_announcement_editor(%{"editor" => "global_message", "body" => body}) do
    update_global_message(body)
  end

  defp persist_announcement_editor(%{"editor" => "news_blotter"} = params) do
    config = Settings.current_instance_config()
    entries = parse_blotter_entries(params)
    limit = max_blotter_limit(Map.get(config, :news_blotter_limit, 100))
    button_label =
      params
      |> Map.get("button_label", Eirinchan.NewsBlotter.button_label(config))
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "View News - {date}"
        value -> value
      end

    updated =
      config
      |> Map.put(:news_blotter_entries, entries)
      |> Map.put(:news_blotter_limit, limit)
      |> Map.put(:news_blotter_button_label, button_label)

    case Settings.persist_instance_config(updated) do
      :ok -> {:ok, updated}
      {:error, _reason} -> {:error, :invalid_config}
    end
  end

  defp persist_announcement_editor(_params), do: {:error, :invalid_config}

  defp current_global_message do
    case Settings.current_instance_config() |> Map.get(:global_message) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp dashboard_assigns(moderator, overrides \\ %{}) do
    config = Settings.current_instance_config()

    Map.merge(
      %{
        moderator: moderator,
        boards: Moderation.list_accessible_boards(moderator),
        report_count: accessible_report_count(moderator),
        appeal_count: accessible_appeal_count(moderator),
        feedback_count: Feedback.unread_count(),
        unread_messages: Moderation.count_unread_messages(moderator),
        noticeboard_entries:
          Noticeboard.dashboard_entries(
            limit:
              positive_integer_param(
                Map.get(config, :noticeboard_dashboard, 5),
                Noticeboard.dashboard_size_default()
              )
          ),
        custom_pages: CustomPages.list_pages(),
        error: nil,
        params: %{"uri" => nil, "title" => nil, "subtitle" => nil}
      },
      overrides
    )
  end

  defp verify_noticeboard_delete_token(token) do
    case Phoenix.Token.verify(EirinchanWeb.Endpoint, "noticeboard-delete", token, max_age: 60 * 60 * 24 * 30) do
      {:ok, value} ->
        case Integer.parse(value) do
          {id, ""} -> {:ok, id}
          _ -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp current_global_message_preview_html do
    config = Settings.current_instance_config()

    config
    |> EirinchanWeb.Announcements.global_message(board_ids: preview_board_ids())
    |> case do
      nil -> ""
      message -> EirinchanWeb.Announcements.render_message_fragment(message)
    end
  end

  defp preview_board_ids do
    Boards.list_boards()
    |> Enum.map(& &1.id)
  end

  defp global_message_history do
    Settings.current_instance_config()
    |> Map.get(:global_message_history, [])
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
  end

  defp update_global_message(body) do
    config = Settings.current_instance_config()
    previous = current_global_message()
    body = String.trim(body || "")

    history =
      [previous | global_message_history()]
      |> Enum.filter(&(&1 != "" and &1 != body))
      |> Enum.uniq()
      |> Enum.take(20)

    updated =
      config
      |> Map.put(:global_message, if(body == "", do: false, else: body))
      |> Map.put(:global_message_history, history)

    case Settings.persist_instance_config(updated) do
      :ok -> {:ok, updated}
      {:error, _reason} -> {:error, :invalid_config}
    end
  end

  defp parse_blotter_entries(%{"entries" => entries}) when is_map(entries) do
    entries
    |> Enum.map(fn {index, value} -> {parse_index(index), value} end)
    |> Enum.sort_by(fn {index, _value} -> index end)
    |> Enum.map(fn {_index, entry} ->
      %{
        date: entry |> Map.get("date", "") |> to_string() |> String.trim(),
        message: entry |> Map.get("message", "") |> to_string() |> String.trim()
      }
    end)
    |> Enum.take(max_blotter_limit())
    |> Enum.filter(fn %{date: date, message: message} ->
      date != "" and message != ""
    end)
  end

  defp parse_blotter_entries(_params), do: []

  defp parse_index(index) when is_integer(index), do: index

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {value, _} -> value
      _ -> 0
    end
  end

  defp parse_index(_index), do: 0

  defp max_blotter_limit(value \\ 100)

  defp max_blotter_limit(value) when is_integer(value) and value > 100, do: 100
  defp max_blotter_limit(value) when is_integer(value) and value > 0, do: value
  defp max_blotter_limit(_value), do: 100

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

  defp render_stickers_error(
         conn,
         message,
         status \\ :forbidden,
         stickers_json \\ "[]"
       ) do
    conn
    |> put_status(status)
    |> render(:stickers,
      moderator: conn.assigns[:current_moderator],
      stickers_json: stickers_json,
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

  defp decode_ip_param(ip) do
    case IpCrypt.uncloak_ip(ip) do
      nil -> {:error, :invalid_ip}
      decoded -> {:ok, decoded}
    end
  end

  defp normalize_ban_ip_mask(nil), do: nil

  defp normalize_ban_ip_mask(value) do
    trimmed = value |> to_string() |> String.trim()

    cond do
      trimmed == "" ->
        trimmed

      String.contains?(trimmed, "/") ->
        trimmed

      true ->
        IpCrypt.uncloak_ip(trimmed) || trimmed
    end
  end

  defp ban_list_filters(params, moderator) do
    %{
      "only_mine" =>
        if(
          moderator.role != "admin" and Map.get(params, "only_mine") in ["1", "true", "on"],
          do: "1",
          else: "0"
        ),
      "only_not_expired" =>
        if(Map.get(params, "only_not_expired") in ["1", "true", "on"], do: "1", else: "0"),
      "search" => Map.get(params, "search", "") |> to_string() |> String.trim()
    }
  end

  defp selected_ban_ids(params) do
    direct_ids =
      params
      |> Map.get("ban_ids", [])
      |> List.wrap()
      |> Enum.map(&normalize_ban_id/1)
      |> Enum.reject(&is_nil/1)

    keyed_ids =
      params
      |> Enum.flat_map(fn
        {"ban_" <> id, _value} -> [normalize_ban_id(id)]
        _other -> []
      end)
      |> Enum.reject(&is_nil/1)

    (direct_ids ++ keyed_ids)
    |> Enum.uniq()
  end

  defp ban_list_row(ban, boards_by_id) do
    board = Map.get(boards_by_id, ban.board_id, ban.board)
    masked_ip = EirinchanWeb.IpPresentation.display_ip(ban.ip_subnet, nil)
    exact_ip? = is_binary(ban.ip_subnet) and not String.contains?(ban.ip_subnet, "/")
    cloak = Eirinchan.IpCrypt.cloak_ip(ban.ip_subnet)

    %{
      id: ban.id,
      access: true,
      active: ban.active,
      single_addr: exact_ip?,
      masked: false,
      mask: masked_ip,
      reason: ban.reason || "",
      board: if(board, do: board.uri, else: nil),
      created: DateTime.to_unix(ban.inserted_at),
      expires: ban.expires_at && DateTime.to_unix(ban.expires_at),
      username: ban.mod_user && ban.mod_user.username,
      staff: ban.mod_user && ban.mod_user.username,
      vstaff: false,
      seen: 0,
      message: "",
      history_url:
        if(exact_ip?,
          do: "/manage/ip/#{cloak}/browser",
          else: nil
        ),
      edit_url: "/manage/bans/#{ban.id}/browser"
    }
  end

  defp accessible_ban?(board_ids, ban) do
    is_nil(ban.board_id) or ban.board_id in board_ids
  end

  defp normalize_ban_id(id) do
    case Integer.parse(to_string(id || "")) do
      {value, ""} when value > 0 -> value
      _ -> nil
    end
  end

  defp ip_history_post_groups(posts, boards, host) do
    BrowserEntries.grouped_post_entries(posts, boards, host)
  end

  defp ip_history_logs(decoded_ip, board_ids, board_uri \\ nil) do
    IpCrypt.cloak_ip(decoded_ip)
    |> ModerationLog.list_recent_entries_by_text(limit: 50, board_uri: board_uri)
    |> Enum.filter(fn entry ->
      not is_binary(entry.board_uri) or entry.board_uri == "" or board_uri != nil or
        accessible_log_board?(board_ids, entry.board_uri)
    end)
  end

  defp accessible_log_board?(board_ids, board_uri) do
    case Boards.get_board_by_uri(board_uri) do
      nil -> false
      board -> board.id in board_ids
    end
  end

  defp selected_ip_ban(bans, params) do
    selected_id = normalize_ban_id(Map.get(params, "edit_ban"))
    Enum.find(bans, &(&1.id == selected_id))
  end

  defp ip_ban_form_params(decoded_ip, default_board_uri, params) do
    %{
      "ip_mask" => Map.get(params, "ip_mask", IpCrypt.cloak_ip(decoded_ip)),
      "reason" => Map.get(params, "reason", ""),
      "length" => Map.get(params, "length", ""),
      "board" => Map.get(params, "board", default_board_uri || "*")
    }
  end

  defp maybe_apply_edit_ban(params, nil), do: params

  defp maybe_apply_edit_ban(_params, ban) do
    %{
      "ip_mask" => IpCrypt.cloak_ip(ban.ip_subnet),
      "reason" => ban.reason || "",
      "length" => "",
      "board" =>
        case ban.board do
          %{uri: uri} -> uri
          _ -> "*"
        end
    }
  end

  defp load_accessible_ban(id, moderator) do
    board_ids = moderator |> Moderation.list_accessible_boards() |> Enum.map(& &1.id)

    case Bans.get_ban(id) do
      nil -> {:error, :not_found}
      ban ->
        if accessible_ban?(board_ids, ban), do: {:ok, ban}, else: {:error, :forbidden}
    end
  end

  defp load_global_note(id, decoded_ip, moderator) do
    board_ids = moderator |> Moderation.list_accessible_boards() |> Enum.map(& &1.id)

    case Repo.get(Eirinchan.Moderation.IpNote, id) do
      %{ip_subnet: ^decoded_ip, board_id: board_id} = note ->
        if is_nil(board_id) or board_id in board_ids, do: {:ok, note}, else: {:error, :not_found}

      _ ->
        {:error, :not_found}
    end
  end

  defp config_map(boards, host) do
    BoardRuntime.config_map(boards, host)
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
    BrowserEntries.post_entries(posts, boards, host)
  end

  defp recent_posts_cutoff(nil), do: nil
  defp recent_posts_cutoff(""), do: nil

  defp recent_posts_cutoff(value) do
    case Integer.parse(to_string(value)) do
      {unix, ""} when unix > 0 ->
        case DateTime.from_unix(unix) do
          {:ok, dt} -> DateTime.to_naive(dt)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp report_entries(reports, boards, host, session_token, moderator) do
    reports = Repo.preload(reports, [:board, post: [:extra_files], thread: [:extra_files]])
    entries =
      reports
      |> Enum.map(& &1.post)
      |> BrowserEntries.post_entries(boards, host)

    Enum.zip(reports, entries)
    |> Enum.map(fn {report, entry} ->
      board = entry.board

      %{
        report: report,
        board: board,
        post: entry.post,
        thread: entry.thread,
        config: entry.config,
        displayed_ip:
          if(PostView.can_view_ip?(moderator, board),
            do: EirinchanWeb.IpPresentation.display_ip(report.ip, moderator),
            else: nil
          ),
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
        displayed_ip:
          if(PostView.can_view_ip?(moderator),
            do: EirinchanWeb.IpPresentation.display_ip(entry.ip_subnet, moderator),
            else: nil
          ),
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

  defp format_changeset(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp effective_board_config(board_record, request_host) do
    BoardRuntime.board_config(board_record, request_host)
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
      "/#{board.uri}/res/#{PostView.public_post_id(post)}.html"
    else
      "/#{board.uri}/res/#{Eirinchan.Posts.PublicIds.thread_public_id(post)}.html##{PostView.public_post_id(post)}"
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
      show_ip: PostView.can_view_ip?(moderator, board),
      error: message,
      params: %{
        "ip" =>
          if(PostView.can_view_ip?(moderator, board),
            do: Map.get(params, "ip", post.ip_subnet || ""),
            else: ""
          ),
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

  defp render_ban_browser_error(conn, id, message, params, status \\ :unprocessable_entity) do
    moderator = conn.assigns[:current_moderator]

    case load_accessible_ban(id, moderator) do
      {:ok, ban} ->
        conn
        |> put_status(status)
        |> render(:ban,
          moderator: moderator,
          ban: Repo.preload(ban, [:board, :mod_user]),
          boards: Moderation.list_accessible_boards(moderator),
          ban_form: %{
            "ip_mask" => Map.get(params, "ip_mask", IpCrypt.cloak_ip(ban.ip_subnet)),
            "reason" => Map.get(params, "reason", ban.reason || ""),
            "length" => Map.get(params, "length", ""),
            "board" => Map.get(params, "board", if(ban.board, do: ban.board.uri, else: "*"))
          },
          config: Settings.current_instance_config(),
          error: message
        )

      _ ->
        render_dashboard_error(conn, "Ban not found.", %{}, :not_found)
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

  defp shell_boardlist_groups do
    Boards.list_boards()
    |> PostView.boardlist_groups()
  end
end
