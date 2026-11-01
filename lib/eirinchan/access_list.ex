defmodule Eirinchan.AccessList do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.IpAccessEntry
  alias Eirinchan.IpMatching
  alias Eirinchan.Repo
  alias Eirinchan.CredentialHash
  alias Eirinchan.ClientMetadata
  alias Eirinchan.Settings

  @default_config %{enabled: false, entries: [], path: nil}
  @legacy_metadata_regex ~r/^#(?<password>\S+)\s+(?<date>\d{4}-\d{2}-\d{2})\s+(?<time>\d{2}:\d{2}:\d{2})(?:\s+\S+)?$/

  def enabled? do
    config().enabled
  end

  def allowed?(ip) do
    cfg = config()

    if cfg.enabled do
      IpMatching.match?(ip, entries(cfg))
    else
      true
    end
  end

  def allowed_for_posting?(ip) do
    IpMatching.match?(ip, entries())
  end

  def most_recent_granted_at(ip) do
    ip
    |> matching_stored_entries()
    |> Enum.map(& &1.granted_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&NaiveDateTime.to_gregorian_seconds/1, fn -> nil end)
  end

  def granted_within_hours?(ip, hours) when is_integer(hours) and hours > 0 do
    case most_recent_granted_at(ip) do
      %NaiveDateTime{} = granted_at ->
        NaiveDateTime.diff(current_timestamp(), granted_at, :second) < hours * 60 * 60

      nil ->
        false
    end
  end

  def granted_within_hours?(_ip, _hours), do: false

  def ip_matches_access_list?(ip, entries) do
    ip_matches_access_list(ip, entries)
  end

  def ip_matches_access_list(ip, entries) when is_list(entries) do
    IpMatching.match?(ip, entries)
  end

  def entries(cfg \\ config()) do
    List.wrap(cfg.entries) ++ stored_entries()
  end

  def stored_entries do
    active_entries(Repo, [:ip]) |> Enum.map(& &1.ip)
  end

  def record_access(ip, password, opts \\ []) when is_binary(ip) and is_list(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    granted_at = Keyword.get(opts, :granted_at, current_timestamp())
    ttl_hours = Keyword.get(opts, :grant_ttl_hours, grant_ttl_hours())
    user_agent = ClientMetadata.user_agent(Keyword.get(opts, :user_agent))
    password = plaintext_password(password)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    repo.transaction(fn ->
      repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["ip-access:#{ip}"])
      current = repo.one(from e in IpAccessEntry, where: e.ip == ^ip, lock: "FOR UPDATE")

      current =
        if current && expired_or_unused?(current, ttl_hours, now, repo) do
          repo.delete!(current)
          nil
        else
          current
        end

      cond do
        current && same_password?(current.password, password) ->
          agents = append_agent(current.user_agents || [], user_agent)

          if agents == current.user_agents,
            do: current,
            else: current |> Ecto.Changeset.change(user_agents: agents) |> repo.update!()

        true ->
          authenticated_at =
            if Keyword.has_key?(opts, :granted_at), do: local_to_utc(granted_at, repo), else: now

          attrs = %{
            password: password,
            granted_at: granted_at,
            authenticated_at: authenticated_at,
            tracking_started_at: now,
            post_count: 0,
            user_agents: List.wrap(user_agent)
          }

          if current do
            current |> Ecto.Changeset.change(attrs) |> repo.update!()
          else
            struct(IpAccessEntry, Map.put(attrs, :ip, ip)) |> repo.insert!()
          end
      end
    end)
  end

  def prune_expired(ttl_hours \\ grant_ttl_hours(), now \\ current_timestamp()) do
    cutoff = expiration_cutoff(ttl_hours, now)

    Repo.delete_all(
      from entry in IpAccessEntry, where: is_nil(entry.granted_at) or entry.granted_at < ^cutoff
    )
  end

  def import_legacy_file(path) when is_binary(path) do
    rows =
      path
      |> File.read!()
      |> String.split(~r/\R/u, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> legacy_rows()

    {count, _rows} = Repo.insert_all(IpAccessEntry, rows)
    {:ok, count}
  end

  def config do
    Map.merge(@default_config, Application.get_env(:eirinchan, :ip_access_list, %{}))
  end

  defp legacy_rows(lines), do: legacy_rows(lines, [])

  defp legacy_rows([], acc), do: Enum.reverse(acc)

  defp legacy_rows([<<"#", _::binary>> | rest], acc), do: legacy_rows(rest, acc)

  defp legacy_rows([ip, <<"#", _::binary>> = metadata | rest], acc) do
    {password, granted_at} = parse_legacy_metadata(metadata)

    legacy_rows(rest, [
      %{ip: ip, password: plaintext_password(password), granted_at: granted_at} | acc
    ])
  end

  defp legacy_rows([ip | rest], acc) do
    legacy_rows(rest, [%{ip: ip, password: nil, granted_at: nil} | acc])
  end

  defp parse_legacy_metadata(metadata) do
    case Regex.named_captures(@legacy_metadata_regex, metadata) do
      %{"password" => password, "date" => date, "time" => time} ->
        {password, NaiveDateTime.from_iso8601!("#{date} #{time}")}

      _ ->
        password =
          metadata
          |> String.trim_leading("#")
          |> String.split(~r/\s+/, parts: 2)
          |> List.first()

        {blank_to_nil(password), nil}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp plaintext_password(nil), do: nil

  defp plaintext_password(password) do
    password = String.trim(password)
    if CredentialHash.encoded?(password), do: nil, else: password
  end

  defp same_password?(a, b) when is_binary(a) and is_binary(b),
    do: String.downcase(a) == String.downcase(b)

  defp same_password?(a, b), do: a == b

  defp append_agent(agents, nil), do: agents

  defp append_agent(agents, agent) do
    if agent in agents or length(agents) >= 10, do: agents, else: agents ++ [agent]
  end

  def prune_unused(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    cutoff = DateTime.add(now, -12 * 3600, :second)

    repo.delete_all(
      from e in IpAccessEntry,
        where:
          e.post_count == 0 and
            fragment(
              "COALESCE(?, (? AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'UTC')",
              e.authenticated_at,
              e.granted_at
            ) < ^cutoff and
            e.tracking_started_at < ^cutoff
    )
  end

  def cleanup(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    cutoff = DateTime.add(now, -grant_ttl_hours() * 3600, :second)

    {expired, _} =
      repo.delete_all(
        from e in IpAccessEntry,
          where:
            fragment(
              "COALESCE(?, (? AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'UTC')",
              e.authenticated_at,
              e.granted_at
            ) < ^cutoff or
              is_nil(e.granted_at)
      )

    {unused, _} = prune_unused(Keyword.put(opts, :now, now))
    %{expired: expired, unused: unused}
  end

  def authentication_age_seconds(ip, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case matching_entries(ip, repo) |> List.first() do
      nil -> nil
      entry -> age_seconds(entry, Keyword.get(opts, :now, DateTime.utc_now()), repo)
    end
  end

  def grant_age_seconds(nil, _repo), do: nil
  def grant_age_seconds(entry, repo), do: age_seconds(entry, DateTime.utc_now(), repo)

  # Called inside the post transaction, before any allocation or publication.
  # Row locks serialize posting against grant refresh and unused-grant pruning.
  def lock_post_grant(request, repo) do
    ip = request[:remote_ip] || request["remote_ip"]

    if is_nil(ip) do
      nil
    else
      case matching_entries(ip, repo, [:ip]) |> List.first() do
        nil ->
          nil

        entry ->
          locked = repo.one(from e in IpAccessEntry, where: e.ip == ^entry.ip, lock: "FOR UPDATE")

          if locked && not expired_or_unused?(locked, grant_ttl_hours(), DateTime.utc_now(), repo),
            do: locked
      end
    end
  end

  def record_successful_post(nil, _post, _request, _config, _repo), do: :ok

  def record_successful_post(entry, post, request, config, repo) do
    {1, _} =
      repo.update_all(from(e in IpAccessEntry, where: e.ip == ^entry.ip), inc: [post_count: 1])

    snapshot = %{
      post_id: post.id,
      auth_password: entry.password,
      authenticated_at: entry.authenticated_at || local_to_utc(entry.granted_at, repo),
      auth_age_seconds: age_seconds(entry, post.inserted_at, repo),
      country_code: ClientMetadata.country_code(request, config)
    }

    case %Eirinchan.PostAuthContext{}
         |> Eirinchan.PostAuthContext.changeset(snapshot)
         |> repo.insert() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def evidence_for_post(post, config, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case repo.one(from c in Eirinchan.PostAuthContext, where: c.post_id == ^post.id) do
      nil ->
        entry =
          matching_entries(post.ip_subnet, repo, [:ip, :password, :granted_at, :authenticated_at])
          |> Enum.filter(fn entry ->
            at = entry.authenticated_at || local_to_utc(entry.granted_at, repo)
            at && DateTime.compare(at, post.inserted_at) != :gt
          end)
          |> List.first()

        %{
          auth_password: entry && entry.password,
          authenticated_at:
            entry && (entry.authenticated_at || local_to_utc(entry.granted_at, repo)),
          auth_age_seconds: entry && age_seconds(entry, post.inserted_at, repo),
          country_code: ClientMetadata.country_code(%{remote_ip: post.ip_subnet}, config)
        }

      context ->
        Map.take(context, [:auth_password, :authenticated_at, :auth_age_seconds, :country_code])
    end
  end

  defp matching_entries(ip, repo, fields \\ [:ip, :granted_at, :authenticated_at])
  defp matching_entries(nil, _repo, _fields), do: []

  defp matching_entries(ip, repo, fields),
    do: active_entries(repo, fields) |> Enum.filter(&IpMatching.match?(ip, [&1.ip]))

  defp active_entries(repo, fields) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -grant_ttl_hours() * 3600, :second)
    unused = DateTime.add(now, -12 * 3600, :second)

    repo.all(
      from e in IpAccessEntry,
        where:
          fragment(
            "COALESCE(?, (? AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'UTC')",
            e.authenticated_at,
            e.granted_at
          ) >= ^cutoff,
        where:
          not (e.post_count == 0 and
                 fragment(
                   "COALESCE(?, (? AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'UTC')",
                   e.authenticated_at,
                   e.granted_at
                 ) < ^unused and
                 e.tracking_started_at < ^unused),
        order_by: [
          desc:
            fragment(
              "COALESCE(?, (? AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'UTC')",
              e.authenticated_at,
              e.granted_at
            ),
          asc: e.ip
        ],
        select: map(e, ^fields)
    )
  end

  defp expired_or_unused?(entry, ttl, now, repo) do
    at = entry.authenticated_at || local_to_utc(entry.granted_at, repo)
    unused = DateTime.add(now, -12 * 3600, :second)

    is_nil(at) or DateTime.compare(at, DateTime.add(now, -ttl * 3600, :second)) == :lt or
      (entry.post_count == 0 and not is_nil(entry.tracking_started_at) and
         DateTime.compare(at, unused) == :lt and
         DateTime.compare(entry.tracking_started_at, unused) == :lt)
  end

  defp age_seconds(entry, now, repo) do
    case entry.authenticated_at || local_to_utc(entry.granted_at, repo) do
      nil -> nil
      at -> max(DateTime.diff(now, at, :second), 0)
    end
  end

  defp local_to_utc(nil, _repo), do: nil

  defp local_to_utc(naive, repo) do
    %{rows: [[utc]]} =
      repo.query!("SELECT $1::timestamp AT TIME ZONE current_setting('TimeZone')", [naive])

    utc
  end

  defp current_timestamp do
    NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second)
  end

  defp expiration_cutoff(ttl_hours, now) do
    NaiveDateTime.add(now, -max(ttl_hours, 1) * 60 * 60, :second)
  end

  defp grant_ttl_hours do
    Settings.current_instance_config()
    |> Map.get(:ip_access_auth, %{})
    |> Map.get(:grant_ttl_hours, 168)
    |> case do
      value when is_integer(value) and value > 0 -> value
      _ -> 168
    end
  end

  defp matching_stored_entries(ip) do
    matching_entries(ip, Repo)
  end
end
