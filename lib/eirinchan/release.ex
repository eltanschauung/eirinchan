defmodule Eirinchan.Release do
  @moduledoc false

  @app :eirinchan

  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _pid, _apps} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _pid, _apps} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def initial_admin_exists? do
    start_app()
    Eirinchan.Installation.admin_exists?()
  end

  def create_initial_admin_from_stdin do
    start_app()

    username =
      System.get_env("EIRINCHAN_ADMIN_USERNAME", "")
      |> String.trim()

    password =
      IO.binread(:stdio, :eof)
      |> trim_line_ending()

    case Eirinchan.InitialAdmin.create(username, password) do
      {:ok, _admin} ->
        IO.puts("Created initial administrator #{username}.")

      {:error, :administrator_exists} ->
        raise "an administrator already exists; use the management interface to add users"

      {:error, changeset} ->
        raise "could not create administrator: #{inspect(changeset.errors)}"
    end
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    {:ok, _apps} = Application.ensure_all_started(@app)
  end

  defp trim_line_ending(password) when is_binary(password) do
    password
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
  end
end
