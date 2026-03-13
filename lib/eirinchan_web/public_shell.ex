defmodule EirinchanWeb.PublicShell do
  @moduledoc false

  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings

  @catalog_required_scripts [
    "js/jquery.mixitup.min.js",
    "js/catalog.js"
  ]

  def head_html(active_page, opts \\ []) do
    config =
      Keyword.get(opts, :config) || Config.compose(nil, Settings.current_instance_config(), %{})

    board_name =
      case Keyword.get(opts, :board_name) do
        nil -> "null"
        value -> ~s("#{value}")
      end

    thread_fragment =
      case Keyword.get(opts, :thread_id) do
        nil -> ""
        value -> ~s(, thread_id = "#{value}")
      end

    selected_style = Keyword.get(opts, :theme_label, "Yotsuba")
    resource_version = Keyword.get(opts, :resource_version, "")
    watcher_count = Keyword.get(opts, :watcher_count, 0)
    watcher_you_count = Keyword.get(opts, :watcher_you_count, 0)

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

    """
    <script type="text/javascript">var active_page = "#{active_page}", board_name = #{board_name}#{thread_fragment};</script><script type="text/javascript">var configRoot="/";var inMod = false;var modRoot="/"+(inMod ? "mod.php?/" : "");var resourceVersion=#{Jason.encode!(resource_version)};</script>
    <script type="text/javascript">var selectedstyle = #{Jason.encode!(selected_style)}; var styles = #{styles_json};</script>
    <script type="text/javascript">var genpassword_chars = #{Jason.encode!(Map.get(config, :genpassword_chars))}; var post_success_cookie_name = "eirinchan_posted"; var watcher_count = #{watcher_count}; var watcher_you_count = #{watcher_you_count};</script>
    """
    |> String.trim()
  end

  def javascript_urls(active_page) do
    javascript_urls(active_page, javascript_config(active_page))
  end

  def eager_javascript_urls(active_page, config)
      when active_page in [:index, :thread, :catalog] do
    javascript_urls(active_page, config)
    |> Enum.filter(
      &(&1 in [
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
    main = [config.url_javascript]

    if Map.get(config, :additional_javascript_compile, false) do
      main
    else
      scripts =
        config
        |> additional_javascript()
        |> maybe_add_catalog_scripts(active_page)
        |> Enum.map(&additional_javascript_url(config, &1))
        |> Enum.reject(&is_nil/1)

      main ++ scripts
    end
  end

  defp javascript_config(_active_page) do
    Config.compose(nil, Settings.current_instance_config(), %{})
  end

  def thread_meta_html(board, thread, config) do
    meta_subject = thread.subject || strip_html(thread.body || "")
    meta_description = strip_html(thread.body || "")
    image_url = thread_thumb_url(board, thread, config)
    thread_url = "/#{board.uri}/res/#{thread.id}.html"

    [
      ~s(<meta name="description" content="#{escape(board_heading(board) <> " - " <> meta_subject)}" />),
      ~s(<meta name="twitter:card" value="summary">),
      ~s(<meta property="og:title" content="#{escape(meta_subject)}" />),
      ~s(<meta property="og:type" content="article" />),
      ~s(<meta property="og:url" content="#{escape(thread_url)}" />)
    ]
    |> maybe_add_meta(image_url, fn url ->
      [
        ~s(<meta property="og:image" content="#{escape(url)}" />)
      ]
    end)
    |> Kernel.++([~s(<meta property="og:description" content="#{escape(meta_description)}" />)])
    |> Enum.join("")
  end

  def body_end_html do
    "<script type=\"text/javascript\">document.addEventListener('DOMContentLoaded', function () { if (typeof ready !== 'undefined') ready(); }, { once: true });</script>"
  end

  def styles_html(theme_options, selected_label) do
    options =
      theme_options
      |> List.wrap()
      |> Enum.map(fn option ->
        label = option.label || option.name || "Style"
        selected_class = if label == selected_label, do: " class=\"selected\"", else: ""
        escaped_label = Phoenix.HTML.html_escape(label) |> Phoenix.HTML.safe_to_string()
        escaped_js_label =
          label
          |> Jason.encode!()
          |> String.replace("\"", "&quot;")

        "<a href=\"javascript:void(0)\"#{selected_class} onclick=\"return changeStyle(#{escaped_js_label}, this)\">[#{escaped_label}]</a>"
      end)
      |> Enum.join("")

    "<div class=\"styles\">#{options}</div>"
  end

  def style_select_html(theme_options, selected_label) do
    options =
      theme_options
      |> List.wrap()
      |> Enum.map(fn option ->
        label = option.label || option.name || "Style"
        selected_attr = if label == selected_label, do: " selected=\"selected\"", else: ""
        escaped_label = Phoenix.HTML.html_escape(label) |> Phoenix.HTML.safe_to_string()
        escaped_value = Phoenix.HTML.html_escape(label) |> Phoenix.HTML.safe_to_string()
        "<option value=\"#{escaped_value}\"#{selected_attr}>#{escaped_label}</option>"
      end)
      |> Enum.join("")

    """
    <div id="style-select" style="display:none;float:right;margin-bottom:10px">Style: <select onchange="return changeStyle(this.value)">${options}</select></div>
    """
    |> String.replace("${options}", options)
  end

  defp additional_javascript(config) do
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
    |> Enum.filter(&safe_script_url?/1)
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

  defp additional_javascript_url(config, script) do
    cond do
      not safe_script_url?(script) ->
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
          |> safe_script_base()

        cond do
          String.ends_with?(base, "/") -> base <> script
          true -> base <> "/" <> script
        end
    end
  end

  defp safe_script_url?(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> false
      String.contains?(trimmed, ["\u0000", "\r", "\n", "\t"]) -> false
      String.starts_with?(trimmed, ["javascript:", "data:"]) -> false
      String.starts_with?(trimmed, ["http://", "https://", "//", "/"]) -> true
      String.contains?(trimmed, "..") -> false
      true -> true
    end
  end

  defp safe_script_base(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> "/"
      String.contains?(trimmed, ["\u0000", "\r", "\n", "\t"]) -> "/"
      String.starts_with?(trimmed, ["javascript:", "data:"]) -> "/"
      String.starts_with?(trimmed, ["http://", "https://", "//", "/"]) -> trimmed
      true -> "/"
    end
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
