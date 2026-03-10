defmodule Eirinchan.Themes do
  @moduledoc """
  Registry and persistence helpers for vichan-style installable template themes.
  """

  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.CustomPages
  alias Eirinchan.FaqPage
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings

  @themes [
    %{
      name: "IpAccessAuth",
      title: "IP Access Authentication",
      description: "Whitelist-style access gate for posting from approved IPs.",
      version: "0.1",
      supported: true,
      page_theme: false,
      default_installed: false,
      config_fields: [
        %{name: "path", title: "Auth path", type: "text", default: "auth"},
        %{name: "title", title: "Page title", type: "text", default: "IP Access Authentication"}
      ]
    },
    %{
      name: "basic",
      title: "Basic index",
      description: "Simple homepage theme.",
      version: "1.0",
      supported: false,
      page_theme: false,
      default_installed: false,
      config_fields: []
    },
    %{
      name: "catalog",
      title: "Catalog",
      description: "Show a post catalog.",
      version: "0.2",
      supported: true,
      page_theme: true,
      default_installed: false,
      config_fields: [
        %{name: "title", title: "Title", type: "text", default: "Catalog"},
        %{name: "boards", title: "Included boards", type: "text", default: "*"},
        %{
          name: "update_on_posts",
          title: "Update on new posts",
          type: "checkbox",
          default: false
        },
        %{name: "use_tooltipster", title: "Use tooltipster", type: "checkbox", default: true}
      ]
    },
    %{
      name: "categories",
      title: "Categories",
      description: "Frames-style category homepage theme.",
      version: "1.0",
      supported: false,
      page_theme: false,
      default_installed: false,
      config_fields: []
    },
    %{
      name: "faq",
      title: "FAQ",
      description: "Generate the public FAQ page as a custom page.",
      version: "1.0",
      supported: true,
      page_theme: false,
      default_installed: false,
      config_fields: [
        %{name: "html", title: "HTML", type: "textarea", default: ""}
      ]
    },
    %{
      name: "feedback",
      title: "Feedback",
      description: "Public feedback page theme.",
      version: "1.0",
      supported: true,
      page_theme: false,
      default_installed: false,
      config_fields: [
        %{name: "title", title: "Title", type: "text", default: "Feedback"}
      ]
    },
    %{
      name: "frameset",
      title: "Frameset",
      description: "Classic frames homepage theme.",
      version: "1.0",
      supported: false,
      page_theme: false,
      default_installed: false,
      config_fields: []
    },
    %{
      name: "index",
      title: "Index",
      description: "Rich homepage theme.",
      version: "1.0",
      supported: false,
      page_theme: false,
      default_installed: false,
      config_fields: []
    },
    %{
      name: "public_banlist",
      title: "Public banlist",
      description: "Public ban list theme.",
      version: "1.0",
      supported: false,
      page_theme: false,
      default_installed: false,
      config_fields: []
    },
    %{
      name: "recent",
      title: "RecentPosts",
      description: "Show recent posts and images, like 4chan.",
      version: "1.0",
      supported: true,
      page_theme: true,
      default_installed: true,
      config_fields: [
        %{name: "title", title: "Title", type: "text", default: "Recent Posts"},
        %{name: "exclude", title: "Excluded boards", type: "text", default: ""},
        %{name: "limit_images", title: "# of recent images", type: "text", default: "3"},
        %{name: "limit_posts", title: "# of recent posts", type: "text", default: "30"},
        %{name: "html", title: "HTML file", type: "text", default: "recent.html"},
        %{name: "css", title: "CSS file", type: "text", default: "recent.css"},
        %{name: "basecss", title: "CSS stylesheet name", type: "text", default: "recent.css"},
        %{name: "body_title", title: "Body Title", type: "text", default: ""},
        %{name: "body", title: "Body", type: "textarea", default: ""}
      ]
    },
    %{
      name: "rss",
      title: "RSS",
      description: "RSS feed generation theme.",
      version: "1.0",
      supported: false,
      page_theme: false,
      default_installed: false,
      config_fields: []
    },
    %{
      name: "sitemap",
      title: "Sitemap",
      description: "Public sitemap.xml generation.",
      version: "1.0",
      supported: true,
      page_theme: true,
      default_installed: true,
      config_fields: [
        %{name: "path", title: "Output path", type: "text", default: "sitemap.xml"}
      ]
    },
    %{
      name: "ukko",
      title: "Overboard (Ukko)",
      description: "Board with threads and messages from all boards.",
      version: "0.2",
      supported: true,
      page_theme: true,
      default_installed: true,
      config_fields: [
        %{name: "title", title: "Board name", type: "text", default: "Ukko"},
        %{name: "uri", title: "Board URI", type: "text", default: "ukko"},
        %{name: "subtitle", title: "Subtitle", type: "text", default: ""},
        %{name: "exclude", title: "Excluded boards", type: "text", default: ""},
        %{name: "thread_limit", title: "Number of threads", type: "text", default: "15"}
      ]
    }
  ]

  def all_themes do
    installed = installed_theme_settings_map()

    Enum.map(@themes, fn theme ->
      stored_settings = Map.get(installed, theme.name)
      installed? = not is_nil(stored_settings)

      theme
      |> Map.put(:installed, installed?)
      |> Map.put(:thumb_uri, "/theme-thumbs/#{theme.name}.png")
      |> Map.put(:settings, normalize_settings(theme, stored_settings || %{}))
    end)
  end

  def page_themes do
    all_themes()
    |> Enum.filter(& &1.page_theme)
    |> Enum.map(&Map.put(&1, :enabled, &1.installed))
  end

  def theme(name) when is_binary(name) do
    normalized = String.trim(name)
    Enum.find(@themes, &(&1.name == normalized))
  end

  def theme(_name), do: nil

  def page_theme(name), do: theme(name)

  def page_theme_enabled?(name) when is_binary(name) do
    normalized = String.trim(name)
    normalized in installed_theme_names()
  end

  def page_theme_enabled?(_name), do: false

  def theme_settings(name) when is_binary(name) do
    case theme(name) do
      nil -> %{}
      %{name: "faq"} = theme -> faq_theme_settings(theme)
      theme -> normalize_settings(theme, Map.get(installed_theme_settings_map(), theme.name, %{}))
    end
  end

  def install_theme(name, params \\ %{}) when is_binary(name) and is_map(params) do
    case theme(name) do
      nil ->
        {:error, :not_found}

      %{supported: false} ->
        {:error, :unsupported}

      theme ->
        settings = normalize_settings(theme, params)
        modules = Map.put(installed_theme_settings_map(), theme.name, settings)

        with :ok <- persist_installed_theme_settings(modules),
             :ok <- maybe_install_side_effect(theme.name, params),
             :ok <- maybe_rebuild_theme(theme.name) do
          {:ok, theme |> Map.put(:settings, settings) |> Map.put(:installed, true)}
        end
    end
  end

  def uninstall_theme(name) when is_binary(name) do
    normalized = String.trim(name)
    modules = installed_theme_settings_map()

    if Map.has_key?(modules, normalized) do
      modules = Map.delete(modules, normalized)

      with :ok <- persist_installed_theme_settings(modules),
           :ok <- maybe_uninstall_side_effect(normalized),
           :ok <- maybe_rebuild_theme(normalized) do
        :ok
      end
    else
      {:error, :not_found}
    end
  end

  def rebuild_theme(name) when is_binary(name) do
    case theme(name) do
      nil -> {:error, :not_found}
      %{supported: false} -> {:error, :unsupported}
      _ -> maybe_rebuild_theme(String.trim(name))
    end
  end

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

  defp maybe_rebuild_theme("catalog"), do: rebuild_all_boards()
  defp maybe_rebuild_theme("faq"), do: rebuild_faq_page()
  defp maybe_rebuild_theme(_name), do: :ok

  defp maybe_install_side_effect("faq", params), do: ensure_faq_page(params)
  defp maybe_install_side_effect(_name, _params), do: :ok

  defp maybe_uninstall_side_effect("faq"), do: delete_faq_page()
  defp maybe_uninstall_side_effect(_name), do: :ok

  defp ensure_faq_page(params) do
    mod_user_id =
      case Map.get(params, "mod_user_id") || Map.get(params, :mod_user_id) do
        nil -> 1
        value when is_integer(value) -> value
        value -> String.to_integer(to_string(value))
      end

    body =
      case Map.get(params, "html") || Map.get(params, :html) do
        value when is_binary(value) and value != "" -> value
        _ -> FaqPage.default_html()
      end

    attrs = %{slug: "faq", title: "FAQ", body: body, mod_user_id: mod_user_id}

    case CustomPages.get_page_by_slug("faq") do
      nil ->
        case CustomPages.create_page(attrs) do
          {:ok, _page} -> :ok
          {:error, reason} -> {:error, reason}
        end

      page ->
        case CustomPages.update_page(page, attrs) do
          {:ok, _page} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp rebuild_faq_page do
    settings = faq_theme_settings(theme("faq"))
    html = Map.get(settings, "html", FaqPage.default_html())

    case CustomPages.get_page_by_slug("faq") do
      nil ->
        :ok

      page ->
        case CustomPages.update_page(page, %{
               slug: "faq",
               title: page.title || "FAQ",
               body: html,
               mod_user_id: page.mod_user_id
             }) do
          {:ok, _page} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp delete_faq_page do
    case CustomPages.get_page_by_slug("faq") do
      nil ->
        :ok

      page ->
        case CustomPages.delete_page(page) do
          {:ok, _page} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp rebuild_all_boards do
    Boards.list_boards()
    |> Enum.reduce_while(:ok, fn board, :ok ->
      config =
        Config.compose(nil, Settings.current_instance_config(), board.config_overrides || %{},
          board: Eirinchan.Boards.BoardRecord.to_board(board)
        )

      case Build.rebuild_board(board, config: config) do
        :ok -> {:cont, :ok}
        {:ok, _board} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp installed_theme_settings_map do
    current = Settings.current_instance_config()

    case current |> Map.get(:template_themes, %{}) |> Map.get(:installed) do
      values when is_map(values) ->
        Enum.reduce(values, %{}, fn {name, settings}, acc ->
          case theme(to_string(name)) do
            nil -> acc
            info -> Map.put(acc, info.name, normalize_settings(info, settings || %{}))
          end
        end)

      _ ->
        legacy_installed_theme_settings(current)
    end
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
        |> Enum.reject(&(&1 == ""))
        |> Enum.reduce(%{}, fn name, acc ->
          case theme(name) do
            nil -> acc
            info -> Map.put(acc, info.name, default_settings(info))
          end
        end)

      _ ->
        %{}
    end
  end

  defp default_installed_theme_settings do
    Enum.reduce(@themes, %{}, fn theme, acc ->
      if theme.default_installed do
        Map.put(acc, theme.name, default_settings(theme))
      else
        acc
      end
    end)
  end

  defp persist_installed_theme_settings(modules) do
    config = Settings.current_instance_config()
    updated_config = Map.put(config, :template_themes, %{installed: modules})

    case Settings.persist_instance_config(updated_config) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_settings(theme, params) when is_map(params) do
    Enum.reduce(theme.config_fields, %{}, fn field, acc ->
      value =
        case field.type do
          "checkbox" ->
            key = field.name
            raw = Map.get(params, key, Map.get(params, to_atom(key), field.default))
            raw in [true, "true", "1", 1, "on"]

          _ ->
            key = field.name
            raw = Map.get(params, key, Map.get(params, to_atom(key), field.default))
            raw |> to_string() |> String.trim()
        end

      Map.put(acc, field.name, value)
    end)
  end

  defp normalize_settings(_theme, _params), do: %{}

  defp faq_theme_settings(theme) do
    base = normalize_settings(theme, Map.get(installed_theme_settings_map(), theme.name, %{}))

    html =
      case CustomPages.get_page_by_slug("faq") do
        %{body: body} when is_binary(body) and body != "" -> body
        _ -> Map.get(base, "html", FaqPage.default_html())
      end

    Map.put(base, "html", html)
  end

  defp default_settings(theme), do: normalize_settings(theme, %{})

  defp to_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> key
    end
  end
end
