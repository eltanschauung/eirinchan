defmodule Eirinchan.Repo.Migrations.MoveHomePageIntoRecentTheme do
  use Ecto.Migration

  alias Eirinchan.Themes

  def up do
    execute(fn ->
      # theme_settings/1 includes the legacy custom-page body as a fallback.
      # Persisting it first makes the file write the durable half of the move;
      # install_theme/2 only deletes the legacy row after that write succeeds.
      settings = Themes.theme_settings("recent")

      case Themes.install_theme("recent", settings) do
        {:ok, _theme} -> :ok
        {:error, reason} -> raise "could not migrate the home page: #{inspect(reason)}"
      end
    end)
  end

  # Rolling application code back should not reintroduce two competing editors.
  def down, do: :ok
end
