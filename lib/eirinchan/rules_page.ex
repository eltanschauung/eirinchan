defmodule Eirinchan.RulesPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]
  alias Eirinchan.LegacyPageBody

  @legacy_contact_emails ["aryanchad@hitler.rocks", "example@example.com"]

  def default_body(contact_email \\ "example@example.com") do
    render_to_string(EirinchanWeb.PageHTML, "rules_body", "html", contact_email: contact_email)
  end

  def normalize_body(html, contact_email \\ "example@example.com") do
    html = replace_legacy_contact_email(html, contact_email)

    LegacyPageBody.normalize(html, fn -> default_body(contact_email) end,
      content_regex:
        ~r|(<div class="box-wrap(?: faq-page-shell)?(?: rules-page-shell)?">.*?</div>\s*)<hr|s,
      strip: [:style, :header, :horizontal_rule]
    )
  end

  defp replace_legacy_contact_email(html, contact_email) when is_binary(html) do
    Enum.reduce(@legacy_contact_emails, html, &String.replace(&2, &1, contact_email))
  end

  defp replace_legacy_contact_email(html, _contact_email), do: html
end
