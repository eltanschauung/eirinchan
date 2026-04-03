defmodule Eirinchan.PosterIds do
  @moduledoc false

  alias Eirinchan.AprilFoolsTeams

  @default_length 5
  @max_length 40
  @colours [
    "#800000",
    "#6B1F33",
    "#7E243C",
    "#A52A2A",
    "#8B0000",
    "#C71585",
    "#8B008B",
    "#4B0082",
    "#483D8B",
    "#4169E1",
    "#4682B4",
    "#2F4F4F",
    "#556B2F",
    "#6B8E23",
    "#8FBC8F",
    "#3CB371",
    "#2E8B57",
    "#20B2AA",
    "#008080",
    "#708090",
    "#696969",
    "#A9A9A9",
    "#BC8F8F",
    "#CD853F",
    "#D2691E",
    "#B8860B",
    "#DAA520",
    "#BDB76B",
    "#F4A460",
    "#DEB887",
    "#D8C1A2",
    "#C0A080"
  ]

  def enabled?(config) when is_map(config), do: Map.get(config, :poster_ids, false) == true
  def enabled?(_config), do: false

  def poster_id(post, config) when is_map(post) and is_map(config) do
    case badge(post, config) do
      %{label: label} when is_binary(label) and label != "" -> label
      _ -> nil
    end
  end

  def poster_id(_post, _config), do: nil

  def badge(post, config) when is_map(post) and is_map(config) do
    cond do
      AprilFoolsTeams.enabled?(config) ->
        april_fools_badge(post)

      enabled?(config) ->
        standard_badge(post, config)

      true ->
        nil
    end
  end

  def badge(_post, _config), do: nil

  defp april_fools_badge(%{} = post) do
    case AprilFoolsTeams.badge(post) do
      %{label: label, html_colour: html_colour, text_colour: text_colour} ->
        %{
          label: label,
          class: "poster_id april_fools_team",
          style:
            "background-color: #{html_colour}; color: #{text_colour}; padding: 0 0.35em; border-radius: 6px;"
        }

      _ ->
        nil
    end
  end

  defp april_fools_badge(_post), do: nil

  defp standard_badge(post, _config) do
    case persisted_poster_id(post) do
      label when is_binary(label) ->
        standard_badge_payload(label)

      _ ->
        nil
    end
  end

  defp standard_badge_payload(label) do
    html_colour = Enum.at(@colours, :erlang.phash2(label, length(@colours)))

    %{
      label: label,
      class: "poster_id standard_poster_id",
      style:
        "background-color: #{html_colour}; color: #{text_colour(html_colour)}; padding: 0 0.35em; border-radius: 6px;"
    }
  end

  def build_label(identity, thread_key, config)
      when is_binary(identity) and identity != "" and is_integer(thread_key) do
    salt = config |> Map.get(:secure_trip_salt, "") |> to_string()
    length = normalize_length(Map.get(config, :poster_id_length, @default_length))

    inner =
      :sha
      |> :crypto.hash("#{identity}#{salt}#{thread_key}")
      |> Base.encode16(case: :lower)

    :sha
    |> :crypto.hash(inner <> salt)
    |> Base.encode16(case: :lower)
    |> binary_part(0, length)
  end

  def build_label(_identity, _thread_key, _config), do: nil

  defp persisted_poster_id(%{poster_id: label}) when is_binary(label) and label != "", do: label
  defp persisted_poster_id(_post), do: nil

  defp text_colour("#" <> hex) when byte_size(hex) == 6 do
    <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex
    {r, ""} = Integer.parse(r, 16)
    {g, ""} = Integer.parse(g, 16)
    {b, ""} = Integer.parse(b, 16)
    luma = round(0.299 * r + 0.587 * g + 0.114 * b)
    if luma >= 150, do: "#000000", else: "#ffffff"
  end

  defp text_colour(_hex), do: "#ffffff"

  defp normalize_length(length) when is_integer(length) do
    length
    |> max(1)
    |> min(@max_length)
  end

  defp normalize_length(length) when is_binary(length) do
    case Integer.parse(String.trim(length)) do
      {parsed, _rest} -> normalize_length(parsed)
      :error -> @default_length
    end
  end

  defp normalize_length(_length), do: @default_length
end
