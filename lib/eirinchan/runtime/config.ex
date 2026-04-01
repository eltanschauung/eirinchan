defmodule Eirinchan.Runtime.Config do
  @moduledoc """
  Builds the effective runtime config with vichan-style precedence:

    * defaults
    * instance overrides
    * board overrides

  Computed defaults are applied after merging, mirroring `loadConfig()`.
  """

  alias Eirinchan.Boards.Board
  alias Eirinchan.WhaleStickers.Defaults, as: WhaleStickerDefaults

  @default_config %{
    root: "/",
    root_file: nil,
    file_post: "post.php",
    file_index: "index.html",
    file_board_index: "index.html",
    file_page: "%d.html",
    file_page50: "%d+50.html",
    file_page_slug: "%d-%s.html",
    file_page50_slug: "%d-%s+50.html",
    file_catalog: "catalog.html",
    file_catalog_page: "catalog/%d.html",
    catalog_name: "Catalog",
    archive_url: false,
    url_favicon: "favicon.ico",
    show_styles_block: true,
    stylesheets_board: true,
    default_theme: nil,
    file_mod: "mod.php",
    file_script: "main.js",
    additional_javascript: [
      "js/jquery.min.js",
      "js/inline-expanding.js",
      "js/server-thread-watcher.js",
      "js/blotter.js"
    ],
    allow_custom_javascript: true,
    allow_remote_script_urls: true,
    allow_analytics_html: false,
    allow_user_custom_code: true,
    security_headers: true,
    additional_javascript_compile: false,
    generation_strategy: "immediate",
    fileboard: false,
    board_path: "%s/",
    board_abbreviation: "%s/",
    board_regex: "[a-zA-Z0-9_]+",
    locale: "en",
    timezone: "UTC",
    anonymous: "Anonymous",
    global_message: false,
    footer: [
      "All trademarks, copyrights, comments, and images on this page are owned by and are the responsibility of their respective parties."
    ],
    news_blotter_entries: [],
    news_blotter_limit: 100,
    news_maxentries: 10,
    news_blotter_button_label: "View News - {date}",
    noticeboard_page: 50,
    noticeboard_dashboard: 5,
    whalestickers: WhaleStickerDefaults.entries(),
    banners: [],
    allow_roll: false,
    try_smarter: false,
    board_locked: false,
    strip_combining_chars: false,
    wordfilters: [],
    hidden_input_name: "hash",
    hidden_input_hash: nil,
    genpassword_chars:
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+",
    ipcrypt_key: "",
    ipcrypt_prefix: "Cloak",
    ipcrypt_immune_ip: "0.0.0.0",
    mod_lock_ip: true,
    mod_session_idle_minutes: 120,
    mod_session_max_hours: 12,
    mod_login_max_attempts: 5,
    mod_login_window_seconds: 300,
    mod_login_lockout_seconds: 900,
    ip_nulling: false,
    ip_nulling_flags: 0,
    auto_maintenance: false,
    maintenance_interval_seconds: 60 * 60 * 12,
    antispam_retention_seconds: 60 * 60 * 48,
    antispam_question: false,
    antispam_question_answer: nil,
    anti_bump_flood: false,
    max_cites: 45,
    max_cross: 45,
    flood_time: 0,
    flood_time_ip: 0,
    flood_time_same: 0,
    filters: nil,
    max_threads_per_hour: 0,
    markup_urls: true,
    max_links: 20,
    board_search: true,
    search_enabled: true,
    search_limit: 100,
    search_queries_per_minutes: [15, 2],
    search_queries_per_minutes_all: [50, 2],
    search_allowed_boards: nil,
    search_disallowed_boards: [],
    search_query_limit_window: 60,
    search_query_limit_count: 0,
    search_query_global_limit_window: 60,
    search_query_global_limit_count: 0,
    early_404: false,
    early_404_page: 3,
    early_404_replies: 5,
    early_404_staged: false,
    early_404_gap: false,
    early_404_gap_warning: 3,
    early_404_gap_deletion: 1,
    early_404_gap_max: 100,
    noko50_count: 50,
    noko50_min: 100,
    force_body: false,
    force_body_op: true,
    force_image_op: false,
    allow_sticker_op: false,
    max_body: 2_000,
    maximum_lines: 100,
    max_images: 1,
    ip_access_passwords: [],
    field_disable_name: false,
    field_disable_email: false,
    field_disable_subject: false,
    field_disable_reply_subject: true,
    field_disable_password: false,
    post_form_flags: false,
    post_form_embed: true,
    ip_access_auth: %{
      auth_path: "/auth",
      message: "Enter a password to gain access.",
      theme: "ipaccessauth"
    },
    threads_per_page: 10,
    max_pages: 10,
    catalog_pagination: false,
    catalog_threads_per_page: 100,
    threads_preview: 5,
    threads_preview_sticky: 1,
    reply_limit: 250,
    reply_hard_limit: 0,
    image_hard_limit: 0,
    spoiler_images: true,
    spoiler_image: "static/spoiler_skillet.png",
    cycle_limit: 1000,
    always_noko: false,
    poster_ids: false,
    poster_id_length: 5,
    april_fools_teams: false,
    secure_trip_salt: ")(*&^%$#@!98765432190zyxwvutsrqponmlkjihgfedcba",
    custom_tripcode: %{},
    slugify: false,
    slug_max_size: 80,
    button_newtopic: "New Thread",
    button_reply: "Reply",
    allowed_tags: false,
    proxy_save: false,
    enable_embedding: true,
    embed_width: 300,
    embed_height: 246,
    ie_mime_type_detection:
      "/<(?:body|head|html|img|plaintext|pre|script|table|title|a href|channel|scriptlet)/i",
    youtube_js_html:
      "<div class=\"video-container\" data-video=\"$2\">" <>
        "<a href=\"https://youtu.be/$2\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"file\">" <>
        "<img style=\"width:208px;height:156px;object-fit:cover;display:block;\" src=\"https://img.youtube.com/vi/$2/0.jpg\" class=\"post-image yt-embed\" loading=\"eager\" decoding=\"async\"/>" <>
        "</a></div>",
    embedding: [
      [
        "/^https?:\\/\\/(\\w+\\.)?(?:youtube\\.com\\/watch\\?v=|youtu\\.be\\/)([a-zA-Z0-9\\-_]{10,11})(&.+)?$/i",
        "<div class=\"video-container\" data-video=\"$2\">" <>
          "<a href=\"https://youtu.be/$2\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"file\">" <>
          "<img style=\"width:208px;height:156px;object-fit:cover;display:block;\" src=\"https://img.youtube.com/vi/$2/0.jpg\" class=\"post-image yt-embed\" loading=\"eager\" decoding=\"async\"/>" <>
          "</a></div>"
      ]
    ],
    dnsbl: [["rbl.efnetrbl.org", 4]],
    dnsbl_exceptions: ["127.0.0.1"],
    use_dnsbl: true,
    ipaccess: false,
    ipaccess_replies: false,
    country_flags: false,
    allow_no_country: false,
    country_flags_condensed: true,
    country_flags_condensed_css: "static/flags/flags.css",
    country_flag_data: %{},
    country_flag_fallback: %{code: "us", name: "United States"},
    country_flag_exclusions: ["eu", "ap", "o1", "a1", "a2"],
    geoip2_database_path: nil,
    geoip2_lookup_bin: "mmdblookup",
    display_flags: true,
    uri_flags: "static/flags/%s.png",
    flag_style: "width:16px;height:11px;",
    user_flag: false,
    multiple_flags: false,
    default_user_flag: "country",
    user_flags: %{},
    duplicate_file_mode: false,
    max_filesize: 10 * 1024 * 1024,
    multiimage_method: "split",
    max_filename_display_length: 30,
    thumb_ext: "",
    thumb_keep_animation_frames: 90,
    strip_exif: true,
    convert_auto_orient: true,
    thumb_width: 208,
    thumb_height: 250,
    thumb_op_width: 250,
    thumb_op_height: 250,
    max_image_width: 0,
    max_image_height: 0,
    file_thumb: nil,
    file_icons: %{
      ".webm" => "video.png",
      ".mp4" => "video.png",
      ".mp3" => "mp3.png",
      ".flac" => "flac.png",
      ".wav" => "wav.png",
      ".swf" => "file.png",
      ".pdf" => "file.png",
      "default" => "file.png"
    },
    minimum_copy_resize: false,
    upload_by_url_enabled: false,
    upload_by_url_timeout_ms: 5_000,
    upload_by_url_allow_private_hosts: false,
    allowed_ext_files_op: nil,
    allowed_ext_files: [
      ".png",
      ".jpg",
      ".jpeg",
      ".gif",
      ".bmp",
      ".webp",
      ".webm",
      ".mp4",
      ".svg",
      ".jxl",
      ".pdf",
      ".mp3",
      ".flac",
      ".wav",
      ".swf"
    ],
    webm: %{
      use_ffmpeg: true,
      allow_audio: true,
      max_length: 720,
      ffmpeg_path: "ffmpeg",
      ffprobe_path: "ffprobe"
    },
    captcha: %{
      enabled: false,
      provider: "native",
      expected_response: nil,
      verify_url: nil,
      secret: nil,
      http_timeout_ms: 5_000,
      mode: "always",
      refresh_on_error: true,
      challenge: nil
    },
    api: %{enabled: false},
    lock: %{enabled: "none", path: "tmp/locks"},
    queue: %{enabled: "db", path: "tmp/queue/build"},
    purge: [],
    purge_timeout_seconds: 3,
    cookies: %{
      mod: "mod",
      js: "serv",
      jail: true,
      expire: 60 * 60 * 24 * 7,
      httponly: true
    },
    dir: %{
      img: "src/",
      thumb: "thumb/",
      res: "res/"
    },
    log_system: %{
      type: "error_log",
      name: "tinyboard",
      syslog_stderr: false,
      file_path: "/var/log/vichan.log",
      format: "logfmt"
    },
    error: %{
      bot: "Invalid post action.",
      referer: "Invalid referer.",
      tooshort_body: "Body too short.",
      toolong_body: "The body was too long.",
      toomanylines: "Your post contains too many lines!",
      invalid_flag: "Invalid flag selection.",
      antispam: "Spam filter triggered.",
      too_many_threads:
        "The hourly thread limit has been reached. Please post in an existing thread.",
      dnsbl: "Your IP address is listed in %s.",
      toomanylinks: "Too many links; flood detected.",
      toomanycites: "Too many cites; post discarded.",
      toomanycross: "Too many cross-board links; post discarded.",
      captcha: "Captcha validation failed.",
      invalid_embed: "Couldn't make sense of the URL of the video you tried to embed.",
      banned: "You are banned.",
      locked: "Thread locked. You may not reply at this time.",
      reply_hard_limit: "Thread has reached its maximum reply limit.",
      image_hard_limit: "Thread has reached its maximum image limit.",
      board_locked: "Board is locked.",
      password: "Incorrect password.",
      duplicate_file: "Duplicate file.",
      file_required: "File required.",
      filetype: "File type not allowed.",
      mime_exploit: "MIME type detection XSS exploit (IE) detected; post discarded.",
      invalid_image: "Invalid image.",
      image_too_large: "Image dimensions too large.",
      file_too_large: "File too large.",
      upload_failed: "Upload failed."
    }
  }

  @type t :: map()

  @deprecated_switch_aliases %{
    "maxLines" => :maximum_lines,
    "maxBody" => :max_body,
    "forceBody" => :force_body,
    "forceBodyOp" => :force_body_op,
    "forceImageOp" => :force_image_op,
    "allowStickerOp" => :allow_sticker_op,
    "countryFlags" => :country_flags,
    "allowNoCountry" => :allow_no_country,
    "countryFlagsCondensed" => :country_flags_condensed,
    "countryFlagsCondensedCss" => :country_flags_condensed_css,
    "countryFlagData" => :country_flag_data,
    "countryFlagFallback" => :country_flag_fallback,
    "countryFlagExclusions" => :country_flag_exclusions,
    "geoip2DatabasePath" => :geoip2_database_path,
    "geoip2LookupBin" => :geoip2_lookup_bin,
    "displayFlags" => :display_flags,
    "uriFlags" => :uri_flags,
    "flagStyle" => :flag_style,
    "userFlag" => :user_flag,
    "userFlags" => :user_flags,
    "defaultUserFlag" => :default_user_flag,
    "multipleFlags" => :multiple_flags,
    "fieldDisableName" => :field_disable_name,
    "fieldDisableEmail" => :field_disable_email,
    "fieldDisableSubject" => :field_disable_subject,
    "fieldDisableReplySubject" => :field_disable_reply_subject,
    "fieldDisablePassword" => :field_disable_password,
    "postFormFlags" => :post_form_flags,
    "postFormEmbed" => :post_form_embed,
    "stylesheetsBoard" => :stylesheets_board,
    "defaultTheme" => :default_theme,
    "ipAccess" => :ipaccess,
    "ipAccessReplies" => :ipaccess_replies,
    "ipNulling" => :ip_nulling,
    "ipNullingFlags" => :ip_nulling_flags,
    "antiBumpFlood" => :anti_bump_flood,
    "maxCites" => :max_cites,
    "maxCross" => :max_cross,
    "floodTime" => :flood_time,
    "floodTimeIp" => :flood_time_ip,
    "floodTimeSame" => :flood_time_same,
    "filters" => :filters,
    "maxThreadsPerHour" => :max_threads_per_hour,
    "markupUrls" => :markup_urls,
    "maxLinks" => :max_links,
    "boardSearch" => :board_search,
    "searchEnabled" => :search_enabled,
    "searchLimit" => :search_limit,
    "searchQueriesPerMinutes" => :search_queries_per_minutes,
    "searchQueriesPerMinutesAll" => :search_queries_per_minutes_all,
    "searchAllowedBoards" => :search_allowed_boards,
    "searchDisallowedBoards" => :search_disallowed_boards,
    "early404" => :early_404,
    "early404Page" => :early_404_page,
    "early404Replies" => :early_404_replies,
    "early404Staged" => :early_404_staged,
    "early404Gap" => :early_404_gap,
    "early404GapWarning" => :early_404_gap_warning,
    "early404GapDeletion" => :early_404_gap_deletion,
    "early404GapMax" => :early_404_gap_max,
    "uploadByUrlEnabled" => :upload_by_url_enabled,
    "uploadByUrlTimeoutMs" => :upload_by_url_timeout_ms,
    "generationStrategy" => :generation_strategy,
    "replyHardLimit" => :reply_hard_limit,
    "imageHardLimit" => :image_hard_limit,
    "maxFilesize" => :max_filesize,
    "thumbWidth" => :thumb_width,
    "thumbHeight" => :thumb_height,
    "thumbOpWidth" => :thumb_op_width,
    "thumbOpHeight" => :thumb_op_height,
    "stripExif" => :strip_exif,
    "convertAutoOrient" => :convert_auto_orient,
    "posterIds" => :poster_ids,
    "posterIdLength" => :poster_id_length,
    "aprilFoolsTeams" => :april_fools_teams,
    "secureTripSalt" => :secure_trip_salt,
    "customTripcode" => :custom_tripcode
  }

  @deprecated_nested_aliases %{
    captcha: %{
      "captchaProvider" => :provider,
      "captchaMode" => :mode,
      "captchaRefreshOnError" => :refresh_on_error,
      "captchaVerifyUrl" => :verify_url,
      "captchaSecret" => :secret,
      "captchaHttpTimeoutMs" => :http_timeout_ms
    }
  }

  @spec default_config() :: t()
  def default_config, do: @default_config

  @spec compose(map() | nil, map(), map(), keyword()) :: t()
  def compose(defaults \\ nil, instance_overrides \\ %{}, board_overrides \\ %{}, opts \\ []) do
    normalized_defaults = normalize_override_keys(defaults || %{})
    normalized_instance = normalize_override_keys(instance_overrides || %{})
    normalized_board = normalize_override_keys(board_overrides || %{})
    base_defaults = deep_merge(default_config(), normalized_defaults)
    board = Keyword.get(opts, :board)
    request_host = Keyword.get(opts, :request_host)

    base_defaults
    |> deep_merge(normalized_instance)
    |> deep_merge(normalized_board)
    |> apply_computed_defaults(board, request_host)
  end

  @spec deep_merge(map(), map()) :: map()
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  @spec normalize_override_keys(map()) :: map()
  def normalize_override_keys(overrides) when is_map(overrides) do
    Enum.into(overrides, %{}, fn
      {key, value} when is_binary(key) ->
        normalized_key = normalize_override_key(key)
        {normalized_key, normalize_override_value(normalized_key, value)}

      {key, value} when is_atom(key) ->
        normalized_key = normalize_override_key(key)
        {normalized_key, normalize_override_value(normalized_key, value)}

      {key, value} ->
        {key, normalize_override_value(key, value)}
    end)
  end

  defp apply_computed_defaults(config, board, request_host) do
    config
    |> Map.put_new(:global_message, false)
    |> Map.put_new(:news_blotter_entries, [])
    |> Map.put_new(:news_blotter_limit, 100)
    |> Map.put_new(:noticeboard_page, 50)
    |> Map.put_new(:noticeboard_dashboard, 5)
    |> ensure_default_filters()
    |> Map.put_new(:post_url, path_join(config.root, config.file_post))
    |> ensure_geoip_defaults()
    |> put_nested_new([:cookies, :path], config.root)
    |> normalize_cookie_names()
    |> Map.put_new(:referer_match, build_referer_match(config, request_host))
    |> ensure_web_assets()
    |> ensure_static_assets()
    |> apply_board_paths(board)
    |> normalize_flags()
  end

  defp ensure_web_assets(config) do
    config
    |> Map.put_new(:uri_stylesheets, path_join(config.root, "stylesheets/"))
    |> then(fn updated ->
      updated
      |> Map.put_new(:url_stylesheet, path_join(updated.uri_stylesheets, "style.css"))
      |> Map.put_new(:url_javascript, path_join(updated.root, updated.file_script))
      |> Map.put_new(:additional_javascript_url, updated.root)
      |> Map.put_new(:uri_flags, path_join(updated.root, "static/flags/%s.png"))
    end)
  end

  defp ensure_geoip_defaults(config) do
    case Map.get(config, :geoip2_database_path) do
      path when is_binary(path) ->
        if String.trim(path) == "" do
          Map.put(config, :geoip2_database_path, default_geoip2_database_path())
        else
          config
        end

      _ ->
        Map.put(config, :geoip2_database_path, default_geoip2_database_path())
    end
  end

  defp ensure_default_filters(%{filters: nil} = config) do
    Map.put(config, :filters, default_filters(config))
  end

  defp ensure_default_filters(config), do: config

  defp default_filters(config) do
    [
      %{
        condition: %{
          "flood-match" => ["ip"],
          "flood-time" => config.flood_time
        },
        action: "reject",
        reason: "antispam",
        message: config.error.antispam
      },
      %{
        condition: %{
          "flood-match" => ["ip", "body"],
          "flood-time" => config.flood_time_ip,
          "!body" => "/^$/"
        },
        action: "reject",
        reason: "antispam",
        message: config.error.antispam
      },
      %{
        condition: %{
          "flood-match" => ["body"],
          "flood-time" => config.flood_time_same
        },
        action: "reject",
        reason: "antispam",
        message: config.error.antispam
      },
      %{
        condition: %{"custom" => "check_thread_limit"},
        action: "reject",
        reason: "too_many_threads",
        message: config.error.too_many_threads
      }
    ]
    |> Enum.reject(fn filter ->
      condition = filter[:condition] || filter["condition"] || %{}
      custom = Map.get(condition, "custom", Map.get(condition, :custom))

      cond do
        custom == "check_thread_limit" ->
          config.max_threads_per_hour in [nil, 0]

        true ->
          Map.get(condition, "flood-time", Map.get(condition, :flood_time)) in [nil, 0]
      end
    end)
  end

  defp default_geoip2_database_path do
    Application.app_dir(:eirinchan, "priv/geoip2/GeoLite2-Country.mmdb")
  end

  defp ensure_static_assets(config) do
    static_dir = Map.get(config.dir, :static, path_join(config.root, "static/"))
    dir = Map.put(config.dir, :static, static_dir)

    config
    |> Map.put(:dir, dir)
    |> Map.put_new(:image_blank, path_join(static_dir, "blank.gif"))
    |> Map.put_new(:image_sticky, path_join(static_dir, "sticky.gif"))
    |> Map.put_new(:image_locked, path_join(static_dir, "locked.gif"))
    |> Map.put_new(:image_bumplocked, path_join(static_dir, "sage.gif"))
    |> Map.put_new(:image_deleted, path_join(static_dir, "deleted.png"))
    |> Map.put_new(:image_cyclical, path_join(static_dir, "cycle.png"))
    |> Map.put_new(:image_gap, path_join(static_dir, "gap.png"))
  end

  defp apply_board_paths(config, nil), do: config

  defp apply_board_paths(config, %Board{} = board) do
    config
    |> Map.put_new(:uri_thumb, board_asset_path(config, board.dir, config.dir.thumb))
    |> Map.put_new(:uri_img, board_asset_path(config, board.dir, config.dir.img))
  end

  defp normalize_override_key(key) when is_binary(key) do
    Map.get(@deprecated_switch_aliases, key) ||
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> key
      end
  end

  defp normalize_override_key(key) when is_atom(key) do
    Map.get(@deprecated_switch_aliases, Atom.to_string(key), key)
  end

  defp normalize_override_value(_key, %{__struct__: _} = value), do: value

  defp normalize_override_value(key, value) when is_map(value) do
    nested_aliases = Map.get(@deprecated_nested_aliases, key, %{})

    value
    |> Enum.into(%{}, fn
      {nested_key, nested_value} when is_binary(nested_key) ->
        normalized_nested_key =
          Map.get(nested_aliases, nested_key) ||
            try do
              String.to_existing_atom(nested_key)
            rescue
              ArgumentError -> nested_key
            end

        {normalized_nested_key, normalize_override_value(normalized_nested_key, nested_value)}

      {nested_key, nested_value} when is_atom(nested_key) ->
        {nested_key, normalize_override_value(nested_key, nested_value)}

      {nested_key, nested_value} ->
        {nested_key, normalize_override_value(nested_key, nested_value)}
    end)
  end

  defp normalize_override_value(_key, value) when is_list(value),
    do: Enum.map(value, &normalize_override_value(nil, &1))

  defp normalize_override_value(_key, value), do: value

  defp normalize_flags(config) do
    config =
      config
      |> Map.put_new(:user_flag, false)
      |> Map.put_new(:multiple_flags, false)
      |> Map.put_new(:default_user_flag, "country")
      |> Map.put_new(:user_flags, %{})
      |> normalize_captcha()

    normalized_default =
      normalize_default_user_flag(config.default_user_flag, config.multiple_flags)

    if config.user_flag do
      %{config | default_user_flag: normalized_default}
    else
      %{config | default_user_flag: normalized_default, multiple_flags: false}
    end
  end

  defp normalize_captcha(config) do
    captcha =
      config
      |> Map.get(:captcha, %{})
      |> Map.put_new(:enabled, false)
      |> Map.put_new(:provider, "native")
      |> Map.put_new(:expected_response, nil)
      |> Map.put_new(:verify_url, nil)
      |> Map.put_new(:secret, nil)
      |> Map.put_new(:http_timeout_ms, 5_000)
      |> Map.put_new(:mode, "always")
      |> Map.put_new(:refresh_on_error, true)
      |> Map.put_new(:challenge, nil)
      |> Map.update!(:mode, fn mode ->
        mode
        |> to_string()
        |> String.trim()
        |> String.downcase()
        |> case do
          "op" -> "op"
          "reply" -> "reply"
          "none" -> "none"
          _ -> "always"
        end
      end)

    Map.put(config, :captcha, captcha)
  end

  defp normalize_default_user_flag(default_user_flag, true) do
    default_user_flag
    |> to_string()
    |> String.split(",", trim: false)
    |> Enum.map(&(String.trim(&1) |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(",")
    |> case do
      "" -> "country"
      value -> value
    end
  end

  defp normalize_default_user_flag(default_user_flag, false) do
    default_user_flag
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> "country"
      value -> value
    end
  end

  defp normalize_cookie_names(config) do
    cookie_name =
      case {get_in(config, [:cookies, :jail]), get_in(config, [:cookies, :mod]), config.root} do
        {true, name, "/"} -> "__Host-" <> String.trim_leading(to_string(name), "__Host-")
        {true, name, _root} -> "__Secure-" <> String.trim_leading(to_string(name), "__Secure-")
        {_jail, name, _root} -> to_string(name)
      end

    put_nested_new(config, [:cookies, :mod_cookie_name], cookie_name)
  end

  defp put_nested_new(config, [key], value), do: Map.put_new(config, key, value)

  defp put_nested_new(config, [key | rest], value) do
    nested =
      config
      |> Map.get(key, %{})
      |> put_nested_new(rest, value)

    Map.put(config, key, nested)
  end

  defp build_referer_match(_config, nil), do: ~r//

  defp build_referer_match(config, request_host) do
    prefix =
      if String.match?(config.root, ~r/^https?:\/\//) do
        ""
      else
        "https?:\\/\\/#{Regex.escape(request_host)}"
      end

    board_path = interpolate_path_pattern(config.board_path, config.board_regex)
    board_index_path = interpolate_board_index_pattern(config.board_path, config.board_regex)
    res_path = Regex.escape(config.dir.res)
    file_index = Regex.escape(config.file_index)
    file_page = interpolate_integer_pattern(config.file_page)
    file_page50 = interpolate_integer_pattern(config.file_page50)
    file_page_slug = interpolate_thread_slug_pattern(config.file_page_slug)
    file_page50_slug = interpolate_thread_slug_pattern(config.file_page50_slug)
    file_catalog = Regex.escape(config.file_catalog)
    file_catalog_page = interpolate_integer_pattern(config.file_catalog_page)
    mod_path = Regex.escape(config.file_mod)

    Regex.compile!(
      "^" <>
        prefix <>
        Regex.escape(config.root) <>
        "(" <>
        board_index_path <>
        "(#{file_index}|#{file_page}|#{file_catalog}|#{file_catalog_page})?" <>
        "|" <>
        board_path <>
        res_path <>
        "(#{file_page}|#{file_page50}|#{file_page_slug}|#{file_page50_slug})" <>
        "|" <>
        mod_path <>
        "\\?/.*" <>
        ")([#?](.+)?)?$",
      "ui"
    )
  end

  defp interpolate_board_index_pattern(template, board_regex) do
    template
    |> interpolate_path_pattern(board_regex)
    |> case do
      "" ->
        ""

      pattern ->
        if String.ends_with?(pattern, "/") do
          String.trim_trailing(pattern, "/") <> "/?"
        else
          pattern
        end
    end
  end

  defp interpolate_path_pattern(template, board_regex) do
    template
    |> Regex.escape()
    |> String.replace("%s", board_regex)
  end

  defp interpolate_integer_pattern(template) do
    template
    |> Regex.escape()
    |> String.replace("%d", "\\d+")
  end

  defp interpolate_thread_slug_pattern(template) do
    template
    |> Regex.escape()
    |> String.replace("%d", "\\d+")
    |> String.replace("%s", "[a-z0-9-]+")
  end

  defp board_asset_path(config, board_dir, suffix) do
    path_join(config.root, board_dir, suffix)
  end

  defp path_join(left, right), do: path_join(left, nil, right)

  defp path_join(left, middle, right) when is_binary(left) do
    if String.starts_with?(left, ["http://", "https://"]) do
      uri = URI.parse(left)
      path = path_join(uri.path || "/", middle, right)
      %{uri | path: path} |> URI.to_string()
    else
      join_relative_path(left, middle, right)
    end
  end

  defp path_join(left, middle, right) do
    join_relative_path(left, middle, right)
  end

  defp join_relative_path(left, middle, right) do
    preserve_trailing_slash? =
      [right, middle, left]
      |> Enum.reject(&is_nil/1)
      |> List.first()
      |> to_string()
      |> String.ends_with?("/")

    [left, middle, right]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&trim_path_segment/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> "/"
      segments -> join_segments(segments, left, preserve_trailing_slash?)
    end
  end

  defp trim_path_segment(segment) do
    segment
    |> to_string()
    |> String.trim()
    |> String.trim("/")
  end

  defp join_segments(segments, original_left, preserve_trailing_slash?) do
    joined = Enum.join(segments, "/")

    base =
      cond do
        String.starts_with?(to_string(original_left), "/") ->
          "/" <> joined

        true ->
          joined
      end

    if preserve_trailing_slash?, do: base <> "/", else: base
  end
end
