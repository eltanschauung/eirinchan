defmodule EirinchanWeb.PostComponents do
  use Phoenix.Component

  alias EirinchanWeb.{IpPresentation, PostView}

  attr :post, :map, required: true
  attr :config, :map, required: true
  attr :board, :map, required: true
  attr :moderator, :map, default: nil
  attr :own, :boolean, default: false

  def post_identity(assigns) do
    assigns =
      assigns
      |> assign(:visible_ip, visible_ip(assigns.post, assigns.board, assigns.moderator))
      |> assign(:flags, PostView.post_flags(assigns.post, assigns.config))

    ~H"""
    <span :if={@post.subject} class="subject"><%= @post.subject %></span><%= if @post.subject, do: " " %>
    <%= if PostView.email_link?(@post.email, @config) do %>
      <a class="email" href={"mailto:" <> to_string(@post.email)}>
        <span class="name"><%= PostView.display_name(@post, @config) %></span>
      </a>
    <% else %>
      <span class="name"><%= PostView.display_name(@post, @config) %></span>
    <% end %>
    <%= if @own, do: " " %><span :if={@own} class="own_post">(You)</span><%= if @post.tripcode,
      do: " " %><span :if={@post.tripcode} class="trip"><%= @post.tripcode %></span><%= if @visible_ip,
      do: " " %><a
      :if={@visible_ip}
      class="ip-link"
      style="margin:0;"
      href={"/mod.php?/IP/" <> @visible_ip}
    >[<%= @visible_ip %>]</a><%= if @flags != [], do: " " %>
    <%= for {flag, index} <- Enum.with_index(@flags) do %>
      <%= if index > 0, do: " " %>
      <img
        class="flag"
        src={flag.src}
        alt={flag.alt}
        title={flag.alt}
        style={PostView.flag_style(@config)}
      />
    <% end %>
    <%= if @flags != [], do: " " %><time datetime={PostView.iso_timestamp(@post)}><%= PostView.formatted_timestamp(@post) %></time>
    """
  end

  attr :post_id, :integer, required: true
  attr :post_href, :string, required: true
  attr :quote_href, :string, required: true
  attr :quote_mode, :atom, default: :inline
  attr :quote_to, :integer, default: nil
  attr :quick_reply_thread, :integer, default: nil

  def post_number_links(assigns) do
    ~H"""
    &nbsp;<a class="post_no" id={"post_no_#{@post_id}"} onclick={"highlightReply(#{@post_id})"} href={@post_href}>No.</a><a class="post_no" onclick={quote_onclick(@post_id, @quote_mode)} href={@quote_href} data-quote-to={@quote_to} data-quick-reply-thread={@quick_reply_thread}><%= @post_id %></a>
    """
  end

  attr :post_target, :string, required: true

  def reply_post_button(assigns) do
    ~H"""
    <a href="#" class="post-btn" title="Post menu" data-post-target={@post_target}>▶</a>
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
        >
          &gt;&gt;<%= backlink_id %>
        </a>
      <% end %>
    </span>
    """
  end

  attr :board_uri, :string, required: true
  attr :thread_id, :integer, required: true
  attr :post_target, :string, required: true
  attr :watch, :map, default: %{watched: false, unread_count: 0}
  attr :show_hide, :boolean, default: false

  def thread_top_controls(assigns) do
    watched = Map.get(assigns.watch || %{}, :watched, false)
    assigns = assign(assigns, :watched, watched)

    ~H"""
    <span class="thread-top-controls">
      <a :if={@show_hide} class="hide-thread-link" href="javascript:void(0)" title="Hide thread">[–]</a>
      <a href="#" class="post-btn" title="Post menu" data-post-target={@post_target}>▶</a>
      <a
        href="javascript:;"
        class={["watch-thread-link", @watched && "watched"]}
        title={if @watched, do: "Unwatch Thread", else: "Watch Thread"}
        data-thread-watch
        data-board-uri={@board_uri}
        data-thread-id={@thread_id}
        data-watch-url={"/watcher/#{@board_uri}/#{@thread_id}"}
        data-unwatch-url={"/watcher/#{@board_uri}/#{@thread_id}"}
        data-watched={to_string(@watched)}
      >
      </a>
    </span>
    """
  end

  attr :moderator, :map, default: nil

  def admin_shortcuts(assigns) do
    ~H"""
    <div :if={@moderator} class="admin-shortcuts unimportant">
      <a href="/manage">Return to Dashboard</a>
      |
      <form action="/manage/logout/browser" method="post" class="inline-form admin-shortcuts-form">
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="_method" value="delete" />
        <a href="/manage/logout/browser" class="admin-shortcuts-logout" onclick="this.closest('form').submit(); return false;">Logout</a>
      </form>
    </div>
    """
  end

  defp quote_onclick(post_id, :navigate), do: "citeReply(#{post_id})"
  defp quote_onclick(post_id, _mode), do: "return citeReply(#{post_id}, false)"

  defp visible_ip(post, board, moderator) do
    if PostView.can_view_ip?(moderator, board) and post.ip_subnet do
      IpPresentation.display_ip(post.ip_subnet, moderator)
    end
  end
end
