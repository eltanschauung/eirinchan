defmodule Eirinchan.FaqPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]
  alias Eirinchan.LegacyPageBody

  def default_body do
    render_to_string(EirinchanWeb.PageHTML, "faq_body", "html", [])
  end

  def normalize_body(html) do
    LegacyPageBody.normalize(html, &default_body/0,
      content_regex: ~r|(<div class="box-wrap faq-page-shell">.*?</div>\s*)<footer|s
    )
  end
end
