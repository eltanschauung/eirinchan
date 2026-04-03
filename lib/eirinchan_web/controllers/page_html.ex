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

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false

  embed_templates "page_html/*"
end
