defmodule EirinchanWeb.JavaScriptLayoutTest do
  use ExUnit.Case, async: true

  test "all public shell scripts are deferred" do
    template = File.read!("lib/eirinchan_web/components/layouts/root.html.heex")

    assert template =~ ~r/:for=\{script_url <- assigns\[:eager_javascript_urls\].*?\}\s+defer/s
    assert template =~ ~r/:for=\{\s*script_url <-.*?assigns\[:javascript_urls\].*?\}\s+defer/s
  end
end
