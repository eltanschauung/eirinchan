defmodule EirinchanWeb.SearchHTML do
  use EirinchanWeb, :html
  import EirinchanWeb.BrowserPostComponents
  import EirinchanWeb.BrowserPageComponents

  embed_templates "search_html/*"

  def search_page_url(params, page) do
    "/search.php?" <> Plug.Conn.Query.encode(Map.put(params, "page", page))
  end

  def search_value(nil), do: ""
  def search_value(%Date{} = date), do: Date.to_iso8601(date)
  def search_value(value), do: to_string(value)

  def checked?(actual, expected), do: actual == expected

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :inputmode, :string, default: nil
  attr :maxlength, :string, default: nil

  def search_field(assigns) do
    ~H"""
    <label class="search-field">
      <span><%= @label %></span>
      <input
        name={@name}
        type={@type}
        value={search_value(@value)}
        inputmode={@inputmode}
        maxlength={@maxlength}
        autocomplete="off"
      />
    </label>
    """
  end

  attr :title, :string, required: true
  attr :boards, :list, required: true
  attr :selected, :any, required: true
  attr :id, :string, required: true

  def board_choices(assigns) do
    ~H"""
    <fieldset class="search-board-choices" id={"search-#{@id}"}>
      <legend class="search-choice-heading">
        <strong><%= @title %></strong>
        <button type="button" data-uncheck={"search-#{@id}"}>Uncheck all</button>
      </legend>
      <div class="search-board-grid">
        <label :for={board <- @boards}>
          <input type="checkbox" name="boards[]" value={board.uri} checked={MapSet.member?(@selected, board.uri)} />
          /<%= board.uri %>/
        </label>
      </div>
    </fieldset>
    """
  end

  attr :legend, :string, required: true
  attr :name, :string, required: true
  attr :selected, :string, required: true
  attr :options, :list, required: true

  def radio_group(assigns) do
    ~H"""
    <fieldset class="search-radio-group">
      <legend class="visually-hidden"><%= @legend %></legend>
      <label :for={{value, label} <- @options}>
        <input type="radio" name={@name} value={value} checked={checked?(@selected, value)} />
        <%= label %>
      </label>
    </fieldset>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :params, :map, required: true

  def search_pagination(assigns) do
    assigns = assign(assigns, :pages, pagination_window(assigns.page, assigns.total_pages))

    ~H"""
    <nav class="search-pagination" aria-label="Search result pages">
      <a :if={@page > 1} href={search_page_url(@params, @page - 1)}>Previous</a>
      <%= for page <- @pages do %>
        <span :if={page == :gap}>&hellip;</span>
        <strong :if={page == @page}><%= page %></strong>
        <a :if={is_integer(page) && page != @page} href={search_page_url(@params, page)}><%= page %></a>
      <% end %>
      <a :if={@page < @total_pages} href={search_page_url(@params, @page + 1)}>Next</a>
    </nav>
    """
  end

  defp pagination_window(page, total_pages) do
    pages =
      [1, total_pages]
      |> Kernel.++(Enum.to_list(max(page - 2, 1)..min(page + 2, total_pages)))
      |> Enum.uniq()
      |> Enum.sort()

    pages
    |> Enum.reduce([], fn current, acc ->
      case List.last(acc) do
        previous when is_integer(previous) and current - previous > 1 -> acc ++ [:gap, current]
        _ -> acc ++ [current]
      end
    end)
  end

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  def search_post(assigns) do
    ~H"""
    <.browser_post
      post={@post}
      board={@board}
      thread={@thread}
      config={@config}
      show_reply_link={true}
      quote_mode={:navigate}
    />
    """
  end
end
