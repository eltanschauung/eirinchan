defmodule EirinchanWeb.Plugs.RuntimeParsersTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias EirinchanWeb.Plugs.RuntimeParsers

  setup do
    previous = Application.get_env(:eirinchan, :max_request_bytes)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:eirinchan, :max_request_bytes)
      else
        Application.put_env(:eirinchan, :max_request_bytes, previous)
      end
    end)
  end

  test "bounds invalid, undersized, and excessive parser limits" do
    Application.put_env(:eirinchan, :max_request_bytes, :invalid)
    assert RuntimeParsers.configured_max_request_bytes() == 50_000_000

    Application.put_env(:eirinchan, :max_request_bytes, 1)
    assert RuntimeParsers.configured_max_request_bytes() == 1_048_576

    Application.put_env(:eirinchan, :max_request_bytes, 2_000_000_000)
    assert RuntimeParsers.configured_max_request_bytes() == 1_073_741_824
  end

  test "returns 413 when an encoded request exceeds the configured limit" do
    Application.put_env(:eirinchan, :max_request_bytes, 1_048_576)

    conn =
      :post
      |> conn("/", "body=" <> String.duplicate("a", 1_048_576))
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> RuntimeParsers.call(
        parsers: [:urlencoded],
        pass: ["*/*"],
        json_decoder: Jason
      )

    assert conn.halted
    assert conn.status == 413
  end
end
