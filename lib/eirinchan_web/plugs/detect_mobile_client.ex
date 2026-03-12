defmodule EirinchanWeb.Plugs.DetectMobileClient do
  @moduledoc false

  import Plug.Conn

  @mobile_regex ~r/iPhone|iPod|iPad|Android|Opera Mini|Blackberry|PlayBook|Windows Phone|Tablet PC|Windows CE|IEMobile/i

  def init(opts), do: opts

  def call(conn, _opts) do
    user_agent = conn |> get_req_header("user-agent") |> List.first() |> to_string()
    assign(conn, :mobile_client?, user_agent =~ @mobile_regex)
  end
end
