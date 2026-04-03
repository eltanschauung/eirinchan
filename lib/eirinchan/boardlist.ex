defmodule Eirinchan.Boardlist do
  @moduledoc """
  Instance-configurable boardlist groups.
  """

  alias Eirinchan.Settings

  @variants [:desktop, :mobile]

  @spec configured_groups(list(), keyword()) :: list()
  def configured_groups(boards, opts \\ []) when is_list(boards) do
    Settings.current_instance_config()
    |> Map.get(:boardlist)
    |> configured_groups_from_value(boards, opts)
  end

  @spec configured_groups_from_value(term(), list(), keyword()) :: list()
  def configured_groups_from_value(value, boards, opts \\ []) when is_list(boards) do
    variant = normalize_variant(opts)

    value
    |> normalize_variants_for_runtime(boards)
    |> Map.get(variant)
    |> case do
      groups when is_list(groups) and groups != [] -> groups
      _ -> default_groups(boards)
    end
  end

  @spec update_from_json(binary(), list()) :: {:ok, map()} | {:error, :invalid_json}
  def update_from_json(raw_json, boards) when is_binary(raw_json) and is_list(boards) do
    with {:ok, decoded} <- Jason.decode(raw_json, objects: :ordered_objects),
         {:ok, variants} <- parse_variants_for_update(decoded, boards),
         :ok <- persist(variants) do
      {:ok, variants}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      false -> {:error, :invalid_json}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_json}
    end
  end

  @spec encode_for_edit(list()) :: binary()
  def encode_for_edit(boards) when is_list(boards) do
    variants =
      Settings.current_instance_config()
      |> Map.get(:boardlist)
      |> normalize_variants_for_runtime(boards)

    [
      "{\n",
      ~s(  "desktop": ),
      encode_groups(Map.get(variants, :desktop, default_groups(boards)), 2),
      ",\n",
      ~s(  "mobile": ),
      encode_groups(Map.get(variants, :mobile, default_groups(boards)), 2),
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  defp parse_variants_for_update(decoded, boards) do
    cond do
      match?(%Jason.OrderedObject{}, decoded) ->
        decoded
        |> ordered_values()
        |> decode_variant_object(boards)

      variant_object?(decoded) ->
        decode_variant_object(decoded, boards)

      is_list(decoded) ->
        with {:ok, groups} <- decode_groups(decoded, boards) do
          {:ok, %{desktop: groups, mobile: groups}}
        end

      true ->
        {:error, :invalid_json}
    end
  end

  defp decode_variant_object(entries, boards) do
    Enum.reduce_while(entries, {:ok, %{}}, fn
      {key, value}, {:ok, acc} ->
        case normalize_variant_key(key) do
          nil ->
            {:halt, {:error, :invalid_json}}

          variant ->
            case decode_groups(value, boards) do
              {:ok, groups} -> {:cont, {:ok, Map.put(acc, variant, groups)}}
              error -> {:halt, error}
            end
        end

      _, _acc ->
        {:halt, {:error, :invalid_json}}
    end)
    |> case do
      {:ok, variants} when map_size(variants) > 0 ->
        desktop = Map.get(variants, :desktop) || Map.get(variants, :mobile) || default_groups(boards)
        mobile = Map.get(variants, :mobile) || Map.get(variants, :desktop) || default_groups(boards)
        {:ok, %{desktop: desktop, mobile: mobile}}

      _ ->
        {:error, :invalid_json}
    end
  end

  defp decode_groups(groups, boards) when is_list(groups) do
    normalized =
      groups
      |> Enum.map(&normalize_group(&1, boards))
      |> Enum.reject(&(&1 == []))

    if normalized != [] and Enum.all?(normalized, &(is_list(&1) and &1 != [])) do
      {:ok, normalized}
    else
      {:error, :invalid_json}
    end
  end

  defp decode_groups(_groups, _boards), do: {:error, :invalid_json}

  defp encode_group(group) when is_list(group) do
    if Enum.all?(group, &(Map.get(&1, :kind, :link) == :board)) do
      Jason.encode_to_iodata!(Enum.map(group, & &1.label), pretty: true)
    else
      [
        "{",
        Enum.intersperse(
          Enum.map(group, fn link ->
            [Jason.encode_to_iodata!(link.label), ": ", Jason.encode_to_iodata!(link.href)]
          end),
          ", "
        ),
        "}"
      ]
    end
  end

  defp encode_groups(groups, indent) when is_list(groups) do
    outer_indent = String.duplicate(" ", indent)

    rendered_groups =
      groups
      |> Enum.map(&indent_block(encode_group(&1), indent + 2))
      |> Enum.intersperse(",\n")

    ["[\n", rendered_groups, "\n", outer_indent, "]"]
  end

  defp indent_block(iodata, indent) do
    prefix = String.duplicate(" ", indent)

    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> prefix <> line
    end)
  end

  defp persist(groups) do
    config = Settings.current_instance_config()
    Settings.persist_instance_config(Map.put(config, :boardlist, groups))
  end

  defp normalize_variants_for_runtime(nil, boards), do: %{desktop: default_groups(boards), mobile: default_groups(boards)}

  defp normalize_variants_for_runtime(%Jason.OrderedObject{} = groups, boards) do
    groups
    |> ordered_values()
    |> normalize_variants_for_runtime(boards)
  end

  defp normalize_variants_for_runtime(groups, boards) when is_list(groups) do
    if variant_object?(groups) do
      case decode_variant_object(groups, boards) do
        {:ok, variants} -> variants
        _ -> %{desktop: default_groups(boards), mobile: default_groups(boards)}
      end
    else
      normalized =
        groups
        |> Enum.map(&normalize_group(&1, boards))
        |> Enum.reject(&(&1 == []))

      groups = if normalized == [], do: default_groups(boards), else: normalized
      %{desktop: groups, mobile: groups}
    end
  end

  defp normalize_variants_for_runtime(%{} = groups, boards) do
    desktop =
      Map.get(groups, :desktop) ||
        Map.get(groups, "desktop") ||
        Map.get(groups, :mobile) ||
        Map.get(groups, "mobile")

    mobile =
      Map.get(groups, :mobile) ||
        Map.get(groups, "mobile") ||
        Map.get(groups, :desktop) ||
        Map.get(groups, "desktop")

    %{
      desktop: runtime_variant_groups(desktop, boards),
      mobile: runtime_variant_groups(mobile, boards)
    }
  end

  defp normalize_variants_for_runtime(_groups, boards),
    do: %{desktop: default_groups(boards), mobile: default_groups(boards)}

  defp runtime_variant_groups(value, boards) when is_list(value) do
    value
    |> Enum.map(&normalize_group(&1, boards))
    |> Enum.reject(&(&1 == []))
    |> case do
      [] -> default_groups(boards)
      groups -> groups
    end
  end

  defp runtime_variant_groups(_value, boards), do: default_groups(boards)

  defp normalize_variant(opts) do
    cond do
      Keyword.get(opts, :variant) in @variants ->
        Keyword.fetch!(opts, :variant)

      Keyword.get(opts, :mobile_client?, false) ->
        :mobile

      true ->
        :desktop
    end
  end

  defp variant_object?(value) when is_list(value) do
    value != [] and
      Enum.all?(value, fn
        {key, groups} -> normalize_variant_key(key) != nil and is_list(groups)
        _ -> false
      end)
  end

  defp variant_object?(%Jason.OrderedObject{} = value), do: value |> ordered_values() |> variant_object?()
  defp variant_object?(_value), do: false

  defp normalize_variant_key("desktop"), do: :desktop
  defp normalize_variant_key(:desktop), do: :desktop
  defp normalize_variant_key("mobile"), do: :mobile
  defp normalize_variant_key(:mobile), do: :mobile
  defp normalize_variant_key(_key), do: nil

  defp default_groups(boards) do
    [
      Enum.map(boards, fn board ->
        %{label: board.uri, href: "/#{board.uri}/index.html", title: board.title, kind: :board}
      end),
      [%{href: "/", label: "Home", title: "Home", kind: :link}]
    ]
    |> Enum.reject(&(&1 == []))
  end

  defp normalize_group(group, boards) when is_list(group) do
    cond do
      Enum.all?(group, &match?({key, _value} when is_binary(key), &1)) ->
        group
        |> Enum.map(&normalize_pair(&1, boards))
        |> Enum.reject(&is_nil/1)

      true ->
        group
        |> Enum.map(&normalize_item(&1, boards))
        |> Enum.reject(&is_nil/1)
    end
  end

  defp normalize_group(%Jason.OrderedObject{} = group, boards) do
    group
    |> ordered_values()
    |> Enum.map(&normalize_pair(&1, boards))
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_group(group, boards) when is_map(group) do
    group
    |> Enum.map(&normalize_pair(&1, boards))
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_group(_group, _boards), do: []

  defp normalize_item(item, boards) when is_binary(item) do
    board =
      Enum.find(boards, fn board ->
        board.uri == String.trim(item)
      end)

    label = String.trim(item)

    if label == "" do
      nil
    else
      %{
        label: label,
        href: "/#{label}/index.html",
        title: (board && board.title) || label,
        kind: :board
      }
    end
  end

  defp normalize_item(%{} = item, boards) do
    label = Map.get(item, "label") || Map.get(item, :label)
    href = Map.get(item, "href") || Map.get(item, :href)
    title = Map.get(item, "title") || Map.get(item, :title)
    kind = Map.get(item, "kind") || Map.get(item, :kind)

    cond do
      is_binary(label) and is_binary(href) ->
        normalized_label = String.trim(label)
        normalized_href = String.trim(href)
        normalized_title = normalize_optional_title(title, normalized_label, boards)

        if normalized_label == "" or normalized_href == "" do
          nil
        else
          %{
            label: normalized_label,
            href: normalized_href,
            title: normalized_title,
            kind: normalize_kind(kind, normalized_href, boards)
          }
        end

      true ->
        nil
    end
  end

  defp normalize_item(_item, _boards), do: nil

  defp normalize_pair({label, href}, boards) when is_binary(label) do
    normalized_label = String.trim(label)
    normalized_href = href |> to_string() |> String.trim()

    cond do
      normalized_label == "" or normalized_href == "" ->
        nil

      true ->
        board = Enum.find(boards, &(&1.uri == normalized_label))

        %{
          label: normalized_label,
          href: normalized_href,
          title: (board && board.title) || normalized_label,
          kind: :link
        }
    end
  end

  defp normalize_pair(_pair, _boards), do: nil

  defp normalize_optional_title(value, default, boards) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: derive_title(default, boards), else: trimmed
  end

  defp normalize_optional_title(_value, default, boards), do: derive_title(default, boards)

  defp derive_title(label, boards) do
    case Enum.find(boards, &(&1.uri == label)) do
      nil -> label
      board -> board.title
    end
  end

  defp normalize_kind(kind, href, boards) do
    case kind do
      "board" -> :board
      :board -> :board
      "link" -> :link
      :link -> :link
      _ -> infer_kind_from_href(href, boards)
    end
  end

  defp infer_kind_from_href(href, boards) do
    if Enum.any?(boards, fn board -> href == "/#{board.uri}/index.html" end) do
      :board
    else
      :link
    end
  end

  defp ordered_values(%Jason.OrderedObject{values: values}), do: values
end
