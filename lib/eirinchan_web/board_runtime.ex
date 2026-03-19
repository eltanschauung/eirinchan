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

    board =
      board_record
      |> BoardRecord.to_board()
      |> maybe_with_runtime_paths(instance_config, runtime_paths?)

    Config.compose(nil, instance_config, overrides,
      board: board,
      request_host: request_host(request_host_or_conn)
    )
  end

  def config_map(boards, request_host_or_conn, opts \\ []) do
    instance_config = Keyword.get_lazy(opts, :instance_config, &Settings.current_instance_config/0)
    runtime_paths? = Keyword.get(opts, :runtime_paths?, false)
    request_host = request_host(request_host_or_conn)

    Map.new(boards, fn board ->
      {board.id,
       board_config(board, request_host,
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
end
