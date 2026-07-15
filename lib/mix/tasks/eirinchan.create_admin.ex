defmodule Mix.Tasks.Eirinchan.CreateAdmin do
  use Mix.Task

  @shortdoc "Creates the initial Eirinchan administrator"
  @switches [username: :string]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if positional != [] or invalid != [] do
      Mix.raise("usage: mix eirinchan.create_admin --username USERNAME")
    end

    username = opts |> Keyword.get(:username, "admin") |> String.trim()
    password = read_password()

    Mix.Task.run("app.start")

    case Eirinchan.InitialAdmin.create(username, password) do
      {:ok, _admin} ->
        Mix.shell().info("Created initial administrator #{username}.")

      {:error, :administrator_exists} ->
        Mix.raise("an administrator already exists; use the management interface to add users")

      {:error, changeset} ->
        Mix.raise("could not create administrator: #{inspect(changeset.errors)}")
    end
  end

  defp read_password do
    case System.get_env("EIRINCHAN_ADMIN_PASSWORD") do
      nil ->
        password = :io.get_password(~c"Administrator password: ") |> IO.iodata_to_binary()
        confirmation = :io.get_password(~c"Confirm password: ") |> IO.iodata_to_binary()

        if password == confirmation, do: password, else: Mix.raise("passwords do not match")

      password ->
        password
    end
  end
end
