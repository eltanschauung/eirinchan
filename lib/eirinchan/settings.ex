defmodule Eirinchan.Settings do
  @moduledoc """
  Persists instance-level runtime overrides for the browser admin config editor.
  """

  alias Eirinchan.Runtime.Config
  alias Eirinchan.SecureFile

  @settings_cache_key {__MODULE__, :instance_config}
  @effective_config_cache_key {__MODULE__, :effective_instance_config}
  @raw_json_cache_key {__MODULE__, :raw_instance_config_json}

  @spec current_instance_config() :: map()
  def current_instance_config do
    case :persistent_term.get(cache_key(@settings_cache_key), :missing) do
      :missing ->
        config = persisted_instance_config_uncached() || %{}
        :persistent_term.put(cache_key(@settings_cache_key), config)
        config

      config ->
        config
    end
  end

  @doc "Returns instance settings merged with defaults and normalized runtime bounds."
  @spec effective_instance_config() :: map()
  def effective_instance_config do
    case :persistent_term.get(cache_key(@effective_config_cache_key), :missing) do
      :missing ->
        config = Config.compose(nil, current_instance_config(), %{})
        :persistent_term.put(cache_key(@effective_config_cache_key), config)
        config

      config ->
        config
    end
  end

  @spec raw_instance_config_json() :: binary() | nil
  def raw_instance_config_json do
    case :persistent_term.get(cache_key(@raw_json_cache_key), :missing) do
      :missing ->
        raw_json = raw_instance_config_json_uncached()
        :persistent_term.put(cache_key(@raw_json_cache_key), raw_json)
        raw_json

      raw_json ->
        raw_json
    end
  end

  @spec installed_themes() :: [map()]
  def installed_themes do
    current_instance_config()
    |> Map.get(:themes, %{})
    |> Map.get(:installed, [])
    |> Enum.map(&normalize_theme_definition/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec default_theme() :: binary() | nil
  def default_theme do
    current_instance_config()
    |> Map.get(:themes, %{})
    |> Map.get(:default)
    |> case do
      value when is_binary(value) -> String.trim(value)
      _ -> nil
    end
  end

  @spec persisted_instance_config() :: map() | nil
  def persisted_instance_config do
    current_instance_config()
  end

  def refresh_instance_config_cache do
    clear_cache_entry(@settings_cache_key)
    clear_cache_entry(@effective_config_cache_key)
    clear_cache_entry(@raw_json_cache_key)

    if Process.whereis(EirinchanWeb.FragmentCache) do
      EirinchanWeb.FragmentCache.clear()
    end

    :ok
  end

  defp persisted_instance_config_uncached do
    path = config_path()

    with true <- is_binary(path) and File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         true <- is_map(decoded) do
      Config.normalize_override_keys(decoded)
    else
      _ -> nil
    end
  end

  defp raw_instance_config_json_uncached do
    path = config_path()

    with true <- is_binary(path) and File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         true <- is_map(decoded) do
      body
    else
      _ -> nil
    end
  end

  @spec update_instance_config_from_json(binary()) :: {:ok, map()} | {:error, :invalid_json}
  def update_instance_config_from_json(raw_json) when is_binary(raw_json) do
    with {:ok, decoded} <- Jason.decode(raw_json),
         true <- is_map(decoded),
         normalized <- Config.normalize_override_keys(decoded),
         :ok <- persist_instance_config_raw_json(raw_json) do
      {:ok, normalized}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      false -> {:error, :invalid_json}
      {:error, _reason} = error -> error
    end
  end

  @spec persist_instance_config(map()) :: :ok | {:error, term()}
  def persist_instance_config(overrides) when is_map(overrides) do
    path = config_path()

    overrides =
      overrides
      |> preserve_hidden_instance_state(current_instance_config())

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    overrides
    |> stringify_keys()
    |> Jason.encode_to_iodata!(pretty: true)
    |> then(&SecureFile.atomic_write(path, &1))
    |> tap(fn
      :ok -> refresh_instance_config_cache()
      _ -> :ok
    end)
  end

  @spec persist_instance_config_raw_json(binary()) :: :ok | {:error, term()}
  def persist_instance_config_raw_json(raw_json) when is_binary(raw_json) do
    path = config_path()
    decoded = Jason.decode!(raw_json)

    processed =
      decoded
      |> Config.normalize_override_keys()
      |> preserve_hidden_instance_state(current_instance_config())
      |> stringify_keys()

    persisted_json =
      if processed == decoded do
        raw_json
      else
        Jason.encode_to_iodata!(processed, pretty: true)
      end

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    persisted_json
    |> then(&SecureFile.atomic_write(path, &1))
    |> tap(fn
      :ok -> refresh_instance_config_cache()
      _ -> :ok
    end)
  end

  @spec config_path() :: binary() | nil
  def config_path do
    Application.get_env(:eirinchan, :instance_config_path)
  end

  @spec encode_for_edit(map()) :: binary()
  def encode_for_edit(overrides) when is_map(overrides) do
    overrides
    |> stringify_keys()
    |> Jason.encode!(pretty: true)
  end

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {to_string(key), stringify_keys(nested_value)}
    end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  @spec upsert_theme(map()) :: {:ok, map()} | {:error, :invalid_theme}
  def upsert_theme(attrs) when is_map(attrs) do
    with %{name: name} = theme <-
           normalize_theme_definition(attrs) do
      config = current_instance_config()

      themes =
        config
        |> Map.get(:themes, %{})
        |> Map.get(:installed, [])
        |> Enum.map(&normalize_theme_definition/1)

      updated =
        themes
        |> Enum.reject(&(&1 && &1.name == name))
        |> Kernel.++([theme])
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.name)

      persist_and_return(
        put_themes_config(config, %{default: default_theme(), installed: updated}),
        theme
      )
    else
      _ -> {:error, :invalid_theme}
    end
  end

  @spec delete_theme(binary()) :: :ok | {:error, :not_found}
  def delete_theme(name) when is_binary(name) do
    normalized_name = String.trim(name)
    config = current_instance_config()
    themes = installed_themes()
    updated = Enum.reject(themes, &(&1.name == normalized_name))

    if length(updated) == length(themes) do
      {:error, :not_found}
    else
      default =
        case default_theme() do
          ^normalized_name -> nil
          current -> current
        end

      new_config = put_themes_config(config, %{default: default, installed: updated})

      case persist_instance_config(new_config |> bump_asset_version()) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec set_default_theme(binary()) :: :ok | {:error, :invalid_theme}
  def set_default_theme(name) when is_binary(name) do
    normalized_name = String.trim(name)

    if normalized_name == "" do
      {:error, :invalid_theme}
    else
      config = current_instance_config()
      themes = config |> Map.get(:themes, %{}) |> Map.get(:installed, [])
      new_config = put_themes_config(config, %{default: normalized_name, installed: themes})

      case persist_instance_config(new_config |> bump_asset_version()) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec current_asset_version() :: binary() | nil
  def current_asset_version do
    case current_instance_config() |> Map.get(:asset_version) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp normalize_theme_definition(attrs) when is_map(attrs) do
    name =
      attrs[:name] ||
        attrs["name"]
        |> to_string()
        |> String.trim()

    label =
      attrs[:label] ||
        attrs["label"]
        |> to_string()
        |> String.trim()

    stylesheet =
      attrs[:stylesheet] ||
        attrs["stylesheet"]
        |> to_string()
        |> String.trim()

    if name == "" or label == "" or stylesheet == "" do
      nil
    else
      %{name: name, label: label, stylesheet: stylesheet}
    end
  rescue
    _ -> nil
  end

  defp normalize_theme_definition(_attrs), do: nil

  defp persist_and_return(new_config, result) do
    case persist_instance_config(new_config |> bump_asset_version()) do
      :ok -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp preserve_hidden_instance_state(overrides, current) do
    overrides
    |> maybe_preserve_key(current, :template_themes)
    |> maybe_preserve_nested_key(current, :themes, :page_enabled)
  end

  defp maybe_preserve_key(overrides, current, key) do
    if Map.has_key?(overrides, key) or not Map.has_key?(current, key) do
      overrides
    else
      Map.put(overrides, key, Map.get(current, key))
    end
  end

  defp maybe_preserve_nested_key(overrides, current, parent, child) do
    current_parent = Map.get(current, parent)
    override_parent = Map.get(overrides, parent)

    cond do
      not is_map(current_parent) ->
        overrides

      is_map(override_parent) and Map.has_key?(override_parent, child) ->
        overrides

      not Map.has_key?(current_parent, child) ->
        overrides

      true ->
        Map.put(
          overrides,
          parent,
          Map.put(override_parent || %{}, child, Map.get(current_parent, child))
        )
    end
  end

  defp put_themes_config(config, updates) do
    Map.put(config, :themes, Map.merge(Map.get(config, :themes, %{}), updates))
  end

  defp bump_asset_version(config) do
    Map.put(config, :asset_version, Integer.to_string(System.system_time(:millisecond)))
  end

  defp cache_key(base_key), do: {base_key, config_path()}

  defp clear_cache_entry(base_key) do
    :persistent_term.erase(cache_key(base_key))
    :ok
  rescue
    ArgumentError -> :ok
  end
end
