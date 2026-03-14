defmodule EirinchanWeb.Plugs.LoadBoard do
  import Plug.Conn

  alias Eirinchan.Boards
  alias Eirinchan.Runtime

  def init(opts), do: opts

  def call(conn, _opts) do
    board_uri = conn.path_params["board"] || conn.params["board"]

    with true <- is_binary(board_uri),
         {:ok, runtime_context} <-
           Boards.open_board(board_uri,
             context:
               Runtime.bootstrap(request_host: EirinchanWeb.RequestMeta.request_host(conn)),
             request_host: EirinchanWeb.RequestMeta.request_host(conn)
           ) do
      conn
      |> assign(:runtime_context, runtime_context)
      |> assign(:current_board, Boards.get_board_by_uri!(runtime_context.board.uri))
      |> assign(:current_board_runtime, runtime_context.board)
      |> assign(
        :current_board_config,
        with_viewer_timezone(
          preload_saved_user_flag(runtime_context.config, board_uri, conn.cookies),
          conn.assigns[:browser_timezone],
          conn.assigns[:browser_timezone_offset_minutes]
        )
      )
    else
      _ ->
        conn
        |> send_resp(:not_found, "Board not found")
        |> halt()
    end
  end

  defp with_viewer_timezone(config, timezone, offset_minutes) do
    config
    |> maybe_put_viewer_timezone(timezone)
    |> maybe_put_viewer_offset(offset_minutes)
  end

  defp maybe_put_viewer_timezone(config, timezone) when is_binary(timezone), do: Map.put(config, :viewer_timezone, timezone)
  defp maybe_put_viewer_timezone(config, _timezone), do: config

  defp maybe_put_viewer_offset(config, offset_minutes) when is_integer(offset_minutes),
    do: Map.put(config, :viewer_timezone_offset_minutes, offset_minutes)

  defp maybe_put_viewer_offset(config, _offset_minutes), do: config

  defp preload_saved_user_flag(%{user_flag: true} = config, board_uri, cookies) when is_binary(board_uri) and is_map(cookies) do
    case Map.get(cookies, "flag_" <> board_uri) do
      nil -> config
      "" -> config
      saved_flag -> Map.put(config, :default_user_flag, normalize_saved_user_flag(saved_flag, config))
    end
  end

  defp preload_saved_user_flag(config, _board_uri, _cookies), do: config

  defp normalize_saved_user_flag(saved_flag, %{multiple_flags: true} = config) when is_binary(saved_flag) do
    saved_flag
    |> String.split(",", trim: false)
    |> Enum.map(&(String.trim(&1) |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&allowed_user_flag?(&1, config))
    |> Enum.uniq()
    |> case do
      [] -> config.default_user_flag
      flags -> Enum.join(flags, ",")
    end
  end

  defp normalize_saved_user_flag(saved_flag, config) when is_binary(saved_flag) do
    flag = saved_flag |> String.trim() |> String.downcase()

    if flag != "" and allowed_user_flag?(flag, config) do
      flag
    else
      config.default_user_flag
    end
  end

  defp allowed_user_flag?("country", _config), do: true

  defp allowed_user_flag?(flag, config) when is_binary(flag) do
    fallback_code =
      config
      |> Map.get(:country_flag_fallback, %{})
      |> Map.get(:code, "")
      |> to_string()
      |> String.downcase()

    flag == fallback_code or Map.has_key?(Map.get(config, :user_flags, %{}), flag)
  end

  defp allowed_user_flag?(_flag, _config), do: false
end
