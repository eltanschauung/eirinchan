defmodule EirinchanWeb.ManagePageHTML do
  use EirinchanWeb, :html

  alias EirinchanWeb.PostView

  embed_templates "manage_page_html/*"

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil
  attr :backlinks_map, :map, default: %{}
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false

  def moderation_post(assigns) do
    ~H"""
    <%= if is_nil(@post.thread_id) do %>
      <div class="thread" id={"thread_#{@post.id}"} data-board={@board.uri}>
        <.files_block
          post={@post}
          config={@config}
          op?={true}
          board={@board}
          moderator={@moderator}
          secure_manage_token={@secure_manage_token}
        />

        <div
          class="post op"
          id={"op_#{@post.id}"}
          {case PostView.post_container_style(@post) do
            nil -> []
            style -> [style: style]
          end}
        >
          <p class="intro">
            <input
              type="checkbox"
              class="delete"
              name={"delete_#{@post.id}"}
              id={"delete_#{@post.id}"}
            />
            <label for={"delete_#{@post.id}"}>
              <.post_identity
                post={@post}
                config={@config}
                board={@board}
                moderator={@moderator}
                own={@show_yous and MapSet.member?(@own_post_ids, @post.id)}
              />
            </label>
            <.post_number_links
              post_id={@post.id}
              post_href={PostView.thread_path(@board, @post, @config) <> "##{@post.id}"}
              quote_href={PostView.reply_path(@board, @post, @post, @config, :quote)}
              quote_to={@post.id}
            />
            <.backlinks post={@post} backlinks_map={@backlinks_map} />
            <%= for icon <- PostView.state_icons(@post, @config) do %>
              <img class="icon" title={icon.title} src={icon.path} alt={icon.title} />
            <% end %>
            <a href={PostView.thread_path(@board, @post, @config)}>[Reply]</a>
            <.post_controls
              post={@post}
              board={@board}
              moderator={@moderator}
              secure_manage_token={@secure_manage_token}
            />
          </p>
          <%= raw(
            PostView.body_container_html(@post, @board, @post, @config,
              op?: true,
              own_post_ids: @own_post_ids,
              show_yous: @show_yous
            )
          ) %>
        </div>

        <br class="clear" />
      </div>
    <% else %>
      <div class="post reply" id={"reply_#{@post.id}"}>
        <p class="intro">
          <a id={to_string(@post.id)} class="post_anchor"></a>
          <input type="checkbox" class="delete" name={"delete_#{@post.id}"} id={"delete_#{@post.id}"} />
          <.reply_post_button post_target={"reply_#{@post.id}"} />
          <label for={"delete_#{@post.id}"}>
            <.post_identity
              post={@post}
              config={@config}
              board={@board}
              moderator={@moderator}
              own={@show_yous and MapSet.member?(@own_post_ids, @post.id)}
            />
          </label>
          <.post_number_links
            post_id={@post.id}
            post_href={PostView.thread_path(@board, @thread, @config) <> "##{@post.id}"}
            quote_href={PostView.reply_path(@board, @thread, @post, @config, :quote)}
            quote_to={@post.id}
          />
          <.backlinks post={@post} backlinks_map={@backlinks_map} />
        </p>

        <.files_block
          post={@post}
          config={@config}
          op?={false}
          board={@board}
          moderator={@moderator}
          secure_manage_token={@secure_manage_token}
        />

        <.post_controls
          post={@post}
          board={@board}
          moderator={@moderator}
          secure_manage_token={@secure_manage_token}
        />
        <%= raw(
          PostView.body_container_html(@post, @board, @thread, @config,
            own_post_ids: @own_post_ids,
            show_yous: @show_yous
          )
        ) %>
      </div>
    <% end %>
    """
  end
end
