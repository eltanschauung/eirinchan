defmodule Eirinchan.HomePage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  def default_body(contact_email \\ "example@example.com") do
    render_to_string(EirinchanWeb.PageHTML, "home_body", "html", contact_email: contact_email)
  end

  def normalize_body(html, contact_email \\ "example@example.com")

  def normalize_body(html, _contact_email) when is_binary(html), do: html

  def normalize_body(_html, contact_email), do: default_body(contact_email)
end
