defmodule Eirinchan.IpAccessEntry do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:ip, :string, autogenerate: false}
  @derive {Inspect, except: [:ip, :password, :user_agents]}
  schema "ip_access_entries" do
    field :password, :string
    field :granted_at, :naive_datetime
    field :authenticated_at, :utc_datetime_usec
    field :post_count, :integer, default: 0
    field :user_agents, {:array, :string}, default: []
    field :tracking_started_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end
end
