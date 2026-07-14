defmodule Eirinchan.Repo.Migrations.SeedHomeCustomPage do
  use Ecto.Migration

  alias Eirinchan.HomePage

  def up do
    body = HomePage.default_body()

    execute(fn ->
      repo().query!(
        """
        INSERT INTO custom_pages (slug, title, body, mod_user_id, inserted_at, updated_at)
        SELECT 'home', 'Recent Posts', $1, id, NOW(), NOW()
        FROM mod_users
        WHERE role = 'admin'
        ORDER BY id
        LIMIT 1
        ON CONFLICT (slug) DO NOTHING
        """,
        [body]
      )
    end)
  end

  # Preserve the editable page if an operator rolls the application back.
  def down, do: :ok
end
