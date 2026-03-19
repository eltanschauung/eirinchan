defmodule EirinchanWeb.BrowserPageComponents do
  use EirinchanWeb, :html

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :back_href, :string, default: nil
  attr :back_label, :string, default: nil
  slot :subtitle_content

  def page_header(assigns) do
    ~H"""
    <header>
      <h1><%= @title %></h1>
      <div class="subtitle">
        <%= if @subtitle do %>
          <%= @subtitle %>
        <% end %>
        <%= render_slot(@subtitle_content) %>
        <p :if={@back_href && @back_label}><a href={@back_href}><%= @back_label %></a></p>
      </div>
    </header>
    """
  end

  attr :text, :string, required: true
  attr :class_name, :string, default: "unimportant"
  attr :centered, :boolean, default: true
  attr :parenthesize, :boolean, default: true

  def empty_notice(assigns) do
    ~H"""
    <p class={@class_name} style={if @centered, do: "text-align:center", else: nil}>
      <%= if @parenthesize do %>
        (<%= @text %>)
      <% else %>
        <%= @text %>
      <% end %>
    </p>
    """
  end
end
