defmodule EirinchanWeb.Plugs.FetchSiteAssets do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.Settings

  @default_config %{
    version: nil,
    custom_javascript: [],
    analytics_html: nil
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    config = config()

    conn
    |> assign(:asset_version, blank_to_nil(config.version))
    |> assign(:custom_javascript_urls, parse_custom_javascript(config.custom_javascript))
    |> assign(:analytics_html, blank_to_nil(config.analytics_html))
  end

  def parse_custom_javascript(value) when is_list(value) do
    value
    |> Enum.flat_map(&parse_custom_javascript/1)
    |> Enum.filter(&safe_script_url?/1)
    |> Enum.uniq()
  end

  def parse_custom_javascript(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]/u, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&safe_script_url?/1)
  end

  def parse_custom_javascript(nil), do: []
  def parse_custom_javascript(_value), do: []

  defp safe_script_url?(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> false
      String.contains?(trimmed, ["\u0000", "\r", "\n", "\t"]) -> false
      String.starts_with?(trimmed, ["javascript:", "data:"]) -> false
      String.starts_with?(trimmed, ["http://", "https://", "//", "/"]) -> true
      String.contains?(trimmed, "..") -> false
      true -> true
    end
  end

  defp config do
    site_assets = Map.merge(@default_config, Application.get_env(:eirinchan, :site_assets, %{}))
    instance_config = Settings.current_instance_config()

    Map.merge(site_assets, %{
      version: Map.get(instance_config, :asset_version, site_assets.version),
      custom_javascript:
        Map.get(instance_config, :custom_javascript, site_assets.custom_javascript),
      analytics_html: Map.get(instance_config, :analytics_html, site_assets.analytics_html)
    })
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
