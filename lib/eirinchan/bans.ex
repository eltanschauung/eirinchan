defmodule Eirinchan.Bans do
  @moduledoc """
  Minimal ban storage, checks, and appeal handling.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Bans.{Appeal, Ban}
  alias Eirinchan.Bans.TargetResolver
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.IpMatching
  alias Eirinchan.Repo

  @duration_pattern ~r/^((\d+)\s?ye?a?r?s?)?\s?+((\d+)\s?mon?t?h?s?)?\s?+((\d+)\s?we?e?k?s?)?\s?+((\d+)\s?da?y?s?)?((\d+)\s?ho?u?r?s?)?\s?+((\d+)\s?mi?n?u?t?e?s?)?\s?+((\d+)\s?se?c?o?n?d?s?)?$/
  @default_ban_appeals true
  @default_ban_appeals_min_length 60 * 60 * 6
  @default_ban_appeals_max 1

  @spec create_ban(map(), keyword()) :: {:ok, Ban.t()} | {:error, Ecto.Changeset.t()}
  def create_ban(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    %Ban{}
    |> Ban.changeset(normalize_attrs(attrs))
    |> repo.insert()
  end

  @spec update_ban(Ban.t(), map(), keyword()) :: {:ok, Ban.t()} | {:error, Ecto.Changeset.t()}
  def update_ban(%Ban{} = ban, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    ban
    |> Ban.changeset(normalize_attrs(attrs))
    |> repo.update()
  end

  @spec parse_length(nil | String.t() | DateTime.t()) ::
          {:ok, DateTime.t() | nil} | {:error, :invalid_length}
  def parse_length(nil), do: {:ok, nil}
  def parse_length(%DateTime{} = datetime), do: {:ok, datetime}

  def parse_length(length) when is_binary(length) do
    trimmed = String.trim(length)

    cond do
      trimmed == "" ->
        {:ok, nil}

      true ->
        with {:error, :invalid_length} <- parse_absolute_datetime(trimmed),
             {:error, :invalid_length} <- parse_relative_length(trimmed) do
          {:error, :invalid_length}
        end
    end
  end

  def parse_length(_length), do: {:error, :invalid_length}

  @spec valid_ip_mask?(term()) :: boolean()
  def valid_ip_mask?(value), do: match?({:ok, _target}, TargetResolver.resolve(value))

  @spec list_bans(keyword()) :: [Ban.t()]
  def list_bans(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    board_id = Keyword.get(opts, :board_id)

    query =
      from ban in Ban,
        order_by: [desc: ban.active, desc: ban.inserted_at],
        preload: [:board, :mod_user]

    query =
      if board_id do
        from ban in query, where: ban.board_id == ^board_id
      else
        query
      end

    repo.all(query)
  end

  @spec list_matching_bans(String.t() | tuple() | nil, keyword()) :: [Ban.t()]
  def list_matching_bans(remote_ip, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    board_id = Keyword.get(opts, :board_id)
    board_ids = Keyword.get(opts, :board_ids)
    include_inactive = Keyword.get(opts, :include_inactive, true)
    remote_ip = normalize_ip(remote_ip)

    query =
      from ban in Ban,
        order_by: [desc: ban.active, desc: ban.inserted_at],
        preload: [:board, :mod_user]

    query =
      cond do
        board_id ->
          from ban in query, where: is_nil(ban.board_id) or ban.board_id == ^board_id

        is_list(board_ids) ->
          from ban in query, where: is_nil(ban.board_id) or ban.board_id in ^board_ids

        true ->
          query
      end

    query =
      if include_inactive do
        query
      else
        from ban in query, where: ban.active == true
      end

    repo.all(query)
    |> Enum.filter(&ban_matches?(&1, remote_ip))
  end

  @spec active?(Ban.t(), DateTime.t()) :: boolean()
  def active?(%Ban{} = ban, now \\ DateTime.utc_now()) do
    ban.active &&
      case ban.expires_at do
        nil -> true
        %DateTime{} = expires_at -> DateTime.compare(expires_at, now) == :gt
      end
  end

  @spec get_ban(String.t() | integer(), keyword()) :: Ban.t() | nil
  def get_ban(id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    fetch_ban(repo, id)
  end

  @spec create_appeal(String.t() | integer(), map(), keyword()) ::
          {:ok, Appeal.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def create_appeal(ban_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case fetch_ban(repo, ban_id) do
      nil ->
        {:error, :not_found}

      %Ban{} = ban ->
        insert_appeal(repo, ban, attrs)
    end
  end

  @spec create_appeal_for_request(
          String.t() | integer(),
          map(),
          BoardRecord.t(),
          tuple() | String.t() | nil,
          keyword()
        ) ::
          {:ok, Appeal.t()}
          | {:error,
             :not_found
             | :appeals_disabled
             | :appeal_too_short
             | :appeal_pending
             | :appeal_limit
             | Ecto.Changeset.t()}
  def create_appeal_for_request(ban_id, attrs, %BoardRecord{} = board, remote_ip, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, %{})
    remote_ip = normalize_ip(remote_ip)

    case fetch_ban(repo, ban_id) do
      nil ->
        {:error, :not_found}

      %Ban{} = ban ->
        cond do
          not active?(ban) ->
            {:error, :not_found}

          not ban_applies_to_board?(ban, board) ->
            {:error, :not_found}

          not ban_matches?(ban, remote_ip) ->
            {:error, :not_found}

          true ->
            ban = repo.preload(ban, :appeals)

            case appeal_context(ban, config) do
              %{can_appeal?: true} ->
                insert_appeal(repo, ban, attrs)

              %{appeal_error: reason} ->
                {:error, reason}
            end
        end
    end
  end

  @spec list_appeals(keyword()) :: [Appeal.t()]
  def list_appeals(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    board_id = Keyword.get(opts, :board_id)
    status = Keyword.get(opts, :status)

    query =
      from appeal in Appeal,
        join: ban in Ban,
        on: ban.id == appeal.ban_id,
        order_by: [asc: appeal.inserted_at],
        preload: [ban: [:board]]

    query =
      if board_id do
        from [appeal, ban] in query, where: ban.board_id == ^board_id
      else
        query
      end

    query =
      if status do
        from appeal in query, where: appeal.status == ^status
      else
        query
      end

    repo.all(query)
  end

  @spec get_appeal(String.t() | integer(), keyword()) :: Appeal.t() | nil
  def get_appeal(id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case parse_id(id) do
      {:ok, id} ->
        repo.one(
          from appeal in Appeal,
            where: appeal.id == ^id,
            preload: [ban: [:board]]
        )

      :error ->
        nil
    end
  end

  @spec resolve_appeal(String.t() | integer(), map(), keyword()) ::
          {:ok, Appeal.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def resolve_appeal(appeal_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case fetch_appeal(repo, appeal_id) do
      nil ->
        {:error, :not_found}

      %Appeal{} = appeal ->
        repo.transaction(fn ->
          with {:ok, resolved_appeal} <-
                 appeal
                 |> Appeal.changeset(
                   normalize_attrs(attrs)
                   |> Map.put(
                     "resolved_at",
                     DateTime.utc_now() |> DateTime.truncate(:microsecond)
                   )
                 )
                 |> repo.update(),
               :ok <- maybe_deactivate_ban_for_resolved_appeal(repo, resolved_appeal) do
            resolved_appeal
          else
            {:error, reason} -> repo.rollback(reason)
          end
        end)
    end
  end

  @spec appeal_context_for_request(BoardRecord.t(), tuple() | String.t() | nil, map(), keyword()) ::
          map() | nil
  def appeal_context_for_request(%BoardRecord{} = board, remote_ip, config \\ %{}, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case active_ban_for_request(board, remote_ip, opts) do
      nil ->
        nil

      %Ban{} = ban ->
        ban
        |> repo.preload(:appeals)
        |> appeal_context(config)
        |> Map.put(:remote_ip, normalize_ip(remote_ip))
    end
  end

  @spec appeal_context(Ban.t(), map()) :: map()
  def appeal_context(%Ban{} = ban, config \\ %{}) do
    appeals =
      ban
      |> Map.get(:appeals, [])
      |> loaded_association()
      |> Enum.sort_by(&(&1.inserted_at || DateTime.from_unix!(0)))

    pending_appeal = Enum.find(appeals, &(&1.status == "open"))
    rejected_appeals = Enum.filter(appeals, &(&1.status == "rejected"))

    context = %{
      ban: ban,
      pending_appeal: pending_appeal,
      rejected_appeals: rejected_appeals,
      can_appeal?: false,
      appeal_error: nil
    }

    cond do
      not ban_appeals_enabled?(config) ->
        %{context | appeal_error: :appeals_disabled}

      ban_too_short_to_appeal?(ban, config) ->
        %{context | appeal_error: :appeal_too_short}

      pending_appeal ->
        %{context | appeal_error: :appeal_pending}

      length(rejected_appeals) >= ban_appeals_max(config) ->
        %{context | appeal_error: :appeal_limit}

      true ->
        %{context | can_appeal?: true}
    end
  end

  @spec active_ban_for_request(BoardRecord.t(), tuple() | String.t() | nil, keyword()) ::
          Ban.t() | nil
  def active_ban_for_request(%BoardRecord{} = board, remote_ip, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    remote_ip = normalize_ip(remote_ip)

    repo.all(
      from ban in Ban,
        where: ban.active == true and (is_nil(ban.board_id) or ban.board_id == ^board.id),
        order_by: [desc: ban.inserted_at]
    )
    |> Enum.find(&ban_matches?(&1, remote_ip))
    |> case do
      %Ban{expires_at: %DateTime{} = expires_at} = ban ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt, do: ban, else: nil

      ban ->
        ban
    end
  end

  @spec purge_expired(keyword()) :: non_neg_integer()
  def purge_expired(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = DateTime.utc_now()

    {count, _rows} =
      repo.delete_all(
        from ban in Ban,
          where: ban.active == true and not is_nil(ban.expires_at) and ban.expires_at <= ^now
      )

    count
  end

  defp ban_matches?(_ban, nil), do: false
  defp ban_matches?(%Ban{ip_subnet: nil}, _remote_ip), do: false

  defp ban_matches?(%Ban{ip_subnet: ip_subnet}, remote_ip) do
    mask = normalize_ip_mask(ip_subnet)

    cond do
      is_nil(mask) ->
        false

      true ->
        IpMatching.entry_match?(remote_ip, mask)
    end
  end

  defp normalize_attrs(attrs) do
    attrs =
      Enum.into(attrs, %{}, fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        pair -> pair
      end)

    attrs =
      case Map.fetch(attrs, "length") do
        {:ok, length} ->
          case parse_length(length) do
            {:ok, expires_at} ->
              attrs
              |> Map.put("expires_at", expires_at)
              |> Map.delete("length")

            {:error, :invalid_length} ->
              attrs
              |> Map.put("expires_at", "__invalid_length__")
              |> Map.delete("length")
          end

        :error ->
          attrs
      end

    case Map.fetch(attrs, "ip_subnet") do
      {:ok, mask} ->
        Map.put(attrs, "ip_subnet", normalize_ip_mask(mask))

      :error ->
        attrs
    end
  end

  defp insert_appeal(repo, %Ban{} = ban, attrs) do
    %Appeal{}
    |> Appeal.changeset(%{
      "ban_id" => ban.id,
      "body" => appeal_body(attrs),
      "status" => "open"
    })
    |> repo.insert()
  end

  defp appeal_body(attrs) do
    attrs = normalize_attrs(attrs)

    Map.get(attrs, "appeal") ||
      Map.get(attrs, "body") ||
      Map.get(attrs, "message")
  end

  defp fetch_ban(repo, id) do
    case parse_id(id) do
      {:ok, id} -> repo.get(Ban, id)
      :error -> nil
    end
  end

  defp fetch_appeal(repo, id) do
    case parse_id(id) do
      {:ok, id} -> repo.get(Appeal, id)
      :error -> nil
    end
  end

  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp normalize_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_ip(ip) when is_binary(ip), do: String.trim(ip)
  defp normalize_ip(_ip), do: nil

  defp ban_applies_to_board?(%Ban{board_id: nil}, %BoardRecord{}), do: true
  defp ban_applies_to_board?(%Ban{board_id: board_id}, %BoardRecord{id: board_id}), do: true
  defp ban_applies_to_board?(%Ban{}, %BoardRecord{}), do: false

  defp loaded_association(%Ecto.Association.NotLoaded{}), do: []
  defp loaded_association(value) when is_list(value), do: value
  defp loaded_association(_value), do: []

  defp ban_appeals_enabled?(config),
    do: truthy_config?(config_value(config, :ban_appeals, @default_ban_appeals))

  defp ban_too_short_to_appeal?(%Ban{expires_at: nil}, _config), do: false

  defp ban_too_short_to_appeal?(%Ban{inserted_at: nil}, _config), do: false

  defp ban_too_short_to_appeal?(%Ban{inserted_at: inserted_at, expires_at: expires_at}, config) do
    min_length = config_value(config, :ban_appeals_min_length, @default_ban_appeals_min_length)

    is_integer(min_length) and min_length > 0 and
      DateTime.diff(expires_at, inserted_at, :second) <= min_length
  end

  defp ban_appeals_max(config) do
    case config_value(config, :ban_appeals_max, @default_ban_appeals_max) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_ban_appeals_max
    end
  end

  defp config_value(config, key, default) when is_map(config), do: Map.get(config, key, default)
  defp config_value(_config, _key, default), do: default

  defp truthy_config?(value), do: value not in [false, nil, 0, "0", "false", "False", "FALSE"]

  defp maybe_deactivate_ban_for_resolved_appeal(repo, %Appeal{status: "resolved", ban_id: ban_id}) do
    case repo.get(Ban, ban_id) do
      nil ->
        :ok

      %Ban{} = ban ->
        case ban |> Ban.changeset(%{active: false}) |> repo.update() do
          {:ok, _ban} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp maybe_deactivate_ban_for_resolved_appeal(_repo, %Appeal{}), do: :ok

  defp normalize_ip_mask(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_ip_mask(_value), do: nil

  defp parse_absolute_datetime(value) do
    cond do
      match?({:ok, _dt, _offset}, DateTime.from_iso8601(value)) ->
        {:ok, elem(DateTime.from_iso8601(value), 1)}

      match?({:ok, _ndt}, NaiveDateTime.from_iso8601(value)) ->
        {:ok, NaiveDateTime.from_iso8601!(value) |> DateTime.from_naive!("Etc/UTC")}

      match?({:ok, _dt, _offset}, DateTime.from_iso8601(value <> ":00Z")) ->
        {:ok, elem(DateTime.from_iso8601(value <> ":00Z"), 1)}

      match?({:ok, _ndt}, NaiveDateTime.from_iso8601(value <> ":00")) ->
        {:ok, NaiveDateTime.from_iso8601!(value <> ":00") |> DateTime.from_naive!("Etc/UTC")}

      true ->
        {:error, :invalid_length}
    end
  rescue
    _ -> {:error, :invalid_length}
  end

  defp parse_relative_length(value) do
    condensed = String.replace(value, ~r/\s+/, " ")

    case Regex.run(@duration_pattern, condensed) do
      nil ->
        {:error, :invalid_length}

      matches ->
        seconds =
          [
            {2, 365 * 24 * 60 * 60},
            {4, 30 * 24 * 60 * 60},
            {6, 7 * 24 * 60 * 60},
            {8, 24 * 60 * 60},
            {10, 60 * 60},
            {12, 60},
            {14, 1}
          ]
          |> Enum.reduce(0, fn {index, unit_seconds}, acc ->
            case Enum.at(matches, index) do
              nil -> acc
              "" -> acc
              value -> acc + String.to_integer(value) * unit_seconds
            end
          end)

        if seconds > 0 do
          {:ok,
           DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)}
        else
          {:error, :invalid_length}
        end
    end
  end
end
