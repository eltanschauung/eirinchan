defmodule EirinchanWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use EirinchanWeb, :html
  import EirinchanWeb.BrowserPostComponents

  attr :page, :map, required: true
  attr :global_message_html, :string, default: nil
  attr :current_moderator, :any, default: nil
  attr :board_chrome, :map, default: %{show_footer: true}
  attr :subtitle, :string, default: nil
  attr :show_global_message, :boolean, default: true
  slot :inner_block, required: true

  def page_shell(assigns) do
    ~H"""
    <header>
      <h1><%= @page.title %></h1>

      <div :if={present_text?(@subtitle)} class="subtitle"><%= @subtitle %></div>
      <.admin_shortcuts moderator={@current_moderator} />
    </header>

    <%= if @show_global_message && @global_message_html && @global_message_html != "" do %>
      <%= raw(@global_message_html) %>
    <% end %>
    <%= render_slot(@inner_block) %>
    <%= if @board_chrome.show_footer do %>
      <EirinchanWeb.PostComponents.site_footer />
    <% end %>
    """
  end

  attr :watch_summaries, :list, default: []

  def watcher_list(assigns) do
    ~H"""
    <div class="watcher-page">
      <%= if @watch_summaries == [] do %>
        <div class="watcher-entry">
          <p class="body">No watched threads yet.</p>
        </div>
      <% else %>
        <div class="watcher-list">
          <%= for watch <- @watch_summaries do %>
            <div class="watcher-thread">
              <div class={["watcher-entry", watch.unread_count > 0 && "has-unread"]}>
                <p class="intro">
                  <a href={watch.thread_path}>
                    /<%= watch.board_uri %>/ - <%= watch.subject || watch.excerpt ||
                      "Thread ##{watch.thread_id}" %>
                  </a>

                  <span class="watcher-meta">
                    posts: <%= watch.post_count %> | unread: <%= watch.unread_count %>
                  </span>
                </p>

                <%= if watch.excerpt do %>
                  <div class="body watcher-excerpt"><%= watch.excerpt %></div>
                <% end %>

                <p class="intro watcher-actions">
                  <a
                    href="#"
                    data-thread-watch
                    data-board={watch.board_uri}
                    data-thread-id={watch.thread_id}
                    data-watched="true"
                  >
                    [Unwatch<%= if watch.unread_count > 0, do: " (#{watch.unread_count})", else: "" %>]
                  </a>

                  <a
                    class={["watcher-you-count", watch.you_unread_count > 0 && "replies-quoting-you"]}
                    href={watch.you_unread_path}
                  >
                    [<span>(You)s:</span> (<%= watch.you_unread_count %>)]
                  </a>
                </p>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :recent_images, :list, required: true
  attr :recent_posts, :list, required: true
  attr :use_board_subtitle, :boolean, default: true

  def recent_panels(assigns) do
    ~H"""
    <div class="landing-recent-panels">
      <section class="box left landing-recent-images">
        <h2>Recent Images</h2>

        <div class="landing-recent-images-viewport">
          <ul>
            <li :for={post <- @recent_images}>
              <a href={post.link}>
                <img
                  src={post.src}
                  width={post.thumbwidth}
                  height={post.thumbheight}
                  alt={post.alt}
                  loading="lazy"
                  decoding="async"
                />
              </a>
            </li>
          </ul>
        </div>
      </section>

      <section class="box right landing-recent-posts">
        <h2>Latest Posts</h2>

        <ul>
          <li :for={post <- @recent_posts}>
            <strong><%= recent_post_board_label(post, @use_board_subtitle) %></strong>:
            <a href={post.link}><%= raw(post.snippet) %></a>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  attr :boards, :list, required: true

  def public_boards_box(assigns) do
    ~H"""
    <section class="box middle public-boards">
      <h2>Public Boards</h2>

      <table class="landing-table board-table">
        <thead>
          <tr>
            <th scope="col">Board</th>
            <th scope="col" class="board-ppd">PPD</th>
            <th scope="col" class="board-total">Total Posts</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={board <- @boards}>
            <td class="board-name">
              <a href={board.link}>/<%= board.uri %>/ - <%= board.title %></a>
            </td>
            <td class="board-ppd"><%= board.ppd_text %></td>
            <td class="board-total"><%= board.total_posts_text %></td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  attr :stats, :map, required: true

  def stats_box(assigns) do
    ~H"""
    <section class="box middle landing-stats">
      <h2>Stats</h2>

      <table class="landing-table stats-table">
        <thead>
          <tr>
            <th scope="col">Total Posts</th>
            <th scope="col">This Week</th>
            <th scope="col">Active Content</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><%= @stats.total_posts %></td>
            <td><%= @stats.posts_week %></td>
            <td><%= @stats.active_content %></td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false

  defp recent_post_board_label(post, true) do
    if present_text?(post.board_subtitle),
      do: post.board_subtitle,
      else: recent_post_board_uri_label(post)
  end

  defp recent_post_board_label(post, false), do: recent_post_board_uri_label(post)

  defp recent_post_board_uri_label(post), do: "/#{post.board_uri}/"

  embed_templates "page_html/*"
end
