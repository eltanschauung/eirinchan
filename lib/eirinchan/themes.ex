defmodule Eirinchan.Themes do
  @moduledoc """
  Registry-backed persistence for installable, dynamic template themes.

  Template themes control public landing pages and feeds. The board catalog and
  IP-access authentication are core application features and intentionally do
  not live in this registry.
  """

  alias Eirinchan.CustomPages
  alias Eirinchan.FaqPage
  alias Eirinchan.HomePage
  alias Eirinchan.Settings
  alias Eirinchan.SiteContact
  alias Eirinchan.ThemeRegistry

  @always_enabled_features ["catalog"]
  @thumbnail_themes ~w(categories feedback frameset index recent rss sitemap ukko)

  def all_themes do
    installed = stored_theme_settings_map()

    Enum.map(ThemeRegistry.all(), fn theme ->
      stored_settings = Map.get(installed, theme.name)
      installed? = not is_nil(stored_settings)

      theme
      |> Map.put(:installed, installed?)
      |> Map.put(:rebuildable, theme.name == "faq")
      |> Map.put(
        :thumb_uri,
        if(theme.name in @thumbnail_themes, do: "/theme-thumbs/#{theme.name}.png", else: nil)
      )
      |> Map.put(:settings, theme_settings_for(theme, stored_settings || %{}))
    end)
  end

  def page_themes do
    all_themes()
    |> Enum.filter(& &1.page_theme)
    |> Enum.map(&Map.put(&1, :enabled, &1.installed))
  end

  def theme(name), do: ThemeRegistry.get(name)
  def page_theme(name), do: theme(name)

  def page_theme_enabled?(name) when is_binary(name) do
    normalized = String.trim(name)
    normalized in @always_enabled_features or normalized in installed_theme_names()
  end

  def page_theme_enabled?(_name), do: false

  def public_path(name) when is_binary(name) do
    case theme(name) do
      %{name: "ukko"} -> overboard_path()
      %{public_path: path} when is_binary(path) -> path
      _ -> nil
    end
  end

  def public_path(_name), do: nil

  def overboard_uri do
    "ukko"
    |> theme_settings()
    |> Map.get("uri", "ukko")
    |> normalize_page_uri("ukko")
  end

  def overboard_path, do: "/" <> overboard_uri()

  def overboard_matches_uri?(uri) when is_binary(uri) do
    page_theme_enabled?("ukko") and normalize_page_uri(uri, "") == overboard_uri()
  end

  def overboard_matches_uri?(_uri), do: false

  def theme_settings(name) when is_binary(name) do
    case theme(name) do
      nil -> %{}
      theme -> theme_settings_for(theme, Map.get(stored_theme_settings_map(), theme.name, %{}))
    end
  end

  def install_theme(name, params \\ %{}) when is_binary(name) and is_map(params) do
    case theme(name) do
      nil ->
        {:error, :not_found}

      theme ->
        settings = ThemeRegistry.normalize_settings(theme, params)
        previous = installed_theme_settings_map()
        updated = Map.put(previous, theme.name, settings)

        with :ok <- validate_settings(theme, settings),
             :ok <- persist_installed_theme_settings(updated) do
          case maybe_install_side_effect(theme.name, params) do
            :ok ->
              {:ok, theme |> Map.put(:settings, settings) |> Map.put(:installed, true)}

            error ->
              rollback_theme_settings(previous)
              error
          end
        end
    end
  end

  def uninstall_theme(name) when is_binary(name) do
    normalized = String.trim(name)

    cond do
      normalized in @always_enabled_features ->
        {:error, :always_enabled}

      true ->
        modules = installed_theme_settings_map()

        if Map.has_key?(modules, normalized) do
          with :ok <- persist_installed_theme_settings(Map.delete(modules, normalized)) do
            case maybe_uninstall_side_effect(normalized) do
              :ok ->
                :ok

              error ->
                rollback_theme_settings(modules)
                error
            end
          end
        else
          {:error, :not_found}
        end
    end
  end

  def rebuild_theme(name) when is_binary(name) do
    case theme(name) do
      nil -> {:error, :not_found}
      %{name: "faq"} -> rebuild_faq_page()
      _theme -> {:error, :unsupported}
    end
  end

  # Kept for callers predating the registry. Catalog is now a permanent core
  # capability, so enabling it is an idempotent no-op.
  def enable_page_theme("catalog"), do: :ok

  def enable_page_theme(name) do
    case install_theme(name, %{}) do
      {:ok, _theme} -> :ok
      error -> error
    end
  end

  def disable_page_theme(name), do: uninstall_theme(name)

  def installed_theme_names do
    installed_theme_settings_map()
    |> Map.keys()
    |> Enum.sort()
  end

  defp validate_settings(theme, settings) do
    case ThemeRegistry.validate_settings(theme, settings) do
      :ok -> :ok
      {:error, errors} -> {:error, {:invalid_settings, errors}}
    end
  end

  defp maybe_install_side_effect("faq", params), do: ensure_faq_page(params)
  defp maybe_install_side_effect("recent", _params), do: delete_legacy_home_page()
  defp maybe_install_side_effect(_name, _params), do: :ok

  defp maybe_uninstall_side_effect("faq"), do: delete_faq_page()
  defp maybe_uninstall_side_effect(_name), do: :ok

  defp ensure_faq_page(params) do
    mod_user_id = normalize_mod_user_id(params)

    body =
      case Map.get(params, "html") || Map.get(params, :html) do
        value when is_binary(value) and value != "" -> value
        _ -> FaqPage.default_body()
      end
      |> FaqPage.normalize_body()

    attrs = %{slug: "faq", title: "FAQ", body: body, mod_user_id: mod_user_id}

    case CustomPages.get_page_by_slug("faq") do
      nil -> write_custom_page(CustomPages.create_page(attrs))
      page -> write_custom_page(CustomPages.update_page(page, attrs))
    end
  end

  defp normalize_mod_user_id(params) do
    case Map.get(params, "mod_user_id") || Map.get(params, :mod_user_id) do
      nil ->
        1

      value when is_integer(value) ->
        value

      value ->
        case Integer.parse(to_string(value)) do
          {parsed, ""} when parsed > 0 -> parsed
          _ -> 1
        end
    end
  end

  defp rebuild_faq_page do
    html = theme_settings("faq") |> Map.fetch!("html") |> FaqPage.normalize_body()

    case CustomPages.get_page_by_slug("faq") do
      nil ->
        :ok

      page ->
        CustomPages.update_page(page, %{
          slug: "faq",
          title: page.title || "FAQ",
          body: html,
          mod_user_id: page.mod_user_id
        })
        |> write_custom_page()
    end
  end

  defp delete_faq_page do
    case CustomPages.get_page_by_slug("faq") do
      nil -> :ok
      page -> page |> CustomPages.delete_page() |> write_custom_page()
    end
  end

  defp delete_legacy_home_page do
    case CustomPages.get_page_by_slug("home") do
      nil -> :ok
      page -> page |> CustomPages.delete_page() |> write_custom_page()
    end
  end

  defp write_custom_page({:ok, _page}), do: :ok
  defp write_custom_page({:error, reason}), do: {:error, reason}

  defp installed_theme_settings_map do
    stored_theme_settings_map()
    |> normalize_installed_settings()
  end

  defp stored_theme_settings_map do
    current = Settings.current_instance_config()

    template_themes =
      Map.get(current, :template_themes) || Map.get(current, "template_themes") || %{}

    installed = Map.get(template_themes, :installed) || Map.get(template_themes, "installed")

    case installed do
      values when is_map(values) -> known_stored_settings(values)
      _ -> legacy_installed_theme_settings(current)
    end
  end

  defp known_stored_settings(values) do
    Enum.reduce(values, %{}, fn {name, settings}, acc ->
      case theme(to_string(name)) do
        nil -> acc
        info -> Map.put(acc, info.name, settings || %{})
      end
    end)
  end

  defp normalize_installed_settings(values) do
    Enum.reduce(values, %{}, fn {name, settings}, acc ->
      case theme(to_string(name)) do
        nil -> acc
        info -> Map.put(acc, info.name, ThemeRegistry.normalize_settings(info, settings || %{}))
      end
    end)
  end

  defp legacy_installed_theme_settings(current) do
    current
    |> Map.get(:themes, %{})
    |> Map.get(:page_enabled, :unset)
    |> case do
      :unset ->
        default_installed_theme_settings()

      values when is_list(values) ->
        values
        |> Enum.map(&to_string/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reduce(%{}, fn name, acc ->
          case theme(name) do
            nil -> acc
            info -> Map.put(acc, info.name, ThemeRegistry.default_settings(info))
          end
        end)

      _ ->
        %{}
    end
  end

  defp default_installed_theme_settings do
    Enum.reduce(ThemeRegistry.all(), %{}, fn theme, acc ->
      if theme.default_installed,
        do: Map.put(acc, theme.name, ThemeRegistry.default_settings(theme)),
        else: acc
    end)
  end

  defp persist_installed_theme_settings(modules) do
    config = Settings.current_instance_config()

    template_themes =
      config
      |> Map.get(:template_themes)
      |> case do
        value when is_map(value) -> value
        _ -> %{}
      end
      |> Map.put(:installed, modules)

    case Settings.persist_instance_config(Map.put(config, :template_themes, template_themes)) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp rollback_theme_settings(previous) do
    _ = persist_installed_theme_settings(previous)
    :ok
  end

  defp theme_settings_for(%{name: "faq"} = theme, stored),
    do: faq_theme_settings(theme, stored)

  defp theme_settings_for(%{name: "recent"} = theme, stored),
    do: recent_theme_settings(theme, stored)

  defp theme_settings_for(theme, stored),
    do: ThemeRegistry.normalize_settings(theme, stored)

  defp faq_theme_settings(theme, stored) do
    base = ThemeRegistry.normalize_settings(theme, stored)

    html =
      case CustomPages.get_page_by_slug("faq") do
        %{body: body} when is_binary(body) and body != "" -> FaqPage.normalize_body(body)
        _ -> base |> Map.get("html", FaqPage.default_body()) |> FaqPage.normalize_body()
      end

    Map.put(base, "html", html)
  end

  defp recent_theme_settings(theme, stored) do
    base = ThemeRegistry.normalize_settings(theme, stored)
    contact_email = SiteContact.email()
    legacy_page = CustomPages.get_page_by_slug("home")

    uses_legacy_page? =
      not is_nil(legacy_page) and
        (Map.get(base, "body") in [nil, ""] or legacy_recent_schema?(stored))

    body =
      cond do
        uses_legacy_page? ->
          legacy_home_body(legacy_page, contact_email)

        Map.get(base, "body") in [nil, ""] ->
          HomePage.default_body(contact_email)

        true ->
          HomePage.normalize_body(Map.fetch!(base, "body"), contact_email)
      end

    title =
      if uses_legacy_page?,
        do: legacy_home_title(legacy_page),
        else: Map.get(base, "title", "Recent Posts")

    base
    |> Map.put("title", title)
    |> Map.put("body", body)
  end

  defp legacy_home_body(%{body: body}, contact_email) when is_binary(body) and body != "",
    do: HomePage.normalize_body(body, contact_email)

  defp legacy_home_body(_page, contact_email), do: HomePage.default_body(contact_email)

  defp legacy_home_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp legacy_home_title(_page), do: "Recent Posts"

  defp legacy_recent_schema?(stored) when is_map(stored) do
    Enum.any?(~w(body_title html css basecss), fn key ->
      Map.has_key?(stored, key) or
        try do
          Map.has_key?(stored, String.to_existing_atom(key))
        rescue
          ArgumentError -> false
        end
    end)
  end

  defp legacy_recent_schema?(_stored), do: false

  defp normalize_page_uri(value, default) do
    normalized = value |> to_string() |> String.trim() |> String.trim("/")
    if ThemeRegistry.safe_route_segment?(normalized), do: normalized, else: default
  end
end
