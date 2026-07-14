defmodule Eirinchan.Repo.Migrations.MoveFaqToStaticPages do
  use Ecto.Migration

  alias Eirinchan.FaqPage
  alias Eirinchan.Settings

  def up do
    execute(fn ->
      config = Settings.current_instance_config()
      template_themes = Map.get(config, :template_themes, %{})

      installed =
        case Map.get(template_themes, :installed) do
          value when is_map(value) -> value
          _ -> %{}
        end

      faq_settings = Map.get(installed, "faq") || Map.get(installed, :faq) || %{}
      body = faq_body(faq_settings)

      repo().query!(
        """
        INSERT INTO custom_pages (slug, title, body, mod_user_id, inserted_at, updated_at)
        SELECT 'faq', 'FAQ', $1, id, NOW(), NOW()
        FROM mod_users
        WHERE role = 'admin'
          AND NOT EXISTS (SELECT 1 FROM custom_pages WHERE slug = 'faq')
        ORDER BY id
        LIMIT 1
        """,
        [body]
      )

      remaining = Map.drop(installed, ["faq", :faq])

      if map_size(remaining) != map_size(installed) do
        updated =
          Map.put(config, :template_themes, Map.put(template_themes, :installed, remaining))

        case Settings.persist_instance_config(updated) do
          :ok -> :ok
          {:error, reason} -> raise "could not retire the FAQ theme: #{inspect(reason)}"
        end
      end
    end)
  end

  # The static page remains editable if the application is rolled back.
  def down, do: :ok

  defp faq_body(settings) do
    case Map.get(settings, "html") || Map.get(settings, :html) do
      value when is_binary(value) and value != "" -> FaqPage.normalize_body(value)
      _ -> FaqPage.default_body()
    end
  end
end
