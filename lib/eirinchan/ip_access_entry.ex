defmodule Eirinchan.IpAccessEntry do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "ip_access_entries" do
    field :ip, :string
    field :password, :string
    field :granted_at, :naive_datetime
  end
end
