defmodule Eirinchan.AccessList do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.IpAccessEntry
  alias Eirinchan.IpMatching
  alias Eirinchan.Repo

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
    Repo.all(from entry in IpAccessEntry, select: entry.ip)
  end

  def record_access(ip, password, granted_at \\ current_timestamp()) when is_binary(ip) do
    Repo.insert(%IpAccessEntry{ip: ip, password: password, granted_at: granted_at})
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
    legacy_rows(rest, [%{ip: ip, password: password, granted_at: granted_at} | acc])
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

  defp current_timestamp do
    NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second)
  end

  defp matching_stored_entries(ip) do
    Repo.all(from entry in IpAccessEntry, select: %{ip: entry.ip, granted_at: entry.granted_at})
    |> Enum.filter(&IpMatching.match?(ip, [&1.ip]))
  end
end
