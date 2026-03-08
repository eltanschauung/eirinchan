defmodule Eirinchan.Bans do
  @moduledoc """
  Minimal ban storage, checks, and appeal handling.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Bans.{Appeal, Ban}
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Repo

  @duration_pattern ~r/^((\d+)\s?ye?a?r?s?)?\s?+((\d+)\s?mon?t?h?s?)?\s?+((\d+)\s?we?e?k?s?)?\s?+((\d+)\s?da?y?s?)?((\d+)\s?ho?u?r?s?)?\s?+((\d+)\s?mi?n?u?t?e?s?)?\s?+((\d+)\s?se?c?o?n?d?s?)?$/

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

  @spec parse_length(nil | String.t() | DateTime.t()) :: {:ok, DateTime.t() | nil} | {:error, :invalid_length}
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

  @spec get_ban(String.t() | integer(), keyword()) :: Ban.t() | nil
  def get_ban(id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.get(Ban, normalize_id(id))
  end

  @spec create_appeal(String.t() | integer(), map(), keyword()) ::
          {:ok, Appeal.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def create_appeal(ban_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case repo.get(Ban, normalize_id(ban_id)) do
      nil ->
        {:error, :not_found}

      %Ban{} = ban ->
        %Appeal{}
        |> Appeal.changeset(%{
          "ban_id" => ban.id,
          "body" => Map.get(normalize_attrs(attrs), "body"),
          "status" => "open"
        })
        |> repo.insert()
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

    repo.one(
      from appeal in Appeal,
        where: appeal.id == ^normalize_id(id),
        preload: [ban: [:board]]
    )
  end

  @spec resolve_appeal(String.t() | integer(), map(), keyword()) ::
          {:ok, Appeal.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def resolve_appeal(appeal_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case repo.get(Appeal, normalize_id(appeal_id)) do
      nil ->
        {:error, :not_found}

      %Appeal{} = appeal ->
        appeal
        |> Appeal.changeset(
          normalize_attrs(attrs)
          |> Map.put("resolved_at", DateTime.utc_now() |> DateTime.truncate(:microsecond))
        )
        |> repo.update()
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
    cond do
      String.ends_with?(ip_subnet, "/16") ->
        String.starts_with?(remote_ip, ip_prefix(ip_subnet, 2))

      String.ends_with?(ip_subnet, "/24") ->
        String.starts_with?(remote_ip, ip_prefix(ip_subnet, 3))

      String.ends_with?(ip_subnet, "/48") ->
        String.starts_with?(remote_ip, ipv6_prefix(ip_subnet, 3))

      true ->
        remote_ip == ip_subnet
    end
  end

  defp ip_prefix(ip_subnet, octets) do
    ip_subnet
    |> String.replace(~r/\/\d+$/, "")
    |> String.split(".")
    |> Enum.take(octets)
    |> Enum.join(".")
  end

  defp ipv6_prefix(ip_subnet, groups) do
    ip_subnet
    |> String.replace(~r/::\/\d+$/, "")
    |> String.split(":")
    |> Enum.take(groups)
    |> Enum.join(":")
  end

  defp normalize_attrs(attrs) do
    attrs =
      Enum.into(attrs, %{}, fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        pair -> pair
      end)

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
  end

  defp normalize_id(value) when is_integer(value), do: value
  defp normalize_id(value) when is_binary(value), do: String.to_integer(String.trim(value))

  defp normalize_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_ip(ip) when is_binary(ip), do: String.trim(ip)
  defp normalize_ip(_ip), do: nil

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
          [{2, 365 * 24 * 60 * 60}, {4, 30 * 24 * 60 * 60}, {6, 7 * 24 * 60 * 60},
           {8, 24 * 60 * 60}, {10, 60 * 60}, {12, 60}, {14, 1}]
          |> Enum.reduce(0, fn {index, unit_seconds}, acc ->
            case Enum.at(matches, index) do
              nil -> acc
              "" -> acc
              value -> acc + String.to_integer(value) * unit_seconds
            end
          end)

        if seconds > 0 do
          {:ok, DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)}
        else
          {:error, :invalid_length}
        end
    end
  end
end
