defmodule EirinchanWeb.CacheControl do
  @moduledoc false

  @one_month 60 * 60 * 24 * 30
  @one_minute 60
  @ten_minutes 60 * 10
  @one_year 60 * 60 * 24 * 365

  def static_headers(conn) do
    [{"cache-control", cache_control_for_path(conn.request_path)}]
  end

  def cache_control_for_path(path) when is_binary(path) do
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

  defp public(seconds), do: "public, max-age=#{seconds}"
  defp immutable(seconds), do: "public, max-age=#{seconds}, immutable"
end
