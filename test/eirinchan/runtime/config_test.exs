defmodule Eirinchan.Runtime.ConfigTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Boards.Board
  alias Eirinchan.Runtime.Config

  test "defaults global message cache refreshes to 30 seconds" do
    assert Config.default_config().global_message_refresh_seconds == 30
    assert Config.default_config().statistics_snapshots

    assert Config.compose(%{}, %{global_message_refresh_seconds: 45}).global_message_refresh_seconds ==
             45

    refute Config.compose(%{}, %{statistics_snapshots: false}).statistics_snapshots
  end

  test "normalizes configurable limits and their cross-field invariants" do
    config =
      Config.compose(nil, %{
        max_name_length: "70",
        max_subject_length: 999,
        feedback_name_max_length: 999,
        feedback_body_max_length: -1,
        thumbnail_jpeg_quality: 500,
        statistics_api_default_hours: 48,
        statistics_api_max_hours: 24,
        mod_password_min_length: 100,
        mod_password_max_length: 20,
        moderation_recent_posts_default: 200,
        moderation_recent_posts_max: 30,
        browser_identity_ttl_seconds: 100,
        browser_identity_rotation_seconds: 200,
        browser_identity_touch_interval_seconds: 300,
        queue: %{max_attempts: "9"}
      })

    assert config.max_name_length == 70
    assert config.max_subject_length == 255
    assert config.feedback_name_max_length == 255
    assert config.feedback_body_max_length == 4_000
    assert config.thumbnail_jpeg_quality == 100
    assert config.statistics_api_default_hours == 24
    assert config.mod_password_min_length == 20
    assert config.moderation_recent_posts_default == 30
    assert config.browser_identity_rotation_seconds == 100
    assert config.browser_identity_touch_interval_seconds == 100
    assert config.queue.max_attempts == 9
  end

  test "merges default, instance, and board config before applying computed defaults" do
    defaults = %{
      root: "/",
      file_post: "post.php",
      file_index: "index.html",
      file_page: "%d.html",
      file_page50: "%d+50.html",
      file_page_slug: "%d-%s.html",
      file_page50_slug: "%d-%s+50.html",
      file_mod: "mod.php",
      file_script: "main.js",
      board_path: "%s/",
      board_abbreviation: "%s/",
      board_regex: "[a-z]+",
      dir: %{img: "img/", thumb: "thumb/", res: "res/"},
      cookies: %{mod: "mod"},
      user_flag: false,
      multiple_flags: true
    }

    instance = %{
      root: "/chan/",
      dir: %{img: "images/"},
      cookies: %{mod: "__Host-mod"}
    }

    board_overrides = %{
      dir: %{thumb: "th/"},
      file_index: "home.html",
      user_flag: true,
      multiple_flags: true
    }

    board =
      Board.with_runtime_paths(
        %Board{uri: "tech", title: "Technology"},
        Config.compose(defaults, instance)
      )

    config =
      Config.compose(defaults, instance, board_overrides,
        board: board,
        request_host: "example.test"
      )

    assert config.root == "/chan/"
    assert config.file_index == "home.html"
    assert config.post_url == "/chan/post.php"
    assert config.cookies.mod == "__Host-mod"
    assert config.cookies.path == "/chan/"
    assert config.dir.img == "images/"
    assert config.dir.thumb == "th/"
    assert config.uri_thumb == "/chan/tech/th/"
    assert config.uri_img == "/chan/tech/images/"
    assert config.url_stylesheet == "/chan/stylesheets/style.css"
    assert config.url_javascript == "/chan/main.js"
    assert config.default_user_flag == "country"
    assert config.multiple_flags
    assert Regex.match?(config.referer_match, "https://example.test/chan/tech/home.html")
    assert Regex.match?(config.referer_match, "https://example.test/chan/tech")
    assert Regex.match?(config.referer_match, "https://example.test/chan/tech/catalog.html")
    assert Regex.match?(config.referer_match, "https://example.test/chan/tech/catalog/2.html")

    assert Regex.match?(
             config.referer_match,
             "https://example.test/chan/tech/res/42-thread-slug.html"
           )

    assert Regex.match?(
             config.referer_match,
             "https://example.test/chan/tech/res/42-thread-slug+50.html"
           )

    port_config =
      Config.compose(defaults, instance, board_overrides,
        board: board,
        request_host: "example.test:4001"
      )

    assert Regex.match?(port_config.referer_match, "https://example.test:4001/chan/tech")
  end

  test "disables multiple_flags unless user_flag is enabled" do
    config =
      Config.compose(
        %{
          root: "/",
          user_flag: false,
          multiple_flags: true,
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    refute config.multiple_flags
  end

  test "defaults to requiring reply bodies only when explicitly enabled" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    refute config.force_body
    assert config.force_body_op
  end

  test "normalizes comma-separated default user flags when multiple_flags is enabled" do
    config =
      Config.compose(
        %{
          root: "/",
          user_flag: true,
          multiple_flags: true,
          default_user_flag: " Country, SAU ,spc ",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.default_user_flag == "country,sau,spc"
  end

  test "derives jailed moderator cookie names with host and secure prefixes" do
    host_config =
      Config.compose(
        %{
          root: "/",
          cookies: %{mod: "mod", jail: true},
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    secure_config =
      Config.compose(
        %{
          root: "/chan/",
          cookies: %{mod: "mod", jail: true},
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert host_config.cookies.mod_cookie_name == "__Host-mod"
    assert secure_config.cookies.mod_cookie_name == "__Secure-mod"
  end

  test "normalizes captcha mode and refresh defaults" do
    config =
      Config.compose(
        %{
          root: "/",
          captcha: %{enabled: true, provider: "native", mode: " Reply "},
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.captcha.mode == "reply"
    assert config.captcha.refresh_on_error
  end

  test "provides search gating defaults" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.search_enabled
    assert config.board_search
    assert config.search_limit == 100
    assert config.search_max_query_length == 256
    assert config.search_max_terms == 12
    assert config.search_queries_per_minutes == [15, 2]
    assert config.search_queries_per_minutes_all == [50, 2]
    assert config.feedback_submissions_per_minutes == [5, 1440]
    assert config.feedback_submissions_per_minutes_all == [50, 2]
    assert config.auto_updater_poll_interval_seconds == 5
    assert config.watcher_max_threads == 500
    assert config.ip_access_auth.max_attempts == 5
    assert config.ip_access_auth.global_max_attempts == 100
    assert config.ip_access_auth.window_seconds == 300
    assert config.ip_access_auth.lockout_seconds == 900
    assert config.ip_access_auth.grant_ttl_hours == 168
    assert config.search_allowed_boards == nil
    assert config.search_disallowed_boards == []
  end

  test "defaults cycle_limit to the vichan value" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.cycle_limit == 1000
  end

  test "defaults forced_theme to false and normalizes the deprecated alias" do
    default_config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    aliased_config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{"forcedTheme" => "aya"},
        %{}
      )

    assert default_config.forced_theme == false
    assert aliased_config.forced_theme == "aya"
  end

  test "defaults footer to the vichan-style disclaimer list" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.footer == [
             "All trademarks, copyrights, comments, and images on this page are owned by and are the responsibility of their respective parties."
           ]
  end

  test "defaults news blotter button label to a date placeholder template" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.news_blotter_button_label == "View News - {date}"
  end

  test "defaults moderator noticeboard paging values to vichan parity" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.noticeboard_page == 50
    assert config.noticeboard_dashboard == 5
  end

  test "builds default vichan flood filters when filters are unset" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.flood_time == 0
    assert config.flood_time_ip == 0
    assert config.flood_time_same == 0
    assert config.max_threads_per_hour == 0
    assert config.max_links == 20
    assert config.markup_urls
    assert config.filters == []
  end

  test "provides post form row defaults" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    refute config.post_form_flags
    assert config.post_form_embed
  end

  test "provides catalog pagination defaults" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    refute config.catalog_pagination
    assert config.catalog_threads_per_page == 100
    assert config.file_catalog_page == "catalog/%d.html"
  end

  test "provides the moderation ban-list page-size default" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.ban_list_page_size == 50
  end

  test "matches vichan dnsbl defaults" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.dnsbl == [["rbl.efnetrbl.org", 4]]
    assert config.dnsbl_exceptions == ["127.0.0.1"]
    assert config.use_dnsbl == true
    assert config.ipaccess == false
    assert config.ipaccess_replies == false
    assert config.ipaccess_imagelim == 0
  end

  test "defaults GeoIP2 database path to external runtime storage" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.geoip2_database_path ==
             Application.fetch_env!(:eirinchan, :geoip2_database_path)
  end

  test "normalizes deprecated camelCase feature switches" do
    config =
      Config.compose(
        %{
          root: "/",
          maxBody: 99,
          maxLines: 4,
          forceImageOp: true,
          allowStickerOp: true,
          countryFlags: true,
          allowNoCountry: true,
          ipAccessImageLim: 4,
          geoip2DatabasePath: "/tmp/GeoLite2-Country.mmdb",
          geoip2LookupBin: "/usr/bin/mmdblookup",
          userFlag: true,
          multipleFlags: true,
          defaultUserFlag: "country, sau",
          userFlags: %{"sau" => "Sauce"},
          uploadByUrlEnabled: true,
          uploadByUrlTimeoutMs: 1234,
          captcha: %{
            "captchaProvider" => "hcaptcha",
            "captchaMode" => "reply",
            "captchaRefreshOnError" => false
          },
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.max_body == 99
    assert config.maximum_lines == 4
    assert config.force_image_op
    assert config.allow_sticker_op
    assert config.country_flags
    assert config.allow_no_country
    assert config.ipaccess_imagelim == 4
    assert config.geoip2_database_path == "/tmp/GeoLite2-Country.mmdb"
    assert config.geoip2_lookup_bin == "/usr/bin/mmdblookup"
    assert config.user_flag
    assert config.multiple_flags
    assert config.default_user_flag == "country,sau"
    assert config.user_flags["sau"] == "Sauce"
    refute config.upload_by_url_enabled
    assert config.captcha.provider == "hcaptcha"
    assert config.captcha.mode == "reply"
    refute config.captcha.refresh_on_error
  end

  test "defaults ip_nulling to false and accepts instance override" do
    default_config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    enabled_config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{"ipNulling" => true},
        %{}
      )

    refute default_config.ip_nulling
    assert enabled_config.ip_nulling
  end

  test "defaults ip_nulling_flags to zero and accepts instance override" do
    default_config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    enabled_config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{"ipNullingFlags" => 8},
        %{}
      )

    assert default_config.ip_nulling_flags == 0
    assert enabled_config.ip_nulling_flags == 8
  end

  test "provides vichan xss mitigation defaults" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{}
      )

    assert config.ie_mime_type_detection ==
             "/<(?:body|head|html|img|plaintext|pre|script|table|title|a href|channel|scriptlet)/i"

    assert config.error.mime_exploit ==
             "MIME type detection XSS exploit (IE) detected; post discarded."
  end

  test "normalizes early404 gap max alias" do
    config =
      Config.compose(
        %{
          root: "/",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        %{},
        %{"early404GapMax" => 25}
      )

    assert config.early_404_gap_max == 25
  end
end
