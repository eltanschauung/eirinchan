defmodule EirinchanWeb.PublicShell do
  @moduledoc false

  @base_javascript_urls [
    "/main.js",
    "/js/jquery.min.js",
    "/js/inline-expanding.js",
    "/js/jquery.min.js",
    "/js/youtube.js",
    "/js/save-user_flag.js",
    "/js/thread-stats.js",
    "/js/strftime.min.js",
    "/js/ajax.js",
    "/js/navarrows2.js",
    "/js/file-selector.js",
    "/js/upload-selection.js",
    "/js/expand.js",
    "/js/options.js",
    "/js/style-select.js",
    "/js/options/general.js",
    "/js/options/user-js.js",
    "/js/options/user-css.js",
    "/js/instance.settings.js",
    "/js/jquery-ui.custom.min.js",
    "/js/quick-reply.js",
    "/js/filters.js",
    "/js/post-filter.js",
    "/js/local-time.js",
    "/js/titlebar-notifications.js",
    "/js/auto-reload.js",
    "/js/image-hover.js",
    "/js/post-hover.js",
    "/js/show-backlinks.js",
    "/js/show-op.js",
    "/js/show-own-posts-options.js",
    "/js/archive.js",
    "/js/mobile-style.js",
    "/js/fix-report-delete-submit.js",
    "/js/quick-post-controls.js",
    "/js/download-original.js",
    "/js/unspoiler3.js",
    "/js/ruffle.js",
    "/js/expand-swf.js",
    "/js/catalog-search.js",
    "/js/webm-settings.js",
    "/js/webm-settings.js",
    "/js/expand-video.js",
    "/js/download-original.js"
  ]

  @catalog_javascript_urls @base_javascript_urls ++
                             ["/js/jquery.mixitup.min.js", "/js/catalog.js"]

  def head_html(active_page, opts \\ []) do
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
    <script type="text/javascript">var active_page = "#{active_page}", board_name = #{board_name}#{thread_fragment};</script><script type="text/javascript">var configRoot="/";var inMod = false;var modRoot="/"+(inMod ? "mod.php?/" : "");var resourceVersion="";</script>
    <script type="text/javascript">var selectedstyle = #{Jason.encode!(selected_style)}; var styles = #{styles_json};</script>
    """
    |> String.trim()
  end

  def javascript_urls, do: @base_javascript_urls
  def javascript_urls(:catalog), do: @catalog_javascript_urls
  def javascript_urls(_page), do: @base_javascript_urls

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
    "<script type=\"text/javascript\">ready();</script>"
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
    |> String.replace(~r/<[^>]*>/, "")
    |> String.slice(0, 256)
  end

  defp escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
