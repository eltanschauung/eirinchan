defmodule Eirinchan.HomePage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  @legacy_contact_emails ["aryanchad@hitler.rocks", "example@example.com"]

  def default_body(contact_email \\ "example@example.com") do
    render_to_string(EirinchanWeb.PageHTML, "home_body", "html", contact_email: contact_email)
  end

  def normalize_body(html, contact_email \\ "example@example.com")

  def normalize_body(html, contact_email) when is_binary(html) do
    Enum.reduce(@legacy_contact_emails, html, &String.replace(&2, &1, contact_email))
  end

  def normalize_body(_html, contact_email), do: default_body(contact_email)
end
