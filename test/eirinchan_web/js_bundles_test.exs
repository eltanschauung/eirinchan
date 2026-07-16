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
