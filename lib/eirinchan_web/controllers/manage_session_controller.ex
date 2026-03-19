defmodule EirinchanWeb.ManageSessionController do
  use EirinchanWeb, :controller

  alias Eirinchan.ManageLoginThrottle
  alias Eirinchan.Moderation
  alias EirinchanWeb.{ManageSecurity, ModerationAudit, RequestMeta}

  def create(conn, %{"username" => username, "password" => password}) do
    config = current_config()
    remote_ip = RequestMeta.effective_remote_ip(conn)

    case ManageLoginThrottle.allowed?(username, remote_ip, config) do
      :ok ->
        case Moderation.authenticate(username, password) do
          {:ok, user} ->
            ManageLoginThrottle.clear(username, remote_ip)
            ModerationAudit.log(conn, "Logged in", moderator: user)

            conn
            |> establish_moderator_session(user, remote_ip)
            |> json(%{data: session_data(user)})

          {:error, :invalid_credentials} ->
            handle_failed_login(conn, username, remote_ip, config)
        end

      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> json(%{error: "rate_limited"})
    end
  end

  def show(conn, _params) do
    case conn.assigns[:current_moderator] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})

      user ->
        json(conn, %{data: session_data(user)})
    end
  end

  def delete(conn, _params) do
    ModerationAudit.log(conn, "Logged out")

    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> json(%{status: "ok"})
  end

  defp session_data(user) do
    %{
      id: user.id,
      username: user.username,
      role: user.role
    }
  end

  defp establish_moderator_session(conn, user, remote_ip) do
    secure_token = ManageSecurity.generate_token()
    session_fingerprint = ManageSecurity.session_fingerprint(user)
    login_ip = ManageSecurity.ip_fingerprint(remote_ip)
    issued_at = ManageSecurity.current_session_issued_at()

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:moderator_user_id, user.id)
    |> put_session(:secure_manage_token, secure_token)
    |> put_session(:moderator_session_fingerprint, session_fingerprint)
    |> put_session(:moderator_login_ip, login_ip)
    |> put_session(:moderator_session_issued_at, issued_at)
    |> put_session(:moderator_session_last_seen_at, issued_at)
  end

  defp handle_failed_login(conn, username, remote_ip, config) do
    case ManageLoginThrottle.record_failure(username, remote_ip, config) do
      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> json(%{error: "rate_limited"})

      :ok ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_credentials"})
    end
  end

  defp current_config do
    Eirinchan.Settings.current_instance_config()
  end
end
