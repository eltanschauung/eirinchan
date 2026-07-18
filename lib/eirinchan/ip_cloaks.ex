defmodule Eirinchan.IpCloaks do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.IpCloaks.Alias
  alias Eirinchan.Repo
  alias Eirinchan.Settings

  @prefix "c2_"
  @payload_characters 13
  @token_length byte_size(@prefix) + @payload_characters
  @token_pattern ~r/\Ac2_[A-Za-z0-9_-]{13}\z/
  @ttl_seconds 7 * 24 * 60 * 60
  @issue_attempts 5

  def token_prefix, do: @prefix
  def token_length, do: @token_length
  def ttl_seconds do
    case Map.get(Settings.effective_instance_config(), :ip_cloak_ttl_seconds, @ttl_seconds) do
      value when is_integer(value) and value > 0 -> value
      _other -> @ttl_seconds
    end
  end

  def short_token?(value) when is_binary(value) and byte_size(value) == @token_length do
    Regex.match?(@token_pattern, value)
  end

  def short_token?(_value), do: false

  def issue(payload, opts \\ [])

  def issue(payload, opts) when is_binary(payload) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
    ttl_seconds = Keyword.get(opts, :ttl_seconds, ttl_seconds())

    if authenticated_payload?(payload) and is_integer(ttl_seconds) and ttl_seconds > 0 do
      expires_at = DateTime.add(now, ttl_seconds, :second)
      issue_alias(payload, expires_at, repo, @issue_attempts)
    else
      {:error, :invalid_payload}
    end
  end

  def issue(_payload, _opts), do: {:error, :invalid_payload}

  def resolve(token, opts \\ [])

  def resolve(token, opts) when is_binary(token) do
    if short_token?(token) do
      repo = Keyword.get(opts, :repo, Repo)
      now = Keyword.get(opts, :now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

      repo.one(
        from alias_record in Alias,
          where: alias_record.token == ^token and alias_record.expires_at > ^now,
          select: alias_record.payload
      )
    end
  end

  def resolve(_token, _opts), do: nil

  def prune_expired(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

    {count, _rows} =
      repo.delete_all(from alias_record in Alias, where: alias_record.expires_at <= ^now)

    count
  end

  defp issue_alias(_payload, _expires_at, _repo, 0), do: {:error, :token_collision}

  defp issue_alias(payload, expires_at, repo, attempts_left) do
    token = generate_token()

    case %Alias{}
         |> Alias.changeset(%{token: token, payload: payload, expires_at: expires_at})
         |> repo.insert() do
      {:ok, _alias_record} -> {:ok, token}
      {:error, _changeset} -> issue_alias(payload, expires_at, repo, attempts_left - 1)
    end
  end

  defp generate_token do
    encoded = :crypto.strong_rand_bytes(10) |> Base.url_encode64(padding: false)
    @prefix <> binary_part(encoded, 0, @payload_characters)
  end

  defp authenticated_payload?(payload) do
    byte_size(payload) <= 128 and String.contains?(payload, ":v2:")
  end
end
