defmodule Eirinchan.Repo.Migrations.HashBrowserIdentityReferences do
  use Ecto.Migration

  alias Eirinchan.BrowserIdentity

  def up do
    migrate_table("post_ownerships")
    migrate_table("thread_watches")
  end

  def down do
    raise Ecto.MigrationError, "browser identity HMAC references cannot be reversed"
  end

  defp migrate_table(table) do
    %{rows: rows} = repo().query!("SELECT DISTINCT browser_token FROM #{table}")

    Enum.each(rows, fn [stored_value] ->
      reference = BrowserIdentity.reference(stored_value)

      if reference != stored_value do
        repo().query!(
          "UPDATE #{table} SET browser_token = $1 WHERE browser_token = $2",
          [reference, stored_value]
        )
      end
    end)
  end
end
