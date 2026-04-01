defmodule Eirinchan.AprilFoolsTeam do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:team, :integer, autogenerate: false}
  schema "april_fools_2026" do
    field :display_name, :string
    field :html_colour, :string
    field :post_count, :integer, default: 0
  end
end
