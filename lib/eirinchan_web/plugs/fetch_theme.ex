defmodule EirinchanWeb.Plugs.FetchTheme do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.Boards
  alias Eirinchan.Settings
  alias EirinchanWeb.ThemeRegistry

  @color_scheme_cookie "eirinchan_color_scheme"

  def init(opts), do: opts

  def call(conn, _opts) do
    instance_config = Settings.current_instance_config()
    stylesheets_board = Map.get(instance_config, :stylesheets_board, true)
    board = board_for_request(conn)
    forced_theme_identifier = forced_theme(board, instance_config)
    saved_theme_identifier = saved_theme_identifier(conn, board, stylesheets_board)
    light_theme_identifier = board_default_theme(board) || global_default_theme(instance_config)
    dark_theme_identifier = board_default_dark_theme(board)
    light_theme = theme_entry(light_theme_identifier) || default_theme_entry()
    dark_theme = theme_entry(dark_theme_identifier)

    auto_theme? =
      is_nil(forced_theme_identifier) and is_nil(saved_theme_identifier) and
        not is_nil(dark_theme)

    theme_identifier =
      forced_theme_identifier ||
        saved_theme_identifier ||
        if(auto_theme? and dark_scheme?(conn), do: dark_theme.name, else: light_theme.name)

    theme = theme_entry(theme_identifier) || default_theme_entry()
    theme_options = if forced_theme_identifier, do: [], else: ThemeRegistry.public_all()

    conn
    |> assign(:theme_name, theme.name)
    |> assign(:theme_label, theme.label)
    |> assign(:theme_stylesheet, theme.stylesheet)
    |> assign(:theme_preload_assets, ThemeRegistry.preload_assets(theme.name))
    |> assign(:theme_options, theme_options)
    |> assign(:auto_theme_light, if(auto_theme?, do: light_theme))
    |> assign(:auto_theme_dark, if(auto_theme?, do: dark_theme))
  end

  defp saved_theme_identifier(conn, board, true) do
    board_theme_identifier(conn, board) ||
      global_theme_identifier(conn) ||
      primary_public_board_theme_identifier(conn, board)
  end

  defp saved_theme_identifier(conn, _board, false), do: global_theme_identifier(conn)

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

  defp primary_public_board_theme_identifier(_conn, board) when not is_nil(board), do: nil

  defp primary_public_board_theme_identifier(conn, nil) do
    conn.cookies["board_themes"]
    |> decode_board_themes_cookie()
    |> Map.get("bant")
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

  defp board_default_dark_theme(nil), do: nil

  defp board_default_dark_theme(board) do
    board.config_overrides
    |> case do
      overrides when is_map(overrides) ->
        Map.get(overrides, :default_theme_dark) || Map.get(overrides, "default_theme_dark")

      _ ->
        nil
    end
    |> normalize_theme_identifier()
  end

  defp global_default_theme(instance_config) do
    Map.get(instance_config, :default_theme) || ThemeRegistry.default_theme()
  end

  defp dark_scheme?(conn), do: conn.cookies[@color_scheme_cookie] == "dark"

  defp default_theme_entry do
    ThemeRegistry.default_theme()
    |> theme_entry()
  end

  defp theme_entry(nil), do: nil

  defp theme_entry(identifier) do
    public_theme = ThemeRegistry.public_lookup(identifier)

    case ThemeRegistry.fetch(identifier) || ThemeRegistry.fetch(public_theme && public_theme.name) do
      nil ->
        nil

      theme ->
        %{
          name: if(public_theme, do: public_theme.name, else: identifier),
          label: (public_theme && public_theme.label) || theme.label,
          stylesheet: theme.stylesheet
        }
    end
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

  defp normalize_theme_identifier(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_theme_identifier(_name), do: nil
end
