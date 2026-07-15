defmodule Eirinchan.InitialAdmin do
  @moduledoc """
  Creates the first administrator from a trusted server-side command.

  Eirinchan deliberately has no browser installation endpoint. This is the
  shared bootstrap boundary used by Mix and immutable-release commands.
  """

  alias Eirinchan.Installation
  alias Eirinchan.Moderation

  @spec create(String.t(), String.t()) ::
          {:ok, Eirinchan.Moderation.ModUser.t()}
          | {:error, :administrator_exists | Ecto.Changeset.t()}
  def create(username, password) when is_binary(username) and is_binary(password) do
    if Installation.admin_exists?() do
      {:error, :administrator_exists}
    else
      Moderation.create_user(%{
        "username" => username,
        "password" => password,
        "role" => "admin",
        "all_boards" => true
      })
    end
  end
end
