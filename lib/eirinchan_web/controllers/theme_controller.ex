defmodule EirinchanWeb.ThemeController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Settings
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
    board_record = if board, do: Boards.get_board_by_uri(board), else: nil
    forced_theme_identifier = forced_theme(board_record, Settings.current_instance_config())

    conn =
      if forced_theme_identifier do
        conn
      else
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
      end

    redirect(conn, to: return_to)
  end

  defp decode_board_themes_cookie(value) when is_binary(value) do
    decoded_value =
      case URI.decode(value) do
        ^value -> value
        decoded -> decoded
      end

    case Jason.decode(decoded_value) do
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

  defp forced_theme(board, instance_config) do
    board_forced_theme(board) || global_forced_theme(instance_config)
  end

  defp board_forced_theme(nil), do: nil

  defp board_forced_theme(board) do
    board.config_overrides
    |> case do
      overrides when is_map(overrides) ->
        Map.get(overrides, :forced_theme) ||
          Map.get(overrides, "forced_theme") ||
          Map.get(overrides, :force_theme) ||
          Map.get(overrides, "force_theme")

      _ ->
        nil
    end
    |> valid_forced_theme()
  end

  defp global_forced_theme(instance_config) do
    Map.get(instance_config, :forced_theme)
    |> valid_forced_theme()
  end

  defp valid_forced_theme(name) do
    case name do
      value when is_binary(value) ->
        value = String.trim(value)
        if value != "" and ThemeRegistry.valid_theme?(value), do: value, else: nil

      _ ->
        nil
    end
  end

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
