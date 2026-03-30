defmodule EirinchanWeb.SearchHTML do
  use EirinchanWeb, :html
  import EirinchanWeb.BrowserPostComponents
  import EirinchanWeb.BrowserPageComponents

  embed_templates "search_html/*"

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  def search_post(assigns) do
    ~H"""
    <.browser_post
      post={@post}
      board={@board}
      thread={@thread}
      config={@config}
      show_reply_link={true}
      quote_mode={:navigate}
    />
    """
  end
end
