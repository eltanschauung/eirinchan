defmodule Eirinchan.FormattingPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]
  alias Eirinchan.LegacyPageBody
  alias Eirinchan.WhaleStickers.Defaults, as: WhaleStickerDefaults

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
    |> refresh_sticker_columns(sticker_entries)
    |> stabilize_sticker_images(sticker_entries)
  end

  defp refresh_sticker_columns(html, sticker_entries) when is_binary(html) do
    with {:ok, nodes} <- Floki.parse_fragment(html),
         {:ok, default_nodes} <- Floki.parse_fragment(default_body(sticker_entries)),
         [replacement] <- Floki.find(default_nodes, ".formatting-sticker-columns"),
         [_existing | _] <- Floki.find(nodes, ".formatting-sticker-columns") do
      nodes
      |> Floki.traverse_and_update(fn
        {"div", attrs, _children} = node ->
          if has_class?(attrs, "formatting-sticker-columns"), do: replacement, else: node

        node ->
          node
      end)
      |> Floki.raw_html()
    else
      _ -> html
    end
  end

  defp refresh_sticker_columns(html, _sticker_entries), do: html

  defp has_class?(attrs, class) do
    attrs
    |> Enum.find_value(fn {name, value} -> if name == "class", do: value end)
    |> to_string()
    |> String.split()
    |> Enum.member?(class)
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
    stickers_for_column(sticker_entries, :left)
  end

  defp right_stickers(sticker_entries) do
    stickers_for_column(sticker_entries, :right)
  end

  defp stickers_for_column(sticker_entries, column) do
    columns = WhaleStickerDefaults.formatting_columns()
    column_tokens = Map.fetch!(columns, column)

    column_by_token =
      for {configured_column, tokens} <- columns,
          token <- tokens,
          into: %{},
          do: {token, configured_column}

    order_by_token =
      column_tokens
      |> Enum.with_index()
      |> Map.new()

    sticker_entries
    |> Enum.filter(fn sticker ->
      Map.get(column_by_token, sticker_token(sticker), :right) == column
    end)
    |> Enum.sort_by(fn sticker ->
      {Map.get(order_by_token, sticker_token(sticker), 10_000), sticker_token(sticker)}
    end)
  end

  defp sticker_token(%{token: token}) when is_binary(token), do: token
  defp sticker_token(%{"token" => token}) when is_binary(token), do: token
  defp sticker_token(_sticker), do: ""
end
