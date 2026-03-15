defmodule EirinchanWeb.ThemeRegistry do
  @moduledoc false

  alias Eirinchan.Settings

  @static_stylesheet_dir "/home/telemazer/eirinchan-v1/priv/static/stylesheets"
  @internal_stylesheets MapSet.new([
                          "style.css",
                          "contrast.css",
                          "feedback.css",
                          "ipaccessauth.css",
                          "eirinchan-public.css",
                          "eirinchan-bant.css",
                          "eirinchan-mod.css"
                        ])
  @hidden_public_names MapSet.new(["contrast", "feedback", "ipaccessauth"])
  @preferred_public_order [
    "default",
    "vichan",
    "christmas",
    "cirno",
    "hacker",
    "aya",
    "futabamonkey",
    "tomorrow",
    "shadow",
    "eientei1"
  ]

  @themes %{
    "default" => %{label: "Yotsuba", stylesheet: "/stylesheets/yotsuba.css"},
    "yotsuba" => %{label: "Yotsuba", stylesheet: "/stylesheets/yotsuba.css"},
    "vichan" => %{label: "Yotsuba B", stylesheet: "/stylesheets/style.css"},
    "contrast" => %{label: "Contrast", stylesheet: "/stylesheets/contrast.css"},
    "feedback" => %{label: "Feedback", stylesheet: "/stylesheets/feedback.css"},
    "ipaccessauth" => %{label: "IpAccessAuth", stylesheet: "/stylesheets/ipaccessauth.css"},
    "aya" => %{label: "Aya", stylesheet: "/stylesheets/aya.css"},
    "cirno" => %{label: "Cirno Blue", stylesheet: "/stylesheets/cirno.css"},
    "christmas" => %{label: "Christmas", stylesheet: "/stylesheets/christmas.css"},
    "eientei1" => %{label: "Eientei1", stylesheet: "/stylesheets/eientei1.css"},
    "futabamonkey" => %{label: "Futaba Monkey", stylesheet: "/stylesheets/futabamonkey.css"},
    "hacker" => %{label: "Hacker", stylesheet: "/stylesheets/hacker.css"},
    "shadow" => %{label: "Westopolis", stylesheet: "/stylesheets/shadow.css"},
    "tomorrow" => %{label: "Tomorrow", stylesheet: "/stylesheets/tomorrow.css"}
  }

  def all do
    themes()
    |> Enum.map(fn {name, theme} -> Map.put(theme, :name, name) end)
    |> Enum.sort_by(& &1.name)
  end

  def public_all do
    public_theme_names()
    |> Enum.map(&public_theme_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.label)
  end

  def public_default do
    default_theme()
    |> public_lookup()
    |> Kernel.||(public_all() |> List.first())
  end

  def default_theme do
    case Settings.default_theme() do
      value when is_binary(value) and value != "" -> value
      _ -> "default"
    end
  end

  def fetch(name) when is_binary(name) do
    Map.get(themes(), String.trim(name))
  end

  def fetch(_name), do: nil

  def valid_theme?(name), do: not is_nil(fetch(name))

  def public_lookup(identifier) when is_binary(identifier) do
    value = String.trim(identifier)

    public_all()
    |> Enum.find(fn option ->
      option.name == value or option.label == value
    end)
  end

  def public_lookup(_identifier), do: nil

  defp themes do
    installed =
      Settings.installed_themes()
      |> Map.new(fn %{name: name, label: label, stylesheet: stylesheet} ->
        {name, %{label: label, stylesheet: stylesheet}}
      end)

    @themes
    |> Map.merge(detected_static_themes())
    |> Map.merge(installed)
  end

  defp detected_static_themes do
    @static_stylesheet_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".css"))
    |> Enum.reject(&MapSet.member?(@internal_stylesheets, &1))
    |> Map.new(fn filename ->
      name = Path.rootname(filename)
      {name, %{label: theme_label(name), stylesheet: "/stylesheets/#{filename}"}}
    end)
  end

  defp public_theme_names do
    configured =
      case configured_public_themes() do
        [] -> detected_public_theme_names()
        names -> names
      end

    default_name = default_theme()

    (configured ++ [default_name])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.filter(fn name ->
      fetch(name) && not MapSet.member?(@hidden_public_names, name)
    end)
  end

  defp configured_public_themes do
    config = Settings.current_instance_config()

    from_public_list =
      case get_in(config, [:themes, :public]) || get_in(config, ["themes", "public"]) do
        names when is_list(names) ->
          names
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end

    case from_public_list do
      [] -> configured_stylesheet_themes(config)
      names -> names
    end
  end

  defp configured_stylesheet_themes(config) do
    case Map.get(config, :stylesheets) || Map.get(config, "stylesheets") do
      stylesheets when is_map(stylesheets) ->
        stylesheets
        |> Enum.map(fn {label, stylesheet} ->
          theme_name_for_configured_stylesheet(to_string(label), to_string(stylesheet))
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp detected_public_theme_names do
    names =
      themes()
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(@hidden_public_names, &1))

    preferred = Enum.filter(@preferred_public_order, &(&1 in names))
    remainder = names -- preferred

    preferred ++ Enum.sort(remainder)
  end

  defp theme_name_for_configured_stylesheet(label, stylesheet) do
    stylesheet_path =
      case stylesheet do
        value ->
          if String.starts_with?(value, "/") do
            value
          else
            "/stylesheets/" <> Path.basename(value)
          end
      end

    all()
    |> Enum.find(fn theme ->
      theme.label == label or theme.stylesheet == stylesheet_path
    end)
    |> case do
      nil -> nil
      theme -> theme.name
    end
  end

  defp public_theme_entry(name) do
    case fetch(name) do
      nil -> nil
      theme -> Map.put(theme, :name, name)
    end
  end

  defp theme_label(name) do
    name
    |> String.replace(~r/[_+-]+/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
