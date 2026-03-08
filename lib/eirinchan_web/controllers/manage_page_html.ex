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

  def moderation_post(assigns) do
    ~H"""
    <%= if is_nil(@post.thread_id) do %>
      <div class="thread" id={"thread_#{@post.id}"} data-board={@board.uri}>
        <.files_block post={@post} config={@config} op?={true} />

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
              <%= raw(PostView.intro_identity_html(@post, @board, @config, @moderator)) %>
            </label>
            &nbsp;
            <a
              class="post_no"
              id={"post_no_#{@post.id}"}
              onclick={"highlightReply(#{@post.id})"}
              href={PostView.thread_path(@board, @post, @config) <> "##{@post.id}"}
            >
              No.
            </a><a
              class="post_no"
              onclick={"citeReply(#{@post.id})"}
              href={PostView.reply_path(@board, @post, @post, @config, :quote)}
              data-quote-to={@post.id}
            ><%= @post.id %></a>
            <%= for icon <- PostView.state_icons(@post, @config) do %>
              <img class="icon" title={icon.title} src={icon.path} alt={icon.title} />
            <% end %>
            <a href={PostView.thread_path(@board, @post, @config)}>[Reply]</a>
            <%= raw(PostView.post_controls_html(@post, @board, @moderator, @secure_manage_token)) %>
          </p>
          <div class="body">
            <%= raw(PostView.body_html(@post, @board, @post, @config)) %>
          </div>
        </div>

        <br class="clear" />
      </div>
    <% else %>
      <div class="post reply" id={"reply_#{@post.id}"}>
        <p class="intro">
          <a id={to_string(@post.id)} class="post_anchor"></a>
          <input type="checkbox" class="delete" name={"delete_#{@post.id}"} id={"delete_#{@post.id}"} />
          <label for={"delete_#{@post.id}"}>
            <%= raw(PostView.intro_identity_html(@post, @board, @config, @moderator)) %>
          </label>
          &nbsp;
          <a
            class="post_no"
            id={"post_no_#{@post.id}"}
            onclick={"highlightReply(#{@post.id})"}
            href={PostView.thread_path(@board, @thread, @config) <> "##{@post.id}"}
          >
            No.
          </a><a
            class="post_no"
            onclick={"citeReply(#{@post.id})"}
            href={PostView.reply_path(@board, @thread, @post, @config, :quote)}
            data-quote-to={@post.id}
          ><%= @post.id %></a>
        </p>

        <.files_block post={@post} config={@config} op?={false} />

        <%= raw(PostView.post_controls_html(@post, @board, @moderator, @secure_manage_token)) %>
        <div
          class="body"
          {case PostView.reply_body_style(@post) do
            nil -> []
            style -> [style: style]
          end}
        >
          <%= raw(PostView.body_html(@post, @board, @thread, @config)) %>
        </div>
      </div>
    <% end %>
    """
  end

  attr :post, :map, required: true
  attr :config, :map, required: true
  attr :op?, :boolean, default: false

  defp files_block(assigns) do
    ~H"""
    <div class="files">
      <%= for media <- PostView.media_entries(@post, @config) do %>
        <%= if PostView.embed_entry?(media) do %>
          <%= raw(media.embed_html) %>
        <% else %>
          <% file = media %>
          <div
            class={PostView.file_class(@post)}
            {case PostView.multifile_style(file, @config,
                  multifile: PostView.media_multifile?(@post)
                ) do
              nil -> []
              style -> [style: style]
            end}
          >
            <p class="fileinfo">
              File: <a href={file.file_path}><%= PostView.stored_file_name(file) %></a>
              <span>
                (<%= PostView.file_size_text(file) %><%= if PostView.file_dimensions(file),
                  do: raw(", " <> PostView.file_dimensions(file)) %>, <span
                  class="postfilename"
                  title={PostView.original_file_name(file)}
                ><%= PostView.display_file_name(file, @config) %></span>)
              </span>
            </p>
            <a href={file.file_path}>
              <img
                class="post-image"
                src={file.thumb_path || file.file_path}
                style={PostView.thumb_style(file, @config, op?: @op?)}
                alt=""
              />
            </a>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
