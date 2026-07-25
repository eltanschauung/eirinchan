defmodule Eirinchan.Statistics.SearchTerm do
  use Ecto.Schema

  schema "statistics_search_terms" do
    field :period_start, :utc_datetime_usec
    field :field, :string
    field :term, :string
    field :occurrences, :integer

    timestamps(type: :utc_datetime_usec)
  end
end
