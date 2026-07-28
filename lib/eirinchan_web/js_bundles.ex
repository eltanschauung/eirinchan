defmodule EirinchanWeb.JsBundles do
  @moduledoc false

  @bundle_order [:core, :default, :thread, :index, :catalog, :ukko, :search]

  @bundle_sources %{
    core: [
      "js/jquery.min.js",
      "js/options.js",
      "js/options/general.js",
      "js/thread-watcher.js",
      "js/blotter.js",
      "js/youtube.js",
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
      "js/image-hover.js",
      "js/post-hover.js",
      "js/show-own-posts.js",
      "js/show-own-posts-options.js",
      "js/legacy-mod-actions.js",
      "js/fix-report-delete-submit.js",
      "js/quick-post-controls.js",
      "js/webm-settings.js",
      "js/expand-video.js"
    ],
    index: [
      "js/inline-expanding.js",
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
      "js/image-hover.js",
      "js/post-hover.js",
      "js/show-own-posts.js",
      "js/show-own-posts-options.js",
      "js/legacy-mod-actions.js",
      "js/fix-report-delete-submit.js",
      "js/quick-post-controls.js",
      "js/webm-settings.js",
      "js/expand-video.js"
    ],
    catalog: [
      "js/ajax.js",
      "js/file-selector.js",
      "js/upload-selection.js",
      "js/post-menu.js",
      "js/post-filter.js",
      "js/image-hover.js",
      "js/show-own-posts.js",
      "js/show-own-posts-options.js",
      "js/legacy-mod-actions.js",
      "js/fix-report-delete-submit.js",
      "js/catalog.js",
      "js/catalog-search.js"
    ],
    ukko: ["js/overboard.js"],
    search: [
      "js/search.js",
      "js/inline-expanding.js",
      "js/expand.js",
      "js/image-hover.js",
      "js/local-time.js",
      "js/show-own-posts.js",
      "js/show-own-posts-options.js"
    ]
  }

  # These readable sources live outside priv/static. The build task emits their
  # minified public counterparts before constructing the public bundles.
  @maintained_outputs %{
    "assets/app.js" => "assets/js/app.js",
    "js/auth-redirect.js" => "assets/js/auth-redirect.js",
    "js/blotter.js" => "assets/js/blotter.js",
    "js/inline-expanding.js" => "assets/js/inline-expanding.js",
    "js/manage-forms.js" => "assets/js/manage-forms.js",
    "js/mobile-style.js" => "assets/js/mobile-style.js",
    "js/options.js" => "assets/js/options.js",
    "js/options/general.js" => "assets/js/options/general.js",
    "js/options/user-css.js" => "assets/js/options/user-css.js",
    "js/options/user-js.js" => "assets/js/options/user-js.js",
    "js/post-filter.js" => "assets/js/post-filter.js",
    "js/runtime-config.js" => "assets/js/runtime-config.js",
    "js/search.js" => "assets/js/search.js",
    "js/youtube.js" => "assets/js/youtube.js"
  }

  @optional_custom_scripts ["js/options/user-js.js", "js/options/user-css.js"]

  @ignored_scripts MapSet.new([
                     "js/archive.js",
                     "js/filters.js",
                     "js/instance.settings.js"
                   ])

  @external_scripts MapSet.new(["js/ruffle.js", "js/expand-swf.js"])

  def bundle_keys_for("thread"), do: bundle_keys_for(:thread)
  def bundle_keys_for("index"), do: bundle_keys_for(:index)
  def bundle_keys_for("ukko"), do: bundle_keys_for(:ukko)
  def bundle_keys_for("catalog"), do: bundle_keys_for(:catalog)
  def bundle_keys_for("search"), do: bundle_keys_for(:search)
  def bundle_keys_for(:thread), do: [:core, :thread]
  def bundle_keys_for(:index), do: [:core, :index]
  def bundle_keys_for(:ukko), do: [:core, :index, :ukko]
  def bundle_keys_for(:catalog), do: [:core, :catalog]
  def bundle_keys_for(:search), do: [:core, :search]
  def bundle_keys_for(_active_page), do: [:core, :default]

  def bundle_urls_for(active_page) do
    active_page
    |> bundle_keys_for()
    |> Enum.map(&bundle_url/1)
  end

  def bundle_url(bundle_key), do: "/js/bundle-public-#{bundle_key}.js"
  def sources_for(bundle_key), do: Map.fetch!(@bundle_sources, bundle_key)

  def bundled_sources_for(active_page) do
    active_page
    |> bundle_keys_for()
    |> Enum.flat_map(&sources_for/1)
    |> MapSet.new()
  end

  def maintained_outputs, do: @maintained_outputs
  def optional_custom_scripts, do: @optional_custom_scripts
  def all_bundle_keys, do: @bundle_order

  def source_path(public_relative_path) when is_binary(public_relative_path) do
    Map.get(
      @maintained_outputs,
      public_relative_path,
      Path.join("priv/static", public_relative_path)
    )
  end

  def output_path(public_relative_path) when is_binary(public_relative_path),
    do: Path.join("priv/static", public_relative_path)

  def ignored_script?(script) when is_binary(script) do
    script
    |> String.trim_leading("/")
    |> then(&MapSet.member?(@ignored_scripts, &1))
  end

  def external_script?(script) when is_binary(script) do
    script
    |> String.trim_leading("/")
    |> then(&MapSet.member?(@external_scripts, &1))
  end

  def validate!(project_root \\ File.cwd!()) do
    bundle_keys = @bundle_sources |> Map.keys() |> MapSet.new()

    unless bundle_keys == MapSet.new(@bundle_order) do
      raise "JavaScript bundle order and bundle source keys differ"
    end

    Enum.each(@bundle_order, fn bundle_key ->
      sources = sources_for(bundle_key)

      if length(sources) != length(Enum.uniq(sources)) do
        raise "duplicate JavaScript source in #{bundle_key} bundle"
      end

      Enum.each(sources, &validate_public_path!/1)
    end)

    Enum.each(@maintained_outputs, fn {output, source} ->
      validate_public_path!(output)
      validate_source_path!(source)
      ensure_file!(project_root, source)
    end)

    @bundle_order
    |> Enum.flat_map(&sources_for/1)
    |> Enum.uniq()
    |> Enum.each(fn public_path ->
      ensure_file!(project_root, source_path(public_path))
    end)

    :ok
  end

  defp validate_public_path!(path) do
    if Path.type(path) == :absolute or String.contains?(path, ["..", "\u0000", "\\"]) do
      raise "unsafe public JavaScript path: #{inspect(path)}"
    end
  end

  defp validate_source_path!(path) do
    if Path.type(path) == :absolute or String.contains?(path, ["..", "\u0000"]) do
      raise "unsafe JavaScript source path: #{inspect(path)}"
    end
  end

  defp ensure_file!(project_root, relative_path) do
    full_path = Path.expand(relative_path, project_root)
    root = Path.expand(project_root)

    unless String.starts_with?(full_path <> "/", root <> "/") and File.regular?(full_path) do
      raise "missing or escaped JavaScript source: #{relative_path}"
    end
  end
end
