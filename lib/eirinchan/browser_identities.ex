defmodule Eirinchan.BrowserIdentities do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.PostOwnership.Ownership
  alias Eirinchan.Repo
  alias Eirinchan.Settings
  alias Eirinchan.ThreadWatcher.Watch

  @default_ttl_seconds 400 * 86_400
  @default_rotation_seconds 30 * 86_400
  @default_touch_interval_seconds 3_600

  def resolve(token, cookie_issued_at, opts \\ [])
      when is_binary(token) and is_integer(cookie_issued_at) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)
    reference = BrowserIdentity.reference(token)

    case repo.get(Identity, reference) do
      nil -> register(reference, cookie_issued_at, now, repo)
      identity -> resolve_registered(identity, cookie_issued_at, now, repo)
    end
  end

  def ttl_seconds,
    do: configured_positive(:browser_identity_ttl_seconds, @default_ttl_seconds)

  def rotation_seconds,
    do:
      min(
        configured_positive(:browser_identity_rotation_seconds, @default_rotation_seconds),
        ttl_seconds()
      )

  def touch_interval_seconds,
    do:
      min(
        configured_positive(
          :browser_identity_touch_interval_seconds,
          @default_touch_interval_seconds
        ),
        rotation_seconds()
      )

  def prune_expired(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)

    references =
      repo.all(
        from identity in Identity,
          where: identity.expires_at <= ^now,
          select: identity.browser_ref
      )

    expire_references(references, repo)
    length(references)
  end

  defp register(reference, cookie_issued_at, now, repo) do
    issued_at = DateTime.from_unix!(cookie_issued_at)
    expires_at = DateTime.add(issued_at, ttl_seconds(), :second)

    if DateTime.compare(expires_at, now) in [:lt, :eq] do
      {:expired, reference}
    else
      attrs = %{
        browser_ref: reference,
        issued_at: issued_at,
        last_seen_at: now,
        expires_at: expires_at
      }

      %Identity{}
      |> Identity.changeset(attrs)
      |> repo.insert(on_conflict: :nothing, conflict_target: :browser_ref)

      identity = repo.get!(Identity, reference)
      resolve_registered(identity, cookie_issued_at, now, repo)
    end
  end

  defp resolve_registered(identity, cookie_issued_at, now, repo) do
    if DateTime.compare(identity.expires_at, now) in [:lt, :eq] do
      expire_references([identity.browser_ref], repo)
      {:expired, identity.browser_ref}
    else
      maybe_touch(identity, now, repo)

      {:ok, identity.browser_ref,
       rotate_cookie?: DateTime.to_unix(now) - cookie_issued_at >= rotation_seconds()}
    end
  end

  defp maybe_touch(identity, now, repo) do
    if DateTime.diff(now, identity.last_seen_at, :second) >= touch_interval_seconds() do
      cutoff = DateTime.add(now, -touch_interval_seconds(), :second)

      repo.update_all(
        from(stored in Identity,
          where:
            stored.browser_ref == ^identity.browser_ref and stored.last_seen_at <= ^cutoff and
              stored.last_seen_at < ^now
        ),
        set: [last_seen_at: now]
      )
    end

    :ok
  end

  defp expire_references([], _repo), do: :ok

  defp expire_references(references, repo) do
    repo.transaction(fn ->
      repo.delete_all(from ownership in Ownership, where: ownership.browser_ref in ^references)
      repo.delete_all(from watch in Watch, where: watch.browser_ref in ^references)
      repo.delete_all(from identity in Identity, where: identity.browser_ref in ^references)
    end)

    :ok
  end

  defp configured_positive(key, default) do
    instance = Settings.current_instance_config()

    value =
      if Map.has_key?(instance, key),
        do: Map.get(instance, key),
        else: Application.get_env(:eirinchan, key, default)

    case value do
      value when is_integer(value) and value > 0 -> min(value, 10 * 365 * 86_400)
      _ -> default
    end
  end
end
