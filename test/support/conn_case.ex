defmodule EirinchanWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use EirinchanWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint EirinchanWeb.Endpoint

      use EirinchanWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import EirinchanWeb.ConnCase
      import Eirinchan.BoardsFixtures
      import Eirinchan.ModerationFixtures
      import Eirinchan.PostsFixtures
      import Eirinchan.UploadsFixtures
    end
  end

  setup tags do
    Eirinchan.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def login_moderator(conn, moderator) do
    secure_manage_token = EirinchanWeb.ManageSecurity.generate_token()
    session_fingerprint = EirinchanWeb.ManageSecurity.session_fingerprint(moderator)
    login_ip = EirinchanWeb.ManageSecurity.ip_fingerprint(conn.remote_ip)
    issued_at = EirinchanWeb.ManageSecurity.current_session_issued_at()

    Phoenix.ConnTest.init_test_session(conn,
      moderator_user_id: moderator.id,
      secure_manage_token: secure_manage_token,
      moderator_session_fingerprint: session_fingerprint,
      moderator_login_ip: login_ip,
      moderator_session_issued_at: issued_at,
      moderator_session_last_seen_at: issued_at
    )
  end

  def put_secure_manage_token(conn) do
    token = Plug.Conn.get_session(conn, :secure_manage_token)
    Plug.Conn.put_req_header(conn, "x-secure-token", token)
  end
end
