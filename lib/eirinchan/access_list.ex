defmodule Eirinchan.AccessList do
  @moduledoc false

  alias Eirinchan.IpMatching

  @default_config %{enabled: false, entries: [], path: nil}
  @default_access_file "var/access.conf"

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

  def ip_matches_access_list?(ip, entries) do
    ip_matches_access_list(ip, entries)
  end

  # vichan parity helper for access.conf-style IP/CIDR matching.
  def ip_matches_access_list(ip, entries_or_path \\ entries())

  def ip_matches_access_list(ip, path) when is_binary(path) do
    ip
    |> ip_matches_access_list(load_file_entries(access_file_path(path)))
  end

  def ip_matches_access_list(ip, entries) when is_list(entries) do
    IpMatching.match?(ip, entries)
  end

  def allowed_from_file?(ip, path \\ default_path()) do
    ip_matches_access_list(ip, access_file_path(path))
  end

  def entries(cfg \\ config()) do
    inline_entries = List.wrap(cfg.entries)
    file_entries = load_file_entries(cfg.path)
    inline_entries ++ file_entries
  end

  def default_path, do: access_file_path(@default_access_file)

  def access_file_path(path) when is_binary(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, project_root())
    end
  end

  def config do
    Map.merge(@default_config, Application.get_env(:eirinchan, :ip_access_list, %{}))
  end

  defp load_file_entries(nil), do: []
  defp load_file_entries(""), do: []

  defp load_file_entries(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split(~r/\R/u, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    else
      []
    end
  end

  defp project_root do
    case Application.get_env(:eirinchan, :instance_config_path) do
      path when is_binary(path) ->
        path
        |> Path.dirname()
        |> then(&Path.expand("..", &1))

      _ ->
        File.cwd!()
    end
  end
end
