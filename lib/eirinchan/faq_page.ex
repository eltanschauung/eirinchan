defmodule Eirinchan.FaqPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  alias Eirinchan.Boards
  alias EirinchanWeb.{BoardChrome, PostView, PublicShell, ThemeRegistry}

  def default_html do
    page = %{slug: "faq", title: "FAQ", body: "", mod_user: nil}
    boards = Boards.list_boards()
    primary_board = Enum.find(boards, &(&1.uri == "bant")) || %{uri: "bant"}

    assigns = [
      boards: boards,
      primary_board: primary_board,
      board_chrome: BoardChrome.for_board(primary_board),
      global_boardlist_html: PostView.boardlist_html(PostView.boardlist_groups(boards)),
      public_shell: true,
      viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
      base_stylesheet: "/stylesheets/style.css",
      body_class: "8chan vichan is-not-moderator active-page",
      body_data_stylesheet: "yotsuba.css",
      head_html:
        PublicShell.head_html("page",
          resource_version: nil,
          theme_label: "Yotsuba",
          theme_options: ThemeRegistry.public_all()
        ),
      javascript_urls: PublicShell.javascript_urls("page"),
      custom_javascript_urls: [],
      analytics_html: nil,
      body_end_html: PublicShell.body_end_html(),
      primary_stylesheet: "/stylesheets/yotsuba.css",
      primary_stylesheet_id: "stylesheet",
      extra_stylesheets: [
        "/stylesheets/eirinchan-public.css",
        "/stylesheets/eirinchan-bant.css",
        "/faq/recent.css"
      ],
      hide_theme_switcher: true,
      skip_app_stylesheet: true,
      page: page,
      flag_board: nil,
      flag_assets: [],
      flag_storage_key: "flag_bant",
      page_title: "FAQ",
      layout: false,
      inner_content: nil
    ]

    inner_content = render_to_string(EirinchanWeb.PageHTML, "faq", "html", assigns)

    render_to_string(
      EirinchanWeb.Layouts,
      "root",
      "html",
      Keyword.put(assigns, :inner_content, Phoenix.HTML.raw(inner_content))
    )
  end

  def refresh_boardlists(html) when is_binary(html) do
    boards = Boards.list_boards()

    html
    |> replace_boardlist("boardlist", boards)
    |> replace_boardlist("boardlist bottom", boards)
    |> replace_bottom_boardlist_script()
  end

  def refresh_boardlists(other), do: other

  defp replace_boardlist(html, class_name, boards) do
    replacement = PostView.boardlist_html(PostView.boardlist_groups(boards), class_name)

    Regex.replace(
      ~r/<div class="#{Regex.escape(class_name)}">.*?<\/div>/s,
      html,
      replacement,
      global: false
    )
  end

  defp replace_bottom_boardlist_script(html) do
    Regex.replace(
      ~r/<script>\s*if \(typeof do_boardlist !== 'undefined'\) do_boardlist\('bottom'\);\s*<\/script>/,
      html,
      ~s|<script>if (typeof do_boardlist !== 'undefined') do_boardlist('bottom');</script>|,
      global: false
    )
  end
end
