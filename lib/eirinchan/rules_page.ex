defmodule Eirinchan.RulesPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]
  alias Eirinchan.LegacyPageBody

  def default_body(contact_email \\ "example@example.com") do
    render_to_string(EirinchanWeb.PageHTML, "rules_body", "html", contact_email: contact_email)
  end

  def normalize_body(html, contact_email \\ "example@example.com") do
    LegacyPageBody.normalize(html, fn -> default_body(contact_email) end,
      content_regex:
        ~r|(<div class="box-wrap(?: faq-page-shell)?(?: rules-page-shell)?">.*?</div>\s*)<hr|s,
      strip: [:style, :header, :horizontal_rule]
    )
  end
end
