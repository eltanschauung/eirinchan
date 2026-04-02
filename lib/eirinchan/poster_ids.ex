defmodule Eirinchan.PosterIds do
  @moduledoc false

  alias Eirinchan.AprilFoolsTeams

  @default_length 5
  @max_length 40

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

  defp standard_badge(post, config) do
    with ip_subnet when is_binary(ip_subnet) and ip_subnet != "" <- Map.get(post, :ip_subnet),
         thread_key when is_integer(thread_key) <- thread_key(post) do
      salt = config |> Map.get(:secure_trip_salt, "") |> to_string()
      length = normalize_length(Map.get(config, :poster_id_length, @default_length))

      inner =
        :sha
        |> :crypto.hash("#{ip_subnet}#{salt}#{thread_key}")
        |> Base.encode16(case: :lower)

      label =
        :sha
        |> :crypto.hash(inner <> salt)
        |> Base.encode16(case: :lower)
        |> binary_part(0, length)

      %{label: label, class: "poster_id", style: nil}
    else
      _ -> nil
    end
  end

  defp thread_key(%{thread_id: thread_id}) when is_integer(thread_id), do: thread_id
  defp thread_key(%{id: id}) when is_integer(id), do: id
  defp thread_key(_post), do: nil

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
