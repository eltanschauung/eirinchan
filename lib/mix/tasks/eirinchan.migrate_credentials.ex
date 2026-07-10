defmodule Mix.Tasks.Eirinchan.MigrateCredentials do
  use Mix.Task

  @shortdoc "Hashes legacy reusable credentials in the database and settings file"

  @impl Mix.Task
  def run(args) do
    if args != [] do
      Mix.raise("usage: mix eirinchan.migrate_credentials")
    end

    Mix.Task.run("app.start")

    case Eirinchan.CredentialMigration.run() do
      {:ok, counts} ->
        Mix.shell().info(
          "Migrated #{counts.posts} post passwords, " <>
            "#{counts.ip_access_entries} IP access passwords, and " <>
            "#{counts.settings} settings files."
        )

      {:error, reason} ->
        Mix.raise("credential migration failed: #{inspect(reason)}")
    end
  end
end
