defmodule EirinchanWeb.BoardChrome do
  @moduledoc false

  alias Eirinchan.Themes

  def for_board(_board), do: default()

  def default(config \\ %{}) do
    catalog_name =
      config
      |> Map.get(:catalog_name, "Catalog")
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "Catalog"
        value -> value
      end

    %{
      subtitle: nil,
      boardlist_groups: nil,
      top_news_html: nil,
      post_form_blotter_html: nil,
      show_footer: true,
      search_links:
        if(Themes.page_theme_enabled?("catalog"),
          do: [%{href: "/__BOARD__/catalog.html", label: "[#{catalog_name}]"}],
          else: []
        ),
      show_default_announcement: true
    }
  end

  def search_links(board_uri, config \\ %{}) do
    default(config)
    |> Map.fetch!(:search_links)
    |> Enum.map(fn link ->
      %{link | href: String.replace(link.href, "__BOARD__", board_uri)}
    end)
  end

  def boardlist_groups(boards, chrome_groups, opts \\ [])
  def boardlist_groups(boards, nil, opts), do: EirinchanWeb.PostView.boardlist_groups(boards, opts)
  def boardlist_groups(boards, chrome_groups, opts), do: Eirinchan.Boardlist.configured_groups_from_value(chrome_groups, boards, opts)
end
