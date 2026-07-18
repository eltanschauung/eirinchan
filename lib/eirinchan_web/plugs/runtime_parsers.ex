defmodule EirinchanWeb.Plugs.RuntimeParsers do
  @moduledoc false

  import Plug.Conn, only: [send_resp: 3, halt: 1]

  @default_max_request_bytes 50_000_000
  @minimum_max_request_bytes 1_048_576
  @absolute_max_request_bytes 1_073_741_824

  def init(opts), do: opts

  def call(conn, opts) do
    parser_opts =
      opts
      |> Keyword.put(:length, configured_max_request_bytes())
      |> Plug.Parsers.init()

    Plug.Parsers.call(conn, parser_opts)
  rescue
    Plug.Parsers.RequestTooLargeError ->
      conn
      |> send_resp(413, "Request body is too large.")
      |> halt()
  end

  def configured_max_request_bytes do
    case Application.get_env(:eirinchan, :max_request_bytes, @default_max_request_bytes) do
      value when is_integer(value) ->
        value
        |> max(@minimum_max_request_bytes)
        |> min(@absolute_max_request_bytes)

      _other ->
        @default_max_request_bytes
    end
  end
end
