defmodule EirinchanWeb.JavaScriptLayoutTest do
  use ExUnit.Case, async: true

  test "public shell defers application scripts after the synchronous preference bootstrap" do
    template = File.read!("lib/eirinchan_web/components/layouts/root.html.heex")

    preference_position = :binary.match(template, "/js/user-flag-preference.js") |> elem(0)
    eager_position = :binary.match(template, "assigns[:eager_javascript_urls]") |> elem(0)

    assert preference_position < eager_position
    assert template =~ ~r/:if=\{assigns\[:public_shell\]\}.*?\/js\/user-flag-preference\.js/s
    assert template =~ ~r/:for=\{script_url <- assigns\[:eager_javascript_urls\].*?\}\s+defer/s
    assert template =~ ~r/:for=\{\s*script_url <-.*?assigns\[:javascript_urls\].*?\}\s+defer/s
  end
end
