defmodule EirinchanWeb.CookiePolicy do
  @moduledoc false

  @same_site "Lax"

  def browser_identity(max_age) when is_integer(max_age) and max_age > 0 do
    [
      max_age: max_age,
      path: "/",
      http_only: true,
      secure: true,
      same_site: @same_site
    ]
  end

  def browser_identity_delete do
    [path: "/", http_only: true, secure: true, same_site: @same_site]
  end

  def preference(max_age) when is_integer(max_age) and max_age > 0 do
    [
      max_age: max_age,
      path: "/",
      http_only: false,
      secure: secure_browser_cookie?(),
      same_site: @same_site
    ]
  end

  def transient(max_age) when is_integer(max_age) and max_age > 0,
    do: preference(max_age)

  defp secure_browser_cookie? do
    Application.get_env(:eirinchan, :environment) == :prod
  end
end
