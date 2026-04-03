defmodule Eirinchan.PublicPages do
  @moduledoc false

  alias Eirinchan.CustomPages
  alias Eirinchan.FeedbackPage
  alias Eirinchan.FlagsPage
  alias Eirinchan.FaqPage
  alias Eirinchan.FormattingPage
  alias Eirinchan.RulesPage

  def fetch_named_page(slug, opts \\ []) when is_binary(slug) do
    current_stickers = Keyword.get(opts, :stickers, [])

    case CustomPages.get_page_by_slug(slug) do
      %CustomPages.Page{} = page ->
        normalize_page(page, stickers: current_stickers)

      nil ->
        default_named_page(slug, current_stickers)
    end
  end

  def normalize_page(page, opts \\ [])

  def normalize_page(%{slug: slug} = page, opts) when is_binary(slug) do
    current_stickers = Keyword.get(opts, :stickers, [])

    case slug do
      "faq" -> %{page | body: FaqPage.normalize_body(page.body)}
      "formatting" -> %{page | body: FormattingPage.normalize_body(page.body, current_stickers)}
      "rules" -> %{page | body: RulesPage.normalize_body(page.body)}
      "flags" -> %{page | body: FlagsPage.normalize_body(page.body)}
      "feedback" -> %{page | body: FeedbackPage.normalize_body(page.body)}
      _ -> page
    end
  end

  def normalize_page(page, _opts), do: page

  def page_subtitle("faq"), do: "Ask questions, get answers."
  def page_subtitle("formatting"), do: "Ask questions, get answers."
  def page_subtitle("rules"), do: "Ask questions, get answers."
  def page_subtitle(_slug), do: nil

  def show_global_message?(slug) when slug in ["flags", "feedback", "faq", "formatting"],
    do: false

  def show_global_message?(_slug), do: true

  defp default_named_page("faq", _current_stickers) do
    %{slug: "faq", title: "FAQ", body: FaqPage.default_body(), mod_user: nil}
  end

  defp default_named_page("formatting", current_stickers) do
    %{slug: "formatting", title: "Formatting", body: FormattingPage.default_body(current_stickers), mod_user: nil}
  end

  defp default_named_page("rules", _current_stickers) do
    %{slug: "rules", title: "Rules", body: RulesPage.default_body(), mod_user: nil}
  end

  defp default_named_page("flags", _current_stickers) do
    %{slug: "flags", title: "Flags", body: FlagsPage.default_body(), mod_user: nil}
  end

  defp default_named_page("feedback", _current_stickers) do
    %{slug: "feedback", title: "Feedback", body: FeedbackPage.default_body(), mod_user: nil}
  end

  defp default_named_page(_slug, _current_stickers), do: nil

end
