defmodule Eirinchan.IpAccessAuth do
  @moduledoc false

  alias Eirinchan.AccessList
  alias Eirinchan.CredentialHash
  alias Eirinchan.IpMatching

  @default_passwords []
  @config_keys %{
    "auth_path" => :auth_path,
    "global_max_attempts" => :global_max_attempts,
    "grant_ttl_hours" => :grant_ttl_hours,
    "lockout_seconds" => :lockout_seconds,
    "max_attempts" => :max_attempts,
    "message" => :message,
    "passwords" => :passwords,
    "theme" => :theme,
    "title" => :title,
    "window_seconds" => :window_seconds
  }

  @type config :: %{
          optional(:auth_path) => binary(),
          optional(:passwords) => binary() | [binary()],
          optional(:message) => binary(),
          optional(:theme) => binary(),
          optional(:title) => binary()
        }

  def default_config do
    %{
      auth_path: "/auth",
      global_max_attempts: 100,
      grant_ttl_hours: 168,
      lockout_seconds: 900,
      max_attempts: 5,
      passwords: @default_passwords,
      message: "Enter a password to gain access.",
      theme: "ipaccessauth",
      title: "IP Access Authentication",
      window_seconds: 300
    }
  end

  def effective_config(config \\ %{}) do
    config
    |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
    |> Map.take([
      :auth_path,
      :global_max_attempts,
      :grant_ttl_hours,
      :lockout_seconds,
      :max_attempts,
      :message,
      :theme,
      :passwords,
      :title,
      :window_seconds
    ])
    |> then(&Map.merge(default_config(), &1))
    |> Map.update!(:auth_path, &normalize_auth_path/1)
    |> Map.update!(:passwords, &normalized_passwords/1)
    |> Map.update!(:message, &normalize_message/1)
    |> Map.update!(:theme, &normalize_theme_name/1)
    |> Map.update!(:title, &normalize_title/1)
    |> Map.update!(:global_max_attempts, &positive_integer(&1, 100))
    |> Map.update!(:grant_ttl_hours, &positive_integer(&1, 168))
    |> Map.update!(:lockout_seconds, &positive_integer(&1, 900))
    |> Map.update!(:max_attempts, &positive_integer(&1, 5))
    |> Map.update!(:window_seconds, &positive_integer(&1, 300))
  end

  def auth_path(config \\ %{}) do
    effective_config(config).auth_path
  end

  def configured_for_path?(request_path, config \\ %{}) when is_binary(request_path) do
    request_path == auth_path(config)
  end

  def authorize(ip, password, config \\ %{})

  def authorize(ip, password, config) when is_binary(password) do
    config = effective_config(config)
    normalized_password = password |> String.trim() |> String.downcase()
    passwords = normalized_passwords(Map.get(config, :passwords, @default_passwords))

    cond do
      normalized_password == "" ->
        {:error, :password_required}

      passwords == [] ->
        {:error, :invalid_password}

      not Enum.any?(passwords, &CredentialHash.verify(normalized_password, &1, :ip_access)) ->
        {:error, :invalid_password}

      true ->
        do_authorize(ip, normalized_password, config)
    end
  end

  def subnet_for_ip(ip) do
    with {:ok, parsed} <- IpMatching.parse_ip(ip) do
      case parsed do
        {a, b, c, _d} ->
          {:ok, "#{a}.#{b}.#{c}.0/24"}

        {a, b, c, _d, _e, _f, _g, _h} ->
          {:ok,
           "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:#{Integer.to_string(c, 16)}::/48"
           |> String.downcase()}
      end
    else
      _ -> {:error, :invalid_ip}
    end
  end

  defp do_authorize(ip, normalized_password, config) do
    with {:ok, subnet} <- subnet_for_ip(ip),
         {:ok, _entry} <-
           AccessList.record_access(subnet, normalized_password,
             grant_ttl_hours: config.grant_ttl_hours
           ) do
      {:ok, %{subnet: subnet}}
    else
      {:error, :invalid_ip} -> {:error, :invalid_ip}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.replace("-", "_")
    |> then(&Map.get(@config_keys, &1, &1))
  end

  defp normalize_key(key), do: key

  defp normalize_auth_path(path) do
    path =
      path
      |> to_string()
      |> String.trim()
      |> String.replace("\\", "/")

    if path == "" or path == "/" do
      "/auth"
    else
      cleaned = "/" <> String.trim(path, "/")

      if String.contains?(cleaned, "..") do
        "/auth"
      else
        cleaned
      end
    end
  end

  defp normalize_message(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> default_config().message
      message -> message
    end
  end

  defp normalize_theme_name(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> default_config().theme
      theme -> theme
    end
  end

  defp normalize_title(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> default_config().title
      title -> title
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp normalized_passwords(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.join(",")
    |> normalized_passwords()
  end

  defp normalized_passwords(value) do
    passwords =
      value
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn password ->
        if CredentialHash.encoded?(password), do: password, else: String.downcase(password)
      end)
      |> Enum.uniq()

    passwords
  end
end
