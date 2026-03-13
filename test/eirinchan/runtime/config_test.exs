defmodule Eirinchan.Runtime.ConfigTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Boards.Board
  alias Eirinchan.Runtime.Config

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
    assert config.search_allowed_boards == nil
    assert config.search_disallowed_boards == []
    assert config.search_query_global_limit_window == 60
    assert config.search_query_global_limit_count == 0
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
  end

  test "defaults GeoIP2 database path to the bundled MMDB" do
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
             Application.app_dir(:eirinchan, "priv/geoip2/GeoLite2-Country.mmdb")
  end

  test "normalizes deprecated camelCase feature switches" do
    config =
      Config.compose(
        %{
          root: "/",
          maxBody: 99,
          maxLines: 4,
          forceImageOp: true,
          countryFlags: true,
          allowNoCountry: true,
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
    assert config.country_flags
    assert config.allow_no_country
    assert config.geoip2_database_path == "/tmp/GeoLite2-Country.mmdb"
    assert config.geoip2_lookup_bin == "/usr/bin/mmdblookup"
    assert config.user_flag
    assert config.multiple_flags
    assert config.default_user_flag == "country,sau"
    assert config.user_flags["sau"] == "Sauce"
    assert config.upload_by_url_enabled
    assert config.upload_by_url_timeout_ms == 1234
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
end
