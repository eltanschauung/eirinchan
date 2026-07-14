defmodule Eirinchan.Repo.Migrations.PortFlagsCustomPage do
  use Ecto.Migration

  alias Eirinchan.FlagsPage

  @placeholder_bodies ["", "Flags", "Custom flags", "Pick custom flags for your posts."]

  def up do
    body = FlagsPage.default_body()

    execute(fn ->
      repo().query!(
        """
        UPDATE custom_pages
        SET body = $1, updated_at = NOW()
        WHERE slug = 'flags'
          AND btrim(body) = ANY($2::text[])
        """,
        [body, @placeholder_bodies]
      )

      repo().query!(
        """
        INSERT INTO custom_pages (slug, title, body, mod_user_id, inserted_at, updated_at)
        SELECT 'flags', 'Flags', $1, id, NOW(), NOW()
        FROM mod_users
        WHERE role = 'admin'
          AND NOT EXISTS (SELECT 1 FROM custom_pages WHERE slug = 'flags')
        ORDER BY id
        LIMIT 1
        """,
        [body]
      )
    end)
  end

  # Preserve the editable page if an operator rolls the application back.
  def down, do: :ok
end
