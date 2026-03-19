defmodule EirinchanWeb.SearchHTML do
  use EirinchanWeb, :html
  import EirinchanWeb.BrowserPostComponents

  embed_templates "search_html/*"

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false

  def search_post(assigns) do
    ~H"""
    <.browser_post
      post={@post}
      board={@board}
      thread={@thread}
      config={@config}
      own_post_ids={@own_post_ids}
      show_yous={@show_yous}
      show_reply_link={true}
      quote_mode={:navigate}
    />
    """
  end
end
