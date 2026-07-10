defmodule Eirinchan.CredentialMigration do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.CredentialHash
  alias Eirinchan.IpAccessEntry
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Settings

  def run(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    migrate_settings? = Keyword.get(opts, :migrate_settings, true)

    with {:ok, counts} <- repo.transaction(fn -> migrate_database_credentials(repo) end),
         {:ok, settings_count} <- migrate_settings(migrate_settings?) do
      {:ok, Map.put(counts, :settings, settings_count)}
    end
  end

  defp migrate_database_credentials(repo) do
    post_count =
      repo.all(
        from post in Post,
          where: not is_nil(post.password) and post.password != "",
          select: {post.id, post.password}
      )
      |> Enum.reject(fn {_id, password} -> CredentialHash.encoded?(password) end)
      |> Enum.reduce(0, fn {id, password}, count ->
        {updated, _rows} =
          repo.update_all(
            from(post in Post, where: post.id == ^id),
            set: [password: CredentialHash.hash(password, :post_delete)]
          )

        count + updated
      end)

    access_entries = repo.all(IpAccessEntry)

    migrated_access_entries =
      Enum.map(access_entries, fn entry ->
        password = migrate_access_password(entry.password)
        %{ip: entry.ip, password: password, granted_at: entry.granted_at}
      end)

    access_count =
      Enum.count(Enum.zip(access_entries, migrated_access_entries), fn {old, new} ->
        old.password != new.password
      end)

    if access_count > 0 do
      repo.delete_all(IpAccessEntry)
      repo.insert_all(IpAccessEntry, migrated_access_entries)
    end

    %{posts: post_count, ip_access_entries: access_count}
  end

  defp migrate_access_password(nil), do: nil
  defp migrate_access_password(""), do: nil

  defp migrate_access_password(password) do
    if CredentialHash.encoded?(password) do
      password
    else
      password |> String.downcase() |> CredentialHash.hash(:ip_access)
    end
  end

  defp migrate_settings(false), do: {:ok, 0}

  defp migrate_settings(true) do
    path = Settings.config_path()

    if is_binary(path) and File.exists?(path) do
      case Settings.persist_instance_config(Settings.current_instance_config()) do
        :ok -> {:ok, 1}
        {:error, reason} -> {:error, {:settings, reason}}
      end
    else
      {:ok, 0}
    end
  end
end
