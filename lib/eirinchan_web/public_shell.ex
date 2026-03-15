defmodule EirinchanWeb.PublicShell do
  @moduledoc false

  alias Eirinchan.Runtime.Config
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Settings

  @catalog_required_scripts [
    "js/jquery.mixitup.min.js",
    "js/catalog.js"
  ]

  @catalog_blocked_scripts MapSet.new([
                           "js/thread-stats.js",
                           "js/strftime.min.js",
                           "js/navarrows2.js",
                           "js/quick-reply.js",
                           "js/local-time.js",
                           "js/titlebar-notifications.js",
                           "js/post-hover.js",
                           "js/show-own-posts-options.js",
                           "js/archive.js",
                           "js/quick-post-controls.js",
                           "js/ruffle.js",
                           "js/expand-swf.js",
                           "js/webm-settings.js",
                           "js/expand-video.js"
                         ])

  def head_meta(active_page, opts \\ []) do
    config =
      Keyword.get(opts, :config) || Config.compose(nil, Settings.current_instance_config(), %{})

    board_name =
      case Keyword.get(opts, :board_name) do
        nil -> ""
        value -> to_string(value)
      end

    selected_style = Keyword.get(opts, :theme_label, "Yotsuba")
    resource_version = Keyword.get(opts, :resource_version, "")
    watcher_count = Keyword.get(opts, :watcher_count, 0)
    watcher_unread_count = Keyword.get(opts, :watcher_unread_count, 0)
    watcher_you_count = Keyword.get(opts, :watcher_you_count, 0)
    stylesheets_board = Keyword.get(opts, :stylesheets_board, Map.get(config, :stylesheets_board, true))
    browser_timezone = Keyword.get(opts, :browser_timezone) || Map.get(config, :viewer_timezone) || Map.get(config, :timezone, "UTC")
    browser_timezone_offset_minutes =
      Keyword.get(opts, :browser_timezone_offset_minutes) || Map.get(config, :viewer_timezone_offset_minutes) || 0

    styles_json =
      opts
      |> Keyword.get(:theme_options, [])
      |> Enum.map(fn option ->
        {
          option.label,
          %{
            name: option.name,
            uri: option.stylesheet
          }
        }
      end)
      |> Map.new()
      |> Jason.encode!()

    %{
      "eirinchan:active-page" => to_string(active_page || ""),
      "eirinchan:board-name" => to_string(board_name || ""),
      "eirinchan:thread-id" => to_string(Keyword.get(opts, :thread_id) || ""),
      "eirinchan:config-root" => "/",
      "eirinchan:resource-version" => to_string(resource_version || ""),
      "eirinchan:selected-style" => to_string(selected_style || ""),
      "eirinchan:styles" => styles_json,
      "eirinchan:stylesheets-board" => if(stylesheets_board, do: "true", else: "false"),
      "eirinchan:genpassword-chars" => to_string(Map.get(config, :genpassword_chars) || ""),
      "eirinchan:post-success-cookie-name" => "eirinchan_posted",
      "eirinchan:watcher-count" => to_string(watcher_count),
      "eirinchan:watcher-unread-count" => to_string(watcher_unread_count),
      "eirinchan:watcher-you-count" => to_string(watcher_you_count),
      "eirinchan:browser-timezone" => to_string(browser_timezone || ""),
      "eirinchan:browser-timezone-offset" => to_string(browser_timezone_offset_minutes)
    }
  end

  def javascript_urls(active_page) do
    javascript_urls(active_page, javascript_config(active_page))
  end

  def eager_javascript_urls(active_page, config)
      when active_page in [:index, :thread, :catalog] do
    javascript_urls(active_page, config)
    |> Enum.filter(
        &(&1 in [
          "/js/runtime-config.js",
          config.url_javascript,
          "/js/jquery.min.js",
          "/js/ajax.js",
          "/js/file-selector.js",
          "/js/upload-selection.js",
          "/js/save-user_flag.js"
        ])
    )
  end

  def eager_javascript_urls(_active_page, _config), do: []

  def javascript_urls(active_page, config) do
    main =
      [
        additional_javascript_url(config, "js/runtime-config.js"),
        config.url_javascript
      ]
      |> Enum.reject(&is_nil/1)

    if Map.get(config, :additional_javascript_compile, false) do
      main
    else
      scripts =
        config
        |> additional_javascript()
        |> maybe_filter_catalog_scripts(active_page)
        |> maybe_add_catalog_scripts(active_page)
        |> Enum.map(&additional_javascript_url(config, &1))
        |> Enum.reject(&is_nil/1)

      main ++ scripts
    end
  end

  defp javascript_config(_active_page) do
    Config.compose(nil, Settings.current_instance_config(), %{})
  end

  def thread_meta(board, thread, config) do
    meta_subject = thread.subject || strip_html(thread.body || "")
    meta_description = strip_html(thread.body || "")
    image_url = thread_thumb_url(board, thread, config)
    thread_url = "/#{board.uri}/res/#{PublicIds.public_id(thread)}.html"

    [
      %{name: "description", content: escape(board_heading(board) <> " - " <> meta_subject)},
      %{name: "twitter:card", value: "summary"},
      %{property: "og:title", content: escape(meta_subject)},
      %{property: "og:type", content: "article"},
      %{property: "og:url", content: escape(thread_url)}
    ]
    |> maybe_add_meta(image_url, fn url ->
      [%{property: "og:image", content: escape(url)}]
    end)
    |> Kernel.++([%{property: "og:description", content: escape(meta_description)}])
  end

  defp additional_javascript(config) do
    allow_remote_script_urls = Map.get(config, :allow_remote_script_urls, false)
    allow_user_custom_code = Map.get(config, :allow_user_custom_code, false)

    config
    |> Map.get(:additional_javascript, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reject(
      &(&1 in [
          "js/unspoiler3.js",
          "/js/unspoiler3.js",
          "js/style-select.js",
          "/js/style-select.js",
          "js/show-op.js",
          "/js/show-op.js",
          "js/show-backlinks.js",
          "/js/show-backlinks.js",
          "js/show-own-posts.js",
          "/js/show-own-posts.js",
          "js/catalog-link.js",
          "/js/catalog-link.js",
          "js/download-original.js",
          "/js/download-original.js"
        ])
    )
    |> Enum.reject(&(custom_code_script?(&1) and not allow_user_custom_code))
    |> Enum.filter(&safe_script_url?(&1, allow_remote_script_urls))
    |> ensure_hide_threads()
    |> ensure_menu_framework()
    |> Enum.uniq()
  end

  defp ensure_hide_threads(scripts) do
    needs_hide_threads? = "js/post-filter.js" in scripts
    has_hide_threads? = "js/hide-threads.js" in scripts

    cond do
      not needs_hide_threads? ->
        scripts

      has_hide_threads? ->
        scripts

      true ->
        prepend_before_first(scripts, "js/hide-threads.js", ["js/post-filter.js"])
    end
  end

  defp ensure_menu_framework(scripts) do
    needs_menu? =
      Enum.any?(scripts, &(&1 in ["js/post-filter.js", "js/fix-report-delete-submit.js"]))

    has_menu? = "js/post-menu.js" in scripts

    cond do
      not needs_menu? ->
        scripts

      has_menu? ->
        scripts

      true ->
        prepend_before_first(scripts, "js/post-menu.js", ["js/post-filter.js", "js/fix-report-delete-submit.js"])
    end
  end

  defp prepend_before_first(scripts, script, anchors) do
    index = Enum.find_index(scripts, &(&1 in anchors))

    case index do
      nil -> scripts ++ [script]
      _ -> List.insert_at(scripts, index, script)
    end
  end

  defp maybe_add_catalog_scripts(scripts, :catalog) do
    Enum.reduce(@catalog_required_scripts, scripts, fn script, acc ->
      if script in acc, do: acc, else: acc ++ [script]
    end)
  end

  defp maybe_add_catalog_scripts(scripts, _active_page), do: scripts

  defp maybe_filter_catalog_scripts(scripts, :catalog) do
    Enum.reject(scripts, &MapSet.member?(@catalog_blocked_scripts, &1))
  end

  defp maybe_filter_catalog_scripts(scripts, _active_page), do: scripts

  defp additional_javascript_url(config, script) do
    allow_remote_script_urls = Map.get(config, :allow_remote_script_urls, false)

    cond do
      not safe_script_url?(script, allow_remote_script_urls) ->
        nil

      String.starts_with?(script, "http://") or String.starts_with?(script, "https://") ->
        script

      String.starts_with?(script, "//") ->
        script

      String.starts_with?(script, "/") ->
        script

      true ->
        base =
          config
          |> Map.get(:additional_javascript_url, config.root || "/")
          |> safe_script_base(allow_remote_script_urls)

        cond do
          String.ends_with?(base, "/") -> base <> script
          true -> base <> "/" <> script
        end
    end
  end

  defp safe_script_url?(value, allow_remote_script_urls) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> false
      String.contains?(trimmed, ["\u0000", "\r", "\n", "\t"]) -> false
      String.starts_with?(trimmed, ["javascript:", "data:"]) -> false
      String.starts_with?(trimmed, ["http://", "https://", "//"]) -> allow_remote_script_urls
      String.starts_with?(trimmed, "/") -> true
      String.contains?(trimmed, "..") -> false
      true -> true
    end
  end

  defp safe_script_base(value, allow_remote_script_urls) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> "/"
      String.contains?(trimmed, ["\u0000", "\r", "\n", "\t"]) -> "/"
      String.starts_with?(trimmed, ["javascript:", "data:"]) -> "/"
      String.starts_with?(trimmed, ["http://", "https://", "//"]) and allow_remote_script_urls ->
        trimmed

      String.starts_with?(trimmed, "/") ->
        trimmed

      true -> "/"
    end
  end

  defp custom_code_script?(script) do
    script in [
      "js/options/user-js.js",
      "/js/options/user-js.js",
      "js/options/user-css.js",
      "/js/options/user-css.js"
    ]
  end

  defp board_heading(board), do: "/#{board.uri}/ - #{board.title}"

  defp thread_thumb_url(board, thread, config) do
    case thread.thumb_path do
      nil ->
        nil

      thumb ->
        if String.starts_with?(thumb, "/") do
          thumb
        else
          "/#{board.uri}/#{config.dir.thumb}#{thumb}"
        end
    end
  end

  defp maybe_add_meta(items, nil, _builder), do: items
  defp maybe_add_meta(items, value, builder), do: items ++ builder.(value)

  defp strip_html(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
