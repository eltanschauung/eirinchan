defmodule EirinchanWeb.BannerAsset do
  @moduledoc false

  def banner_url(config) do
    case pick_banner(config) do
      nil -> default_banner_url()
      banner -> normalize_banner_url(banner)
    end
  end

  defp pick_banner(config) do
    config
    |> Map.get(:banners, Map.get(config, "banners", []))
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.random()
  rescue
    Enum.EmptyError -> nil
  end

  defp normalize_banner_url(url) do
    normalized = String.trim(url)

    cond do
      String.contains?(normalized, ["\r", "\n"]) -> default_banner_url()
      String.starts_with?(normalized, ["http://", "https://"]) -> normalized
      String.starts_with?(normalized, "/") and not String.starts_with?(normalized, "//") -> normalized
      String.starts_with?(normalized, "//") -> default_banner_url()
      true -> "/" <> String.trim_leading(normalized, "/")
    end
  end

  defp default_banner_url do
    case default_banner_name() do
      nil -> "/static/file.png"
      name -> "/static/banners/#{name}"
    end
  end

  defp default_banner_name do
    :eirinchan
    |> :code.priv_dir()
    |> Path.join("static/static/banners")
    |> File.ls()
    |> case do
      {:ok, files} ->
        files
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.random()

      _ ->
        nil
    end
  end
end
