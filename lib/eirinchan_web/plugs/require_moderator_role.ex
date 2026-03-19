defmodule EirinchanWeb.Plugs.RequireModeratorRole do
  import Plug.Conn
  alias EirinchanWeb.ModeratorPermissions

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_moderator: %{role: role}}} = conn, opts) do
    required_role = Keyword.fetch!(opts, :role)

    if ModeratorPermissions.rank(role) >= ModeratorPermissions.rank(required_role) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{error: "forbidden"})
      |> halt()
    end
  end

  def call(conn, _opts) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "unauthorized"})
    |> halt()
  end
end
