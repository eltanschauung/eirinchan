defmodule EirinchanWeb.SearchHTML do
  use EirinchanWeb, :html

  alias Eirinchan.Posts.PublicIds
  alias EirinchanWeb.{PostComponents, PostView}

  embed_templates "search_html/*"

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false

  def search_post(assigns) do
    assigns =
      assigns
      |> assign(:public_post_id, PublicIds.public_id(assigns.post))
      |> assign(:public_thread_id, PublicIds.public_id(assigns.thread))

    ~H"""
    <%= if is_nil(@post.thread_id) do %>
      <div class="thread" id={"thread_#{@public_post_id}"} data-board={@board.uri}>
        <PostComponents.files_block post={@post} config={@config} board={@board} />

        <div class="post op" id={"op_#{@public_post_id}"}>
          <p class="intro">
            <PostComponents.post_identity
              post={@post}
              config={@config}
              board={@board}
              own={@show_yous and MapSet.member?(@own_post_ids, @public_post_id)}
            />
            <PostComponents.post_number_links
              post_id={@public_post_id}
              post_href={PostView.thread_path(@board, @post, @config) <> "##{@public_post_id}"}
              quote_href={PostView.reply_path(@board, @post, @post, @config, :quote)}
              quote_to={@public_post_id}
              quote_mode={:navigate}
            />
            <%= for icon <- PostView.state_icons(@post, @config) do %>
              <img class="icon" title={icon.title} src={icon.path} alt={icon.title} />
            <% end %>
            <a href={PostView.thread_path(@board, @post, @config)}>[Reply]</a>
          </p>
          <PostComponents.body_container
            post={@post}
            board={@board}
            thread={@post}
            config={@config}
            op?={true}
            own_post_ids={@own_post_ids}
            show_yous={@show_yous}
          />
        </div>

        <br class="clear" />
      </div>
    <% else %>
      <div class="post reply" id={"reply_#{@public_post_id}"}>
        <p class="intro">
          <a id={to_string(@public_post_id)} class="post_anchor"></a>
          <PostComponents.post_identity
            post={@post}
            config={@config}
            board={@board}
            own={@show_yous and MapSet.member?(@own_post_ids, @public_post_id)}
          />
          <PostComponents.post_number_links
            post_id={@public_post_id}
            post_href={PostView.thread_path(@board, @thread, @config) <> "##{@public_post_id}"}
            quote_href={PostView.reply_path(@board, @thread, @post, @config, :quote)}
            quote_to={@public_post_id}
            quote_mode={:navigate}
          />
        </p>

        <PostComponents.files_block post={@post} config={@config} board={@board} />
        <PostComponents.body_container
          post={@post}
          board={@board}
          thread={@thread}
          config={@config}
          own_post_ids={@own_post_ids}
          show_yous={@show_yous}
        />
      </div>
      <br class="clear" />
    <% end %>
    """
  end
end
