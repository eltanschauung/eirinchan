defmodule EirinchanWeb.Plugs.FetchCurrentModerator do
  import Plug.Conn

  alias Eirinchan.IpCrypt
  alias Eirinchan.Moderation
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.RequestMeta

  def init(opts), do: opts

  def call(conn, _opts) do
    config =
      Config.compose(nil, Settings.current_instance_config(), %{},
        request_host: RequestMeta.request_host(conn)
      )

    remote_ip = RequestMeta.effective_remote_ip(conn)

    IpCrypt.configure_for_request(config, remote_ip)

    case get_session(conn, :moderator_user_id) do
      nil ->
        conn
        |> assign(:secure_manage_token, nil)
        |> assign(:current_moderator, nil)

      moderator_user_id ->
        session_token = get_session(conn, :secure_manage_token)
        session_fingerprint = get_session(conn, :moderator_session_fingerprint)
        login_ip = get_session(conn, :moderator_login_ip)
        issued_at = get_session(conn, :moderator_session_issued_at)
        last_seen_at = get_session(conn, :moderator_session_last_seen_at)
        moderator = Moderation.get_user(moderator_user_id)

        if valid_session?(moderator, session_fingerprint, login_ip, remote_ip, issued_at, last_seen_at, config) do
          conn =
            if EirinchanWeb.ManageSecurity.refresh_session_activity?(last_seen_at) do
              put_session(conn, :moderator_session_last_seen_at, EirinchanWeb.ManageSecurity.current_session_issued_at())
            else
              conn
            end

          conn
          |> assign(:secure_manage_token, session_token)
          |> assign(:current_moderator, moderator)
        else
          conn
          |> clear_session()
          |> assign(:secure_manage_token, nil)
          |> assign(:current_moderator, nil)
        end
    end
  end

  defp valid_session?(nil, _session_fingerprint, _login_ip, _remote_ip, _issued_at, _last_seen_at, _config), do: false

  defp valid_session?(moderator, session_fingerprint, login_ip, remote_ip, issued_at, last_seen_at, config) do
    expected_fingerprint = EirinchanWeb.ManageSecurity.session_fingerprint(moderator)
    current_ip = EirinchanWeb.ManageSecurity.ip_fingerprint(remote_ip)

    fingerprint_ok? =
      is_binary(session_fingerprint) and
        byte_size(session_fingerprint) == byte_size(expected_fingerprint) and
        Plug.Crypto.secure_compare(session_fingerprint, expected_fingerprint)

    ip_ok? =
      if Map.get(config, :mod_lock_ip, true) do
        is_binary(login_ip) and is_binary(current_ip) and login_ip == current_ip
      else
        true
      end

    not EirinchanWeb.ManageSecurity.session_expired?(issued_at, last_seen_at, config) and
      fingerprint_ok? and ip_ok?
  end
end
