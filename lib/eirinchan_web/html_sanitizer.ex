defmodule EirinchanWeb.HtmlSanitizer do
  @moduledoc false

  @allowed_tags ~w(
    a abbr article aside b blockquote br caption code col colgroup dd del details div dl dt em
    figcaption figure footer h1 h2 h3 h4 h5 h6 header hr i img kbd li main mark nav ol p pre q
    s section small span strong sub summary sup table tbody td tfoot th thead tr u ul
  )

  @drop_with_contents ~w(base button embed form iframe input link math meta object script select
                          style svg template textarea)

  @global_attributes ~w(class id title lang dir role aria-label aria-hidden style)
  @allowed_style_properties ~w(color background-color text-align font-weight font-style text-decoration)
  @tag_attributes %{
    "a" => ~w(href target rel),
    "img" => ~w(src alt width height loading),
    "col" => ~w(span),
    "td" => ~w(colspan rowspan headers),
    "th" => ~w(colspan rowspan headers scope)
  }

  def sanitize_fragment(nil), do: ""

  def sanitize_fragment(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> nodes |> sanitize_nodes() |> Floki.raw_html() |> String.replace("&#39;", "'")
      {:error, _reason} -> ""
    end
  end

  def sanitize_fragment(other), do: sanitize_fragment(to_string(other))

  defp sanitize_nodes(nodes), do: Enum.flat_map(nodes, &sanitize_node/1)

  defp sanitize_node(text) when is_binary(text), do: [text]

  defp sanitize_node({tag, attrs, children}) when is_binary(tag) do
    normalized_tag = String.downcase(tag)

    cond do
      normalized_tag in @drop_with_contents -> []
      normalized_tag in @allowed_tags ->
        [{normalized_tag, sanitize_attributes(normalized_tag, attrs), sanitize_nodes(children)}]

      true -> sanitize_nodes(children)
    end
  end

  defp sanitize_node(_other), do: []

  defp sanitize_attributes(tag, attrs) do
    allowed = @global_attributes ++ Map.get(@tag_attributes, tag, [])

    attrs
    |> Enum.flat_map(fn {name, value} ->
      normalized_name = String.downcase(name)

      if normalized_name in allowed and safe_attribute_value?(value) do
        case sanitize_attribute(tag, normalized_name, value) do
          nil -> []
          sanitized -> [{normalized_name, sanitized}]
        end
      else
        []
      end
    end)
    |> secure_external_link(tag)
  end

  defp sanitize_attribute("a", "href", value), do: sanitize_url(value, :link)
  defp sanitize_attribute("img", "src", value), do: sanitize_url(value, :image)
  defp sanitize_attribute(_tag, "style", value), do: sanitize_style(value)
  defp sanitize_attribute("a", "target", "_blank"), do: "_blank"
  defp sanitize_attribute("a", "target", _value), do: "_self"

  defp sanitize_attribute("a", "rel", value) do
    value
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.map(&String.downcase/1)
    |> Enum.filter(&(&1 in ~w(nofollow noopener noreferrer ugc)))
    |> Enum.uniq()
    |> Enum.join(" ")
  end

  defp sanitize_attribute(_tag, _name, value), do: value

  defp sanitize_style(value) do
    declarations =
      value
      |> String.split(";", trim: true)
      |> Enum.flat_map(fn declaration ->
        case String.split(declaration, ":", parts: 2) do
          [property, raw_value] ->
            property = property |> String.trim() |> String.downcase()
            raw_value = String.trim(raw_value)

            if property in @allowed_style_properties and safe_style_value?(raw_value) do
              ["#{property}:#{raw_value}"]
            else
              []
            end

          _other ->
            []
        end
      end)

    if declarations == [], do: nil, else: Enum.join(declarations, ";")
  end

  defp safe_style_value?(value) do
    Regex.match?(~r/\A[#(),.%\sa-z0-9-]+\z/i, value) and
      not String.contains?(String.downcase(value), ["expression", "url(", "var(", "javascript"])
  end

  defp sanitize_url(value, kind) do
    trimmed = String.trim(value)

    case URI.parse(trimmed) do
      %URI{scheme: nil, host: nil} ->
        if String.starts_with?(trimmed, "//"), do: "#", else: trimmed

      %URI{scheme: scheme} when is_binary(scheme) ->
        case {String.downcase(scheme), kind} do
          {allowed, _kind} when allowed in ["http", "https"] -> trimmed
          {"mailto", :link} -> trimmed
          _other -> "#"
        end

      _other ->
        "#"
    end
  end

  defp secure_external_link(attrs, "a") do
    if Enum.any?(attrs, &match?({"target", "_blank"}, &1)) do
      rel = Enum.find_value(attrs, "", fn
        {"rel", value} -> value
        _attribute -> nil
      end)

      Enum.reject(attrs, &match?({"rel", _value}, &1)) ++ [{"rel", merge_rel(rel)}]
    else
      attrs
    end
  end

  defp secure_external_link(attrs, _tag), do: attrs

  defp merge_rel(rel) do
    rel
    |> String.split(~r/\s+/u, trim: true)
    |> Kernel.++(["noopener", "noreferrer"])
    |> Enum.uniq()
    |> Enum.join(" ")
  end

  defp safe_attribute_value?(value) when is_binary(value) do
    not String.contains?(value, ["\u0000", "\r", "\n"])
  end

  defp safe_attribute_value?(_value), do: false
end
