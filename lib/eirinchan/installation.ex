defmodule Eirinchan.Installation do
  @moduledoc """
  Reports whether the database still needs its initial administrator.

  Database configuration is supplied by the runtime environment. The web application never
  persists or changes repository credentials.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Moderation.ModUser
  alias Eirinchan.Repo

  def setup_required? do
    not admin_exists?()
  rescue
    _ -> true
  end

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
