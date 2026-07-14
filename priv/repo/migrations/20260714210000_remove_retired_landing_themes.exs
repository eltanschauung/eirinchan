defmodule Eirinchan.Repo.Migrations.RemoveRetiredLandingThemes do
  use Ecto.Migration

  alias Eirinchan.Settings

  @retired_themes MapSet.new(~w(categories frameset index))

  def up do
    execute(fn ->
      config = Settings.current_instance_config()
      template_themes = Map.get(config, :template_themes, %{})
      installed = Map.get(template_themes, :installed, %{})

      remaining =
        Enum.reduce(installed, %{}, fn {name, settings}, acc ->
          if MapSet.member?(@retired_themes, to_string(name)) do
            acc
          else
            Map.put(acc, name, settings)
          end
        end)

      if map_size(remaining) != map_size(installed) do
        updated =
          Map.put(config, :template_themes, Map.put(template_themes, :installed, remaining))

        case Settings.persist_instance_config(updated) do
          :ok -> :ok
          {:error, reason} -> raise "could not remove retired landing themes: #{inspect(reason)}"
        end
      end
    end)
  end

  # Rolling back the release does not restore retired, incompatible settings.
  def down, do: :ok
end
