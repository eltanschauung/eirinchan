defmodule EirinchanWeb.JsBundles do
  @moduledoc false

  @bundle_sources %{
    core: [
      "js/jquery.min.js",
      "js/server-thread-watcher.js",
      "js/blotter.js",
      "js/youtube.js",
      "js/options.js",
      "js/options/general.js",
      "js/options/user-js.js",
      "js/options/user-css.js",
      "js/mobile-style.js"
    ],
    default: [
      "js/inline-expanding.js",
      "js/expand.js",
      "js/image-hover.js",
      "js/post-hover.js",
      "js/local-time.js"
    ],
    thread: [
      "js/inline-expanding.js",
      "js/save-user_flag.js",
      "js/thread-stats.js",
      "js/strftime.min.js",
      "js/ajax.js",
      "js/navarrows2.js",
      "js/file-selector.js",
      "js/upload-selection.js",
      "js/expand.js",
      "js/jquery-ui.custom.min.js",
      "js/quick-reply.js",
      "js/post-menu.js",
      "js/post-filter.js",
      "js/local-time.js",
      "js/titlebar-notifications.js",
      "js/auto-reload.js",
      "js/image-hover.js",
      "js/post-hover.js",
      "js/show-own-posts.js",
      "js/show-own-posts-options.js",
      "js/fix-report-delete-submit.js",
      "js/quick-post-controls.js",
      "js/webm-settings.js",
      "js/expand-video.js"
    ],
    index: [
      "js/inline-expanding.js",
      "js/save-user_flag.js",
      "js/strftime.min.js",
      "js/ajax.js",
      "js/navarrows2.js",
      "js/file-selector.js",
      "js/upload-selection.js",
      "js/expand.js",
      "js/jquery-ui.custom.min.js",
      "js/quick-reply.js",
      "js/hide-threads.js",
      "js/post-menu.js",
      "js/post-filter.js",
      "js/local-time.js",
      "js/titlebar-notifications.js",
      "js/auto-reload.js",
      "js/image-hover.js",
      "js/post-hover.js",
      "js/show-own-posts.js",
      "js/show-own-posts-options.js",
      "js/fix-report-delete-submit.js",
      "js/quick-post-controls.js",
      "js/webm-settings.js",
      "js/expand-video.js"
    ],
    catalog: [
      "js/save-user_flag.js",
      "js/ajax.js",
      "js/file-selector.js",
      "js/upload-selection.js",
      "js/post-menu.js",
      "js/post-filter.js",
      "js/image-hover.js",
      "js/show-own-posts.js",
      "js/show-own-posts-options.js",
      "js/fix-report-delete-submit.js",
      "js/catalog.js",
      "js/catalog-search.js"
    ],
    search: [
      "js/inline-expanding.js",
      "js/expand.js",
      "js/image-hover.js",
      "js/local-time.js"
    ]
  }

  @ignored_scripts MapSet.new([
                     "js/archive.js",
                     "js/filters.js",
                     "js/instance.settings.js",
                     "js/ruffle.js",
                     "js/expand-swf.js"
                   ])

  def bundle_keys_for(:thread), do: [:core, :thread]
  def bundle_keys_for(:index), do: [:core, :index]
  def bundle_keys_for(:ukko), do: [:core, :index]
  def bundle_keys_for(:catalog), do: [:core, :catalog]
  def bundle_keys_for(:search), do: [:core, :search]
  def bundle_keys_for(_active_page), do: [:core, :default]

  def bundle_urls_for(active_page) do
    active_page
    |> bundle_keys_for()
    |> Enum.map(&bundle_url/1)
  end

  def bundle_url(bundle_key) do
    "/js/bundle-public-#{bundle_key}.js"
  end

  def sources_for(bundle_key) do
    Map.fetch!(@bundle_sources, bundle_key)
  end

  def bundled_sources_for(active_page) do
    active_page
    |> bundle_keys_for()
    |> Enum.flat_map(&sources_for/1)
    |> MapSet.new()
  end

  def ignored_script?(script) when is_binary(script) do
    normalized = String.trim_leading(script, "/")
    MapSet.member?(@ignored_scripts, normalized)
  end

  def all_bundle_keys do
    Map.keys(@bundle_sources)
  end
end
