defmodule EirinchanWeb.IpPresentation do
  @moduledoc false

  alias Eirinchan.IpCrypt

  def display_ip(nil, _moderator), do: nil

  def display_ip(ip, _moderator), do: IpCrypt.cloak_ip(ip)
end
