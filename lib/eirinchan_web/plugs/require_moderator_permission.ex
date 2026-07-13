defmodule EirinchanWeb.Plugs.RequireModeratorPermission do
  @moduledoc false

  import Plug.Conn

  alias EirinchanWeb.ModeratorPermissions

  def init(opts) do
    Keyword.fetch!(opts, :permission)
  end

  def call(%Plug.Conn{assigns: %{current_moderator: moderator}} = conn, permission) do
    if ModeratorPermissions.allowed?(moderator, permission) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{error: "forbidden"})
      |> halt()
    end
  end

  def call(conn, _permission) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "unauthorized"})
    |> halt()
  end
end
