defmodule EirinchanWeb.ManagePageHTML do
  use EirinchanWeb, :html

  alias Eirinchan.Noticeboard.Entry, as: NoticeboardEntry
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
    assigns =
      assigns
      |> assign(:public_post_id, PostView.public_post_id(assigns.post))
      |> assign(:public_thread_id, PostView.public_post_id(assigns.thread))

    ~H"""
    <%= if is_nil(@post.thread_id) do %>
      <div class="thread" id={"thread_#{@public_post_id}"} data-board={@board.uri}>
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
          id={"op_#{@public_post_id}"}
          {case PostView.post_container_style(@post) do
            nil -> []
            style -> [style: style]
          end}
        >
          <p class="intro">
            <input
              type="checkbox"
              class="delete"
              name={"delete_#{@public_post_id}"}
              id={"delete_#{@public_post_id}"}
            />
            <label for={"delete_#{@public_post_id}"}>
              <.post_identity
                post={@post}
                config={@config}
                board={@board}
                moderator={@moderator}
                own={@show_yous and MapSet.member?(@own_post_ids, @public_post_id)}
              />
            </label>
            <.post_number_links
              post_id={@public_post_id}
              post_href={PostView.thread_path(@board, @post, @config) <> "##{@public_post_id}"}
              quote_href={PostView.reply_path(@board, @post, @post, @config, :quote)}
              quote_to={@public_post_id}
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
          <.body_container
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
          <input type="checkbox" class="delete" name={"delete_#{@public_post_id}"} id={"delete_#{@public_post_id}"} />
          <.reply_post_button post_target={"reply_#{@public_post_id}"} />
          <label for={"delete_#{@public_post_id}"}>
            <.post_identity
              post={@post}
              config={@config}
              board={@board}
              moderator={@moderator}
              own={@show_yous and MapSet.member?(@own_post_ids, @public_post_id)}
            />
          </label>
          <.post_number_links
            post_id={@public_post_id}
            post_href={PostView.thread_path(@board, @thread, @config) <> "##{@public_post_id}"}
            quote_href={PostView.reply_path(@board, @thread, @post, @config, :quote)}
            quote_to={@public_post_id}
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
        <.body_container
          post={@post}
          board={@board}
          thread={@thread}
          config={@config}
          own_post_ids={@own_post_ids}
          show_yous={@show_yous}
        />
      </div>
    <% end %>
    """
  end

  def noticeboard_delete_token(%NoticeboardEntry{id: id}) do
    Phoenix.Token.sign(EirinchanWeb.Endpoint, "noticeboard-delete", Integer.to_string(id))
  end

  def noticeboard_page_path(1), do: "/manage/noticeboard"
  def noticeboard_page_path(page_no) when is_integer(page_no) and page_no > 1, do: "/manage/noticeboard/#{page_no}"
end
