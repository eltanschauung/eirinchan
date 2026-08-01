defmodule EirinchanWeb.CacheControl do
  @moduledoc false

  @one_month 60 * 60 * 24 * 30
  @one_minute 60
  @ten_minutes 60 * 10
  @one_year 60 * 60 * 24 * 365
  @versioned_asset_extensions ~w(.css .gif .ico .jpeg .jpg .js .png .svg .webp)
  @version_pattern ~r/\A[A-Za-z0-9._:-]{1,128}\z/

  def static_headers(conn) do
    [{"cache-control", cache_control_for_request(conn.request_path, conn.query_string)}]
  end

  def cache_control_for_request(path, query_string)
      when is_binary(path) and is_binary(query_string) do
    if versioned_static_asset?(path, query_string) do
      immutable(@one_year)
    else
      cache_control_for_path(path)
    end
  end

  def cache_control_for_path(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "/stylesheets/assets/") ->
        public(@one_minute)

      true ->
        case path |> Path.extname() |> String.downcase() do
          ".gif" -> public(@one_month)
          ".png" -> public(@one_month)
          ".jpg" -> public(@one_month)
          ".jpeg" -> public(@one_month)
          ".webp" -> public(@one_month)
          ".css" -> public(@one_minute)
          ".js" -> public(@one_minute)
          ".svg" -> immutable(@one_year)
          ".ico" -> immutable(@one_year)
          ".txt" -> public(@ten_minutes)
          ".zip" -> public(@ten_minutes)
          _ -> public(@ten_minutes)
        end
    end
  end

  def cache_control_for_upload_bucket("thumb"), do: immutable(@one_year)
  def cache_control_for_upload_bucket("src"), do: public(@one_month)
  def cache_control_for_upload_bucket(_bucket), do: public(@ten_minutes)

  defp versioned_static_asset?(path, query_string) do
    (path |> Path.extname() |> String.downcase()) in @versioned_asset_extensions and
      valid_version?(query_string)
  end

  defp valid_version?(query_string) do
    query_string
    |> URI.decode_query()
    |> Map.get("v")
    |> case do
      value when is_binary(value) -> Regex.match?(@version_pattern, value)
      _ -> false
    end
  rescue
    ArgumentError -> false
  end

  defp public(seconds), do: "public, max-age=#{seconds}"
  defp immutable(seconds), do: "public, max-age=#{seconds}, immutable"
end
