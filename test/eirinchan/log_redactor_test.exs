defmodule Eirinchan.LogRedactorTest do
  use ExUnit.Case, async: true

  alias Eirinchan.LogRedactor

  test "removes sensitive headers, cookies, and complete connections from logger events" do
    conn = %Plug.Conn{
      req_headers: [
        {"cookie",
         "_eirinchan_key=session-value; password=delete-value; cf_clearance=clearance-value"},
        {"authorization", "Bearer bearer-value"},
        {"user-agent", "safe-browser"}
      ]
    }

    event = %{
      level: :error,
      msg: {:report, %{connection: conn, request_headers: conn.req_headers}},
      meta: %{session_cookie: "session-value", request_id: "safe-request-id"}
    }

    sanitized = LogRedactor.filter(event, %{})
    rendered = inspect(sanitized)

    refute rendered =~ "session-value"
    refute rendered =~ "delete-value"
    refute rendered =~ "clearance-value"
    refute rendered =~ "bearer-value"
    assert rendered =~ "safe-request-id"
    assert rendered =~ "[REDACTED] Plug.Conn"
  end

  test "redacts secrets from preformatted exception messages" do
    text =
      ~s|headers: [{"cookie", "_eirinchan_key=abc; password=def; cf_clearance=ghi"}, {"authorization", "Bearer xyz"}]|

    sanitized = LogRedactor.sanitize_text(text)

    refute sanitized =~ "abc"
    refute sanitized =~ "def"
    refute sanitized =~ "ghi"
    refute sanitized =~ "xyz"
    assert sanitized =~ "[REDACTED]"
  end
end
