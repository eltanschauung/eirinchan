defmodule EirinchanWeb.ThemeLayoutTest do
  use EirinchanWeb.ConnCase, async: true

  test "selected theme stylesheet is rendered into the root layout", %{conn: conn} do
    page =
      conn
      |> put_req_cookie("theme", "tomorrow")
      |> get("/search", %{"q" => ""})
      |> html_response(200)

    refute page =~ ~s(action="/theme")
    assert page =~ ~s(/stylesheets/style.css)
    assert page =~ ~s(var selectedstyle = "Tomorrow")
    assert page =~ ~s("Tomorrow":{"name":"tomorrow","uri":"/stylesheets/tomorrow.css"})
    assert page =~ ~s("Christmas":{"name":"christmas","uri":"/stylesheets/christmas.css"})
    assert page =~ ~s("Eientei1":{"name":"eientei1","uri":"/stylesheets/eientei1.css"})
    assert page =~ ~s("Yotsuba B":{"name":"vichan","uri":"/stylesheets/style.css"})
    assert page =~ ~s("Yotsuba":{"name":"default","uri":"/stylesheets/yotsuba.css"})
    refute page =~ "Keyed Frog"
  end
end
