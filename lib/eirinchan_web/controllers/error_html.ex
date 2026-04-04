defmodule EirinchanWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use EirinchanWeb, :html

  def render("403", %{reason: %Plug.CSRFProtection.InvalidCSRFTokenError{}}) do
    "Invalid CSRF token"
  end

  def render("403", %{reason: %Plug.CSRFProtection.InvalidCrossOriginRequestError{}}) do
    "Invalid CSRF token"
  end

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
