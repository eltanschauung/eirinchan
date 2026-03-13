defmodule EirinchanWeb.Plugs.FetchBrowserTimezone do
  @moduledoc false

  import Plug.Conn

  @cookie_name "timezone"
  @offset_cookie_name "timezone_offset"
  @timezone_regex ~r/\A[A-Za-z0-9_+\-\/]{1,128}\z/
  @min_offset_minutes -840
  @max_offset_minutes 840

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = ensure_cookies(conn)

    conn
    |> assign(:browser_timezone, normalize_timezone(conn.cookies[@cookie_name]))
    |> assign(:browser_timezone_offset_minutes, normalize_offset(conn.cookies[@offset_cookie_name]))
  end

  defp ensure_cookies(%Plug.Conn{cookies: %Plug.Conn.Unfetched{}} = conn), do: fetch_cookies(conn)
  defp ensure_cookies(conn), do: conn

  defp normalize_timezone(value) when is_binary(value) do
    timezone = String.trim(value)

    cond do
      timezone == "" ->
        nil

      not Regex.match?(@timezone_regex, timezone) ->
        nil

      true ->
        timezone
    end
  end

  defp normalize_timezone(_value), do: nil

  defp normalize_offset(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {minutes, ""} when minutes >= @min_offset_minutes and minutes <= @max_offset_minutes -> minutes
      _ -> nil
    end
  end

  defp normalize_offset(_value), do: nil
end
