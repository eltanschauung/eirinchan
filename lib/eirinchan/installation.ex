defmodule Eirinchan.Installation do
  @moduledoc """
  Reports whether the server-side installer has created an administrator.

  Database configuration and initial credentials are accepted only by trusted
  CLI commands; the web application has no installation endpoint.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Moderation.ModUser
  alias Eirinchan.Repo

  def admin_exists? do
    case table_exists?("mod_users") do
      false -> false
      true -> Repo.exists?(from user in ModUser, select: user.id, limit: 1)
    end
  end

  defp table_exists?(table_name) do
    case Repo.query("SELECT to_regclass($1)", ["public.#{table_name}"]) do
      {:ok, %{rows: [[nil]]}} -> false
      {:ok, %{rows: [[_name]]}} -> true
      {:error, _reason} -> false
    end
  end
end
