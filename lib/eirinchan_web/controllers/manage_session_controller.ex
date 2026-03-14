defmodule EirinchanWeb.ManageSessionController do
  use EirinchanWeb, :controller

  alias Eirinchan.Moderation
  alias EirinchanWeb.{ManageSecurity, ModerationAudit, RequestMeta}

  def create(conn, %{"username" => username, "password" => password}) do
    case Moderation.authenticate(username, password) do
      {:ok, user} ->
        secure_token = ManageSecurity.generate_token()
        session_fingerprint = ManageSecurity.session_fingerprint(user)
        login_ip = ManageSecurity.ip_fingerprint(RequestMeta.effective_remote_ip(conn))
        ModerationAudit.log(conn, "Logged in", moderator: user)

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:moderator_user_id, user.id)
        |> put_session(:secure_manage_token, secure_token)
        |> put_session(:moderator_session_fingerprint, session_fingerprint)
        |> put_session(:moderator_login_ip, login_ip)
        |> json(%{data: session_data(user)})

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_credentials"})
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
end
