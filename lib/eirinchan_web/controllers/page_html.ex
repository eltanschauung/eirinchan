defmodule EirinchanWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use EirinchanWeb, :html
  import EirinchanWeb.BrowserPostComponents

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
                    data-board-uri={watch.board_uri}
                    data-thread-id={watch.thread_id}
                    data-watch-url={"/watcher/" <> watch.board_uri <> "/" <> Integer.to_string(watch.thread_id)}
                    data-unwatch-url={"/watcher/" <> watch.board_uri <> "/" <> Integer.to_string(watch.thread_id)}
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

  embed_templates "page_html/*"
end
