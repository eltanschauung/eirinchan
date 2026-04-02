defmodule EirinchanWeb.Plugs.FetchTheme do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.Boards
  alias Eirinchan.Settings
  alias EirinchanWeb.ThemeRegistry

  def init(opts), do: opts

  def call(conn, _opts) do
    instance_config = Settings.current_instance_config()
    stylesheets_board = Map.get(instance_config, :stylesheets_board, true)
    board = board_for_request(conn)
    forced_theme_identifier = forced_theme(board, instance_config)
    theme_identifier = forced_theme_identifier || resolve_theme_identifier(conn, board, stylesheets_board, instance_config)

    public_theme = ThemeRegistry.public_lookup(theme_identifier)

    theme =
      ThemeRegistry.fetch(theme_identifier) ||
        ThemeRegistry.fetch(public_theme && public_theme.name) ||
        ThemeRegistry.fetch(ThemeRegistry.default_theme())

    theme_name = public_theme && public_theme.name || theme_identifier || ThemeRegistry.default_theme()
    theme_label = public_theme && public_theme.label || theme.label
    theme_options = if forced_theme_identifier, do: [], else: ThemeRegistry.public_all()

    conn
    |> assign(:theme_name, theme_name)
    |> assign(:theme_label, theme_label)
    |> assign(:theme_stylesheet, theme.stylesheet)
    |> assign(:theme_options, theme_options)
  end

  defp resolve_theme_identifier(conn, board, true, instance_config) do
    board_theme_identifier(conn, board) ||
      board_default_theme(board) ||
      global_default_theme(instance_config)
  end

  defp resolve_theme_identifier(conn, board, false, instance_config) do
    global_theme_identifier(conn) ||
      board_default_theme(board) ||
      global_default_theme(instance_config)
  end

  defp global_theme_identifier(conn) do
    conn.cookies["theme"]
    |> normalize_theme_identifier()
  end

  defp board_theme_identifier(_conn, nil), do: nil

  defp board_theme_identifier(conn, board) do
    conn.cookies["board_themes"]
    |> decode_board_themes_cookie()
    |> Map.get(board.uri)
    |> normalize_theme_identifier()
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

  defp board_default_theme(nil), do: nil

  defp board_default_theme(board) do
    board.config_overrides
    |> case do
      overrides when is_map(overrides) ->
        Map.get(overrides, :default_theme) || Map.get(overrides, "default_theme")

      _ ->
        nil
    end
    |> normalize_theme_identifier()
  end

  defp global_default_theme(instance_config) do
    Map.get(instance_config, :default_theme) || ThemeRegistry.default_theme()
  end

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
      name when is_binary(name) ->
        name
        |> normalize_theme_identifier()
        |> case do
          nil -> nil
          identifier -> if ThemeRegistry.valid_theme?(identifier), do: identifier, else: nil
        end

      _ ->
        nil
    end
  end

  defp board_for_request(conn) do
    case String.split(conn.request_path || "", "/", trim: true) do
      [segment | _rest] ->
        if reserved_path_segment?(segment) do
          nil
        else
          Boards.get_board_by_uri(segment)
        end

      _ ->
        nil
    end
  end

  defp reserved_path_segment?(segment) do
    segment in [
      "manage",
      "mod.php",
      "post.php",
      "theme",
      "api",
      "auth",
      "setup",
      "flags",
      "flag",
      "faq",
      "formatting",
      "feedback",
      "news",
      "catalog",
      "ukko",
      "recent",
      "watcher",
      "pages",
      "search.php",
      "sitemap.xml",
      "stylesheets",
      "static",
      "js",
      "images",
      "theme-thumbs"
    ]
  end

  defp normalize_theme_identifier(name) when is_binary(name), do: String.trim(name)
  defp normalize_theme_identifier(""), do: nil
  defp normalize_theme_identifier(_name), do: nil
end
