defmodule EirinchanWeb.JsBundlesTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.JsBundles

  test "bundle order and URLs are deterministic" do
    assert JsBundles.all_bundle_keys() == [
             :core,
             :default,
             :thread,
             :index,
             :catalog,
             :ukko,
             :search
           ]

    assert JsBundles.bundle_urls_for(:thread) == [
             "/js/bundle-public-core.js",
             "/js/bundle-public-thread.js"
           ]
  end

  test "every bundle has unique source entries" do
    Enum.each(JsBundles.all_bundle_keys(), fn bundle_key ->
      sources = JsBundles.sources_for(bundle_key)
      assert sources == Enum.uniq(sources)
    end)
  end

  test "optional user code is not shipped in the default core bundle" do
    core = JsBundles.sources_for(:core)

    refute "js/options/user-js.js" in core
    refute "js/options/user-css.js" in core

    assert JsBundles.optional_custom_scripts() == [
             "js/options/user-js.js",
             "js/options/user-css.js"
           ]
  end

  test "loads options before scripts that extend it" do
    core_sources = JsBundles.sources_for(:core)
    options_index = Enum.find_index(core_sources, &(&1 == "js/options.js"))
    watcher_index = Enum.find_index(core_sources, &(&1 == "js/thread-watcher.js"))

    assert is_integer(options_index)
    assert is_integer(watcher_index)
    assert options_index < watcher_index
  end

  test "every page bundle shares the complete index Options menu" do
    options_sources =
      MapSet.new([
        "js/options.js",
        "js/options/general.js",
        "js/thread-watcher.js",
        "js/navarrows2.js",
        "js/post-filter.js",
        "js/image-hover.js",
        "js/show-own-posts-options.js",
        "js/webm-settings.js"
      ])

    assert options_sources
           |> MapSet.difference(MapSet.new(JsBundles.sources_for(:core)))
           |> MapSet.size() == 0

    Enum.each([:default, :thread, :index, :catalog, :ukko, :search], fn bundle_key ->
      assert MapSet.disjoint?(options_sources, MapSet.new(JsBundles.sources_for(bundle_key)))
    end)
  end

  test "maintained minified outputs resolve to readable non-static sources" do
    outputs = JsBundles.maintained_outputs()

    assert outputs["js/runtime-config.js"] == "assets/js/runtime-config.js"
    assert outputs["assets/app.js"] == "assets/js/app.js"
    assert outputs["js/options.js"] == "assets/js/options.js"

    Enum.each(outputs, fn {public_output, source} ->
      assert String.starts_with?(JsBundles.output_path(public_output), "priv/static/")
      refute String.starts_with?(source, "priv/static/")
    end)
  end
end
