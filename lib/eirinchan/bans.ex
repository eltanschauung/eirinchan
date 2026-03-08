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

  @spec valid_ip_mask?(term()) :: boolean()
  def valid_ip_mask?(value) when is_binary(value) do
    mask = String.trim(value)

    cond do
      mask == "" ->
        false

      String.contains?(mask, "/") ->
        match?({:ok, _ip, _prefix}, parse_cidr(mask))

      true ->
        match?({:ok, _ip}, parse_ip(mask))
    end
  end

  def valid_ip_mask?(_value), do: false

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
    mask = normalize_ip_mask(ip_subnet)

    cond do
      is_nil(mask) ->
        false

      String.contains?(mask, "/") ->
        with {:ok, remote_ip} <- parse_ip(remote_ip),
             {:ok, mask_ip, prefix} <- parse_cidr(mask) do
          ip_in_cidr?(remote_ip, mask_ip, prefix)
        else
          _ -> false
        end

      true ->
        remote_ip == mask
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

  defp normalize_ip_mask(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_ip_mask(_value), do: nil

  defp parse_ip(value) do
    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _reason} -> {:error, :invalid_ip}
    end
  end

  defp parse_cidr(value) do
    with [address, prefix] <- String.split(value, "/", parts: 2),
         {:ok, ip} <- parse_ip(address),
         {prefix, ""} <- Integer.parse(prefix),
         true <- valid_prefix_length?(ip, prefix) do
      {:ok, ip, prefix}
    else
      _ -> {:error, :invalid_cidr}
    end
  end

  defp valid_prefix_length?({_, _, _, _}, prefix), do: prefix in 0..32
  defp valid_prefix_length?({_, _, _, _, _, _, _, _}, prefix), do: prefix in 0..128
  defp valid_prefix_length?(_, _prefix), do: false

  defp ip_in_cidr?(remote_ip, cidr_ip, prefix) do
    remote_bin = ip_to_binary(remote_ip)
    cidr_bin = ip_to_binary(cidr_ip)

    bit_size(remote_bin) == bit_size(cidr_bin) and prefix_match?(remote_bin, cidr_bin, prefix)
  end

  defp ip_to_binary({a, b, c, d}), do: <<a, b, c, d>>

  defp ip_to_binary({a, b, c, d, e, f, g, h}),
    do: <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>

  defp prefix_match?(_left, _right, 0), do: true

  defp prefix_match?(left, right, prefix) do
    <<left_prefix::bitstring-size(prefix), _::bitstring>> = left
    <<right_prefix::bitstring-size(prefix), _::bitstring>> = right
    left_prefix == right_prefix
  end

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
