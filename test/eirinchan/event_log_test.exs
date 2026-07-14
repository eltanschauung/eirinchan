defmodule Eirinchan.EventLogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Test

  alias Eirinchan.EventLog

  test "writes bounded structured events without raw client or credential data" do
    conn =
      conn(:post, "/manage/login?password=visible")
      |> Map.put(:remote_ip, {198, 51, 100, 8})

    log =
      capture_log(fn ->
        EventLog.log(conn, "auth.manage.rejected", %{
          outcome: "invalid_credentials",
          password: "do-not-log",
          username_id: EventLog.subject_id("Administrator", :manage_login_username)
        })
      end)

    assert log =~ "event {"
    assert log =~ ~s|"event":"auth.manage.rejected"|
    assert log =~ ~s|"outcome":"invalid_credentials"|
    assert log =~ ~s|"password":"[REDACTED]"|
    assert log =~ ~s|"path":"/manage/login"|
    refute log =~ "do-not-log"
    refute log =~ "Administrator"
    refute log =~ "198.51.100.8"
    refute log =~ "visible"
  end
end
