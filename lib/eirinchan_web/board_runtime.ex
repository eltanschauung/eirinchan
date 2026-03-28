defmodule EirinchanWeb.BoardRuntime do
  @moduledoc false

  alias Eirinchan.Boards.Board
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.RequestMeta

  def request_host(%Plug.Conn{} = conn), do: RequestMeta.request_host(conn)
  def request_host(host) when is_binary(host), do: host
  def request_host(_), do: nil

  def board_config(%BoardRecord{} = board_record, request_host_or_conn, opts \\ []) do
    instance_config = Keyword.get_lazy(opts, :instance_config, &Settings.current_instance_config/0)
    runtime_paths? = Keyword.get(opts, :runtime_paths?, false)
    overrides = Config.normalize_override_keys(board_record.config_overrides || %{})
    browser_timezone = Keyword.get(opts, :browser_timezone, viewer_timezone(request_host_or_conn))
    browser_timezone_offset_minutes =
      Keyword.get(opts, :browser_timezone_offset_minutes, viewer_timezone_offset(request_host_or_conn))

    board =
      board_record
      |> BoardRecord.to_board()
      |> maybe_with_runtime_paths(instance_config, runtime_paths?)

    Config.compose(nil, instance_config, overrides,
      board: board,
      request_host: request_host(request_host_or_conn)
    )
    |> maybe_put_viewer_timezone(browser_timezone)
    |> maybe_put_viewer_offset(browser_timezone_offset_minutes)
  end

  def config_map(boards, request_host_or_conn, opts \\ []) do
    instance_config = Keyword.get_lazy(opts, :instance_config, &Settings.current_instance_config/0)
    runtime_paths? = Keyword.get(opts, :runtime_paths?, false)

    Map.new(boards, fn board ->
      {board.id,
       board_config(board, request_host_or_conn,
         instance_config: instance_config,
         runtime_paths?: runtime_paths?
       )}
    end)
  end

  defp maybe_with_runtime_paths(board, _instance_config, false), do: board

  defp maybe_with_runtime_paths(board, instance_config, true) do
    board
    |> Board.with_runtime_paths(Config.compose(nil, instance_config, %{}))
  end

  defp viewer_timezone(%Plug.Conn{} = conn), do: conn.assigns[:browser_timezone]
  defp viewer_timezone(_), do: nil

  defp viewer_timezone_offset(%Plug.Conn{} = conn), do: conn.assigns[:browser_timezone_offset_minutes]
  defp viewer_timezone_offset(_), do: nil

  defp maybe_put_viewer_timezone(config, timezone) when is_binary(timezone),
    do: Map.put(config, :viewer_timezone, timezone)

  defp maybe_put_viewer_timezone(config, _timezone), do: config

  defp maybe_put_viewer_offset(config, offset_minutes) when is_integer(offset_minutes),
    do: Map.put(config, :viewer_timezone_offset_minutes, offset_minutes)

  defp maybe_put_viewer_offset(config, _offset_minutes), do: config
end
