defmodule EirinchanWeb.ErrorHTMLTest do
  use ExUnit.Case, async: true

  alias Plug.CSRFProtection

  test "renders 404.html" do
    assert EirinchanWeb.ErrorHTML.render("404", %{}) == "Not Found"
  end

  test "renders 500.html" do
    assert EirinchanWeb.ErrorHTML.render("500", %{}) == "Internal Server Error"
  end

  test "renders csrf-specific 403.html message" do
    assert EirinchanWeb.ErrorHTML.render("403", %{
             reason: %CSRFProtection.InvalidCSRFTokenError{}
           }) == "Invalid CSRF token"
  end
end
