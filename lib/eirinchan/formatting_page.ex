defmodule Eirinchan.FormattingPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]
  alias Eirinchan.LegacyPageBody

  @left_column_count 52
  @live_sticker_order ~w(
    gem concern2 milk ninacry smell tempura tenfact grimace wow ahegao nvke headphones cinema
    masaka2 krillin rika ominous kanmarisa mask banjo pout notes elated dogshit mid2 gojo
    angry2 17 yeah vibe thumb waka damn yikes cackle whale glasses fact fact2 thinking bruh
    unyu angry lmao dora boom gasp kys bald meow rofl pensive fact3 pensive2 horse kasawalk
    cum imhungry mindbreak2 scaremu number wemywhale cinema2 bbccry gn ramen2 gokek ramen
    wink mindbreak masaka sip seppuku bruh2 lebron peak peak2 mid dance drool no brain2 poop
    theory lambda shock shock2 upvote youmu pipe happy pog baby kek crawl neutral pray frown
    cath concern gay sign fear brain feelio
  )

  def default_body(sticker_entries \\ []) do
    render_to_string(EirinchanWeb.PageHTML, "formatting_body", "html",
      left_stickers: left_stickers(sticker_entries),
      right_stickers: right_stickers(sticker_entries)
    )
  end

  def normalize_body(html, sticker_entries \\ [])

  def normalize_body(html, sticker_entries) do
    html
    |> LegacyPageBody.normalize(fn -> default_body(sticker_entries) end,
      content_regex:
        ~r|(<div class="box-wrap(?: faq-page-shell)?(?: formatting-page-shell)?">.*?</div>\s*)<footer|s,
      strip: [:style]
    )
    |> stabilize_sticker_images(sticker_entries)
  end

  defp stabilize_sticker_images(html, sticker_entries) when is_binary(html) do
    dimensions_by_path = sticker_dimensions_by_path(sticker_entries)

    case Floki.parse_fragment(html) do
      {:ok, nodes} ->
        nodes
        |> stabilize_nodes(dimensions_by_path)
        |> Floki.raw_html()

      {:error, _reason} ->
        html
    end
  end

  defp stabilize_sticker_images(html, _sticker_entries), do: html

  defp sticker_dimensions_by_path(sticker_entries) when is_list(sticker_entries) do
    Enum.reduce(sticker_entries, %{}, fn
      %{path: path, width: width, height: height}, dimensions
      when is_binary(path) and is_integer(width) and width > 0 and is_integer(height) and
             height > 0 ->
        Map.put(dimensions, path, {width, height})

      _sticker, dimensions ->
        dimensions
    end)
  end

  defp sticker_dimensions_by_path(_sticker_entries), do: %{}

  defp stabilize_nodes(nodes, dimensions_by_path) do
    Enum.map(nodes, &stabilize_node(&1, dimensions_by_path))
  end

  defp stabilize_node({tag, attrs, children}, dimensions_by_path) do
    attrs =
      if String.downcase(tag) == "img" do
        stabilize_image_attributes(attrs, dimensions_by_path)
      else
        attrs
      end

    {tag, attrs, stabilize_nodes(children, dimensions_by_path)}
  end

  defp stabilize_node(node, _dimensions_by_path), do: node

  defp stabilize_image_attributes(attrs, dimensions_by_path) do
    src =
      Enum.find_value(attrs, fn {name, value} -> if String.downcase(name) == "src", do: value end)

    case Map.get(dimensions_by_path, src) do
      {width, height} ->
        attrs
        |> put_attribute("width", width)
        |> put_attribute("height", height)
        |> put_attribute("loading", "eager")
        |> put_attribute("decoding", "async")

      nil ->
        attrs
    end
  end

  defp put_attribute(attrs, name, value) do
    Enum.reject(attrs, fn {attribute, _value} -> String.downcase(attribute) == name end) ++
      [{name, to_string(value)}]
  end

  defp left_stickers(sticker_entries) do
    sticker_entries
    |> ordered_stickers()
    |> Enum.take(@left_column_count)
  end

  defp right_stickers(sticker_entries) do
    sticker_entries
    |> ordered_stickers()
    |> Enum.drop(@left_column_count)
  end

  defp ordered_stickers(sticker_entries) do
    order_map =
      @live_sticker_order
      |> Enum.with_index()
      |> Map.new()

    sticker_entries
    |> Enum.sort_by(fn sticker ->
      {Map.get(order_map, sticker_token(sticker), 10_000), sticker_token(sticker)}
    end)
  end

  defp sticker_token(%{token: token}) when is_binary(token), do: token
  defp sticker_token(%{"token" => token}) when is_binary(token), do: token
  defp sticker_token(_sticker), do: ""
end
