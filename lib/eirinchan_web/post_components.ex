defmodule EirinchanWeb.PostComponents do
  use Phoenix.Component

  attr :post_id, :integer, required: true
  attr :post_href, :string, required: true
  attr :quote_href, :string, required: true
  attr :quote_mode, :atom, default: :inline
  attr :quote_to, :integer, default: nil
  attr :quick_reply_thread, :integer, default: nil

  def post_number_links(assigns) do
    ~H"""
    &nbsp;<a
      class="post_no"
      id={"post_no_#{@post_id}"}
      onclick={"highlightReply(#{@post_id})"}
      href={@post_href}
    >No.</a><a
      class="post_no"
      onclick={quote_onclick(@post_id, @quote_mode)}
      href={@quote_href}
      data-quote-to={@quote_to}
      data-quick-reply-thread={@quick_reply_thread}
    ><%= @post_id %></a>
    """
  end

  attr :post, :map, required: true
  attr :backlinks_map, :map, default: %{}

  def backlinks(assigns) do
    backlinks =
      assigns.post
      |> Map.get(:id)
      |> then(&Map.get(assigns.backlinks_map || %{}, &1, []))

    assigns = assign(assigns, :backlinks, backlinks)

    ~H"""
    <span :if={@backlinks != []} class="mentioned">
      <%= for backlink_id <- @backlinks do %>
        <a
          class={"mentioned-#{backlink_id}"}
          onclick={"highlightReply('#{backlink_id}');"}
          href={"##{backlink_id}"}
        >&gt;&gt;<%= backlink_id %></a>
      <% end %>
    </span>
    """
  end

  defp quote_onclick(post_id, :navigate), do: "citeReply(#{post_id})"
  defp quote_onclick(post_id, _mode), do: "return citeReply(#{post_id}, false)"
end
