defmodule EirinchanWeb.Plugs.FetchCurrentModerator do
  import Plug.Conn

  alias Eirinchan.IpCrypt
  alias Eirinchan.Moderation
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.RequestMeta

  def init(opts), do: opts

  def call(conn, _opts) do
    IpCrypt.configure_for_request(
      Config.compose(nil, Settings.current_instance_config(), %{},
        request_host: RequestMeta.request_host(conn)
      ),
      RequestMeta.effective_remote_ip(conn)
    )

    conn = assign(conn, :secure_manage_token, get_session(conn, :secure_manage_token))

    case get_session(conn, :moderator_user_id) do
      nil ->
        assign(conn, :current_moderator, nil)

      moderator_user_id ->
        assign(conn, :current_moderator, Moderation.get_user(moderator_user_id))
    end
  end
end
