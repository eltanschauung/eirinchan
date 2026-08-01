defmodule Eirinchan.HomePage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  @legacy_contact_emails ["aryanchad@hitler.rocks", "example@example.com"]
  @public_boards_token "{{public_boards}}"

  def default_body(contact_email \\ "example@example.com") do
    render_to_string(EirinchanWeb.PageHTML, "home_body", "html", contact_email: contact_email)
  end

  def normalize_body(html, contact_email \\ "example@example.com")

  def normalize_body(html, contact_email) when is_binary(html) do
    Enum.reduce(@legacy_contact_emails, html, &String.replace(&2, &1, contact_email))
  end

  def normalize_body(_html, contact_email), do: default_body(contact_email)

  def split_around_public_boards(html) when is_binary(html) do
    case String.split(html, @public_boards_token, parts: 2) do
      [before_boards, after_boards] ->
        {before_boards, String.replace(after_boards, @public_boards_token, "")}

      [body] ->
        {body, ""}
    end
  end

  def split_around_public_boards(_html), do: {"", ""}
end
