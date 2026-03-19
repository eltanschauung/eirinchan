defmodule EirinchanWeb.BrowserPostComponents do
  use EirinchanWeb, :html

  alias EirinchanWeb.{PostComponents, PostView}

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil
  attr :backlinks_map, :map, default: %{}
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false
  attr :show_selection, :boolean, default: false
  attr :show_post_button, :boolean, default: false
  attr :show_post_controls, :boolean, default: false
  attr :show_reply_link, :boolean, default: true
  attr :hide_op_fileboard, :boolean, default: false
  attr :thread_attrs, :any, default: []
  attr :quote_mode, :atom, default: :navigate
  slot :op_prefix
  slot :op_suffix

  def browser_post(assigns) do
    assigns =
      assigns
      |> assign(:public_post_id, PostView.public_post_id(assigns.post))
      |> assign(:public_thread_id, PostView.public_post_id(assigns.thread))
      |> assign(:own_post?, assigns.show_yous and MapSet.member?(assigns.own_post_ids, PostView.public_post_id(assigns.post)))

    ~H"""
    <%= if is_nil(@post.thread_id) do %>
      <div
        class="thread"
        id={"thread_#{@public_post_id}"}
        data-board={@board.uri}
        {@thread_attrs}
      >
        <PostComponents.files_block
          post={@post}
          config={@config}
          op?={true}
          board={@board}
          moderator={@moderator}
          secure_manage_token={@secure_manage_token}
        />

        <div
          class="post op"
          id={"op_#{@public_post_id}"}
          {case PostView.post_container_style(@post) do
            nil -> []
            style -> [style: style]
          end}
        >
          <p class="intro">
            <%= render_slot(@op_prefix) %>
            <.selection_checkbox :if={@show_selection} post_id={@public_post_id} />
            <.identity
              post={@post}
              board={@board}
              config={@config}
              moderator={@moderator}
              own_post?={@own_post?}
              show_selection={@show_selection}
              post_id={@public_post_id}
            />
            <PostComponents.post_number_links
              post_id={@public_post_id}
              post_href={PostView.thread_path(@board, @post, @config) <> "##{@public_post_id}"}
              quote_href={PostView.reply_path(@board, @post, @post, @config, :quote)}
              quote_to={@public_post_id}
              quote_mode={@quote_mode}
            />
            <PostComponents.backlinks
              post={@post}
              backlinks_map={@backlinks_map}
              board={@board}
              thread={@post}
              config={@config}
            />
            <%= for icon <- PostView.state_icons(@post, @config) do %>
              <img class="icon" title={icon.title} src={icon.path} alt={icon.title} />
            <% end %>
            <a :if={@show_reply_link} href={PostView.thread_path(@board, @post, @config)}>[Reply]</a>
            <%= render_slot(@op_suffix) %>
            <PostComponents.post_controls
              :if={@show_post_controls}
              post={@post}
              board={@board}
              moderator={@moderator}
              secure_manage_token={@secure_manage_token}
            />
          </p>
          <PostComponents.body_container
            post={@post}
            board={@board}
            thread={@post}
            config={@config}
            op?={true}
            hide_fileboard={@hide_op_fileboard}
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
          <.selection_checkbox :if={@show_selection} post_id={@public_post_id} />
          <PostComponents.reply_post_button :if={@show_post_button} post_target={"reply_#{@public_post_id}"} />
          <.identity
            post={@post}
            board={@board}
            config={@config}
            moderator={@moderator}
            own_post?={@own_post?}
            show_selection={@show_selection}
            post_id={@public_post_id}
          />
          <PostComponents.post_number_links
            post_id={@public_post_id}
            post_href={PostView.thread_path(@board, @thread, @config) <> "##{@public_post_id}"}
            quote_href={PostView.reply_path(@board, @thread, @post, @config, :quote)}
            quote_to={@public_post_id}
            quote_mode={@quote_mode}
          />
          <PostComponents.backlinks
            post={@post}
            backlinks_map={@backlinks_map}
            board={@board}
            thread={@thread}
            config={@config}
          />
        </p>

        <PostComponents.files_block
          post={@post}
          config={@config}
          op?={false}
          board={@board}
          moderator={@moderator}
          secure_manage_token={@secure_manage_token}
        />

        <PostComponents.post_controls
          :if={@show_post_controls}
          post={@post}
          board={@board}
          moderator={@moderator}
          secure_manage_token={@secure_manage_token}
        />
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

  attr :board, :map, required: true
  attr :post, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :prefix, :string, default: "eita"

  def browser_entry_link(assigns) do
    assigns =
      assigns
      |> assign(:public_post_id, PostView.public_post_id(assigns.post))
      |> assign(:public_thread_id, PostView.public_post_id(assigns.thread))

    ~H"""
    <a
      class="eita-link"
      id={"#{@prefix}-#{@board.uri}-#{@public_thread_id}-#{@public_post_id}"}
      href={PostView.thread_path(@board, @thread, @config) <> "##{@public_post_id}"}
    >/ <%= @board.uri %> /<%= @public_post_id %></a>
    """
  end

  attr :post_id, :integer, required: true

  defp selection_checkbox(assigns) do
    ~H"""
    <input
      type="checkbox"
      class="delete"
      name={"delete_#{@post_id}"}
      id={"delete_#{@post_id}"}
    />
    """
  end

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :config, :map, required: true
  attr :moderator, :map, default: nil
  attr :own_post?, :boolean, default: false
  attr :show_selection, :boolean, default: false
  attr :post_id, :integer, required: true

  defp identity(assigns) do
    ~H"""
    <label :if={@show_selection} for={"delete_#{@post_id}"}>
      <PostComponents.post_identity
        post={@post}
        config={@config}
        board={@board}
        moderator={@moderator}
        own={@own_post?}
      />
    </label>
    <PostComponents.post_identity
      :if={!@show_selection}
      post={@post}
      config={@config}
      board={@board}
      moderator={@moderator}
      own={@own_post?}
    />
    """
  end
end
