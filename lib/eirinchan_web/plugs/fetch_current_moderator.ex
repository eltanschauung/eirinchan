defmodule EirinchanWeb.Plugs.FetchCurrentModerator do
  import Plug.Conn

  alias Eirinchan.Moderation

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = assign(conn, :secure_manage_token, get_session(conn, :secure_manage_token))

    case get_session(conn, :moderator_user_id) do
      nil ->
        assign(conn, :current_moderator, nil)

      moderator_user_id ->
        assign(conn, :current_moderator, Moderation.get_user(moderator_user_id))
    end
  end
end
