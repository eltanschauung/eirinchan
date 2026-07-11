defmodule Eirinchan.CredentialMigration do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.CredentialHash
  alias Eirinchan.IpAccessEntry
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Settings

  @post_batch_size 500
  @batch_timeout 60_000

  def run(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    migrate_settings? = Keyword.get(opts, :migrate_settings, true)

    with {:ok, post_count} <- migrate_post_credentials(repo),
         {:ok, access_count} <- repo.transaction(fn -> migrate_access_credentials(repo) end),
         {:ok, settings_count} <- migrate_settings(migrate_settings?) do
      {:ok,
       %{
         posts: post_count,
         ip_access_entries: access_count,
         settings: settings_count
       }}
    end
  end

  defp migrate_post_credentials(repo) do
    repo.all(
      from post in Post,
        where: not is_nil(post.password) and post.password != "",
        select: {post.id, post.password}
    )
    |> Enum.reject(fn {_id, password} -> CredentialHash.encoded?(password) end)
    |> Enum.map(fn {id, password} ->
      {id, CredentialHash.hash(password, :post_delete)}
    end)
    |> Enum.chunk_every(@post_batch_size)
    |> Enum.reduce_while({:ok, 0}, fn batch, {:ok, count} ->
      case repo.transaction(fn -> update_post_password_batch(repo, batch) end,
             timeout: @batch_timeout
           ) do
        {:ok, updated} -> {:cont, {:ok, count + updated}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp update_post_password_batch(repo, batch) do
    values =
      batch
      |> Enum.with_index()
      |> Enum.map_join(",", fn {_credential, index} ->
        parameter = index * 2 + 1
        "($#{parameter}::bigint,$#{parameter + 1}::text)"
      end)

    parameters = Enum.flat_map(batch, fn {id, password} -> [id, password] end)

    query = """
    UPDATE posts AS post
    SET password = credentials.password
    FROM (VALUES #{values}) AS credentials(id, password)
    WHERE post.id = credentials.id
    """

    case Ecto.Adapters.SQL.query(repo, query, parameters, timeout: @batch_timeout) do
      {:ok, %Postgrex.Result{num_rows: count}} -> count
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp migrate_access_credentials(repo) do
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

    access_count
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
