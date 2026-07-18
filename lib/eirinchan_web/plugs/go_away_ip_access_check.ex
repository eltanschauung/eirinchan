defmodule EirinchanWeb.Plugs.GoAwayIpAccessCheck do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.AccessList
  alias EirinchanWeb.Plugs.PrivateLoopback
  alias EirinchanWeb.RequestMeta

  @path "/__goaway/ipaccess"

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: @path} = conn, opts) do
    if PrivateLoopback.request?(conn) do
      allowed? = Keyword.get(opts, :allowed?, &AccessList.allowed_for_posting?/1)
      remote_ip = RequestMeta.effective_remote_ip(conn)
      status = if allowed?.(remote_ip), do: 204, else: 403

      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(status, "")
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn
end
