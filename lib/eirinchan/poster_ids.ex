defmodule Eirinchan.PosterIds do
  @moduledoc false

  @default_length 5
  @max_length 40

  def enabled?(config) when is_map(config), do: Map.get(config, :poster_ids, false) == true
  def enabled?(_config), do: false

  def poster_id(post, config) when is_map(post) and is_map(config) do
    with true <- enabled?(config),
         ip_subnet when is_binary(ip_subnet) and ip_subnet != "" <- Map.get(post, :ip_subnet),
         thread_key when is_integer(thread_key) <- thread_key(post) do
      salt = config |> Map.get(:secure_trip_salt, "") |> to_string()
      length = normalize_length(Map.get(config, :poster_id_length, @default_length))

      inner =
        :sha
        |> :crypto.hash("#{ip_subnet}#{salt}#{thread_key}")
        |> Base.encode16(case: :lower)

      :sha
      |> :crypto.hash(inner <> salt)
      |> Base.encode16(case: :lower)
      |> binary_part(0, length)
    else
      _ -> nil
    end
  end

  def poster_id(_post, _config), do: nil

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
