defmodule EirinchanWeb.Plugs.FetchSiteAssets do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.Settings

  @default_config %{
    version: nil,
    custom_javascript: [],
    analytics_html: nil,
    url_favicon: "favicon.ico",
    show_styles_block: true,
    allow_custom_javascript: false,
    allow_remote_script_urls: false,
    allow_analytics_html: false
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    config = config()

    conn
    |> assign(:asset_version, blank_to_nil(config.version))
    |> assign(
      :custom_javascript_urls,
      if(config.allow_custom_javascript,
        do:
          parse_custom_javascript(
            config.custom_javascript,
            allow_remote_script_urls: config.allow_remote_script_urls
          ),
        else: []
      )
    )
    |> assign(
      :analytics_html,
      if(config.allow_analytics_html, do: blank_to_nil(config.analytics_html), else: nil)
    )
    |> assign(:favicon_url, normalize_favicon_url(config.url_favicon))
    |> assign(:show_styles_block, config.show_styles_block != false)
  end

  def parse_custom_javascript(value, opts \\ [])

  def parse_custom_javascript(value, opts) when is_list(value) do
    value
    |> Enum.flat_map(&parse_custom_javascript(&1, opts))
    |> Enum.filter(&safe_script_url?(&1, opts))
    |> Enum.uniq()
  end

  def parse_custom_javascript(value, opts) when is_binary(value) do
    value
    |> String.split(~r/[\n,]/u, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&safe_script_url?(&1, opts))
  end

  def parse_custom_javascript(nil, _opts), do: []
  def parse_custom_javascript(_value, _opts), do: []

  defp safe_script_url?(value, opts) when is_binary(value) do
    trimmed = String.trim(value)
    allow_remote_script_urls = Keyword.get(opts, :allow_remote_script_urls, false)

    cond do
      trimmed == "" -> false
      String.contains?(trimmed, ["\u0000", "\r", "\n", "\t"]) -> false
      String.starts_with?(trimmed, ["javascript:", "data:"]) -> false
      String.starts_with?(trimmed, ["http://", "https://", "//"]) -> allow_remote_script_urls
      String.starts_with?(trimmed, "/") -> true
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
      analytics_html: Map.get(instance_config, :analytics_html, site_assets.analytics_html),
      url_favicon: Map.get(instance_config, :url_favicon, site_assets.url_favicon),
      show_styles_block:
        Map.get(instance_config, :show_styles_block, site_assets.show_styles_block),
      allow_custom_javascript:
        Map.get(instance_config, :allow_custom_javascript, site_assets.allow_custom_javascript),
      allow_remote_script_urls:
        Map.get(
          instance_config,
          :allow_remote_script_urls,
          site_assets.allow_remote_script_urls
        ),
      allow_analytics_html:
        Map.get(instance_config, :allow_analytics_html, site_assets.allow_analytics_html)
    })
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp normalize_favicon_url(nil), do: nil
  defp normalize_favicon_url(""), do: nil

  defp normalize_favicon_url(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> nil
      String.starts_with?(trimmed, ["http://", "https://", "//", "/"]) -> trimmed
      true -> "/" <> trimmed
    end
  end
end
