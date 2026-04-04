defmodule EirinchanWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias Plug.CSRFProtection

  test "renders 404" do
    assert EirinchanWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert EirinchanWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end

  test "renders csrf-specific 403" do
    assert EirinchanWeb.ErrorJSON.render("403.json", %{
             reason: %CSRFProtection.InvalidCSRFTokenError{}
           }) == %{error: "Your tab is out of date. Refreshing the CSRF token and retrying.", csrf: true}
  end
end
