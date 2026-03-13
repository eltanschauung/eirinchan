defmodule EirinchanWeb.ThemeController do
  use EirinchanWeb, :controller

  alias EirinchanWeb.ThemeRegistry

  def update(conn, %{"theme" => theme} = params) do
    selected_theme =
      if ThemeRegistry.valid_theme?(theme) do
        theme
      else
        ThemeRegistry.default_theme()
      end

    return_to = safe_return_to(params["return_to"])
    board = normalize_board(params["board"])

    conn =
      if board do
        board_themes =
          conn.cookies["board_themes"]
          |> decode_board_themes_cookie()
          |> Map.put(board, selected_theme)

        put_resp_cookie(conn, "board_themes", Jason.encode!(board_themes),
          max_age: 60 * 60 * 24 * 365,
          path: "/"
        )
      else
        put_resp_cookie(conn, "theme", selected_theme, max_age: 60 * 60 * 24 * 365, path: "/")
      end

    redirect(conn, to: return_to)
  end

  defp decode_board_themes_cookie(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = decoded} -> decoded
      _ -> %{}
    end
  end

  defp decode_board_themes_cookie(_value), do: %{}

  defp normalize_board(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_board(_value), do: nil

  defp safe_return_to(nil), do: "/"
  defp safe_return_to(""), do: "/"

  defp safe_return_to(path) do
    if String.starts_with?(path, "/") do
      path
    else
      "/"
    end
  end
end
