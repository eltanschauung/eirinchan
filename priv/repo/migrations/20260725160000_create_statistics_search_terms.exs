defmodule Eirinchan.Repo.Migrations.CreateStatisticsSearchTerms do
  use Ecto.Migration

  def change do
    create table(:statistics_search_terms) do
      add :period_start, :utc_datetime_usec, null: false
      add :field, :string, size: 32, null: false
      add :term, :string, size: 256, null: false
      add :occurrences, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:statistics_search_terms, [:period_start, :field, :term])
    create index(:statistics_search_terms, [:period_start])
    create index(:statistics_search_terms, [:field, :term, :period_start])

    create constraint(:statistics_search_terms, :statistics_search_terms_occurrences_positive,
             check: "occurrences > 0"
           )
  end
end
