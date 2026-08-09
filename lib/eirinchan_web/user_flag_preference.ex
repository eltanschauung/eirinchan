defmodule EirinchanWeb.UserFlagPreference do
  @moduledoc false

  @cookie_name "eirinchan_user_flag"
  @max_length 300

  def cookie_name, do: @cookie_name

  def allowed_values(config) when is_map(config) do
    config
    |> user_flags()
    |> Map.keys()
    |> Kernel.++(["country", fallback_country_code(config)])
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def value(%Plug.Conn{} = conn, config) when is_map(config) do
    default = default_value(config)

    if Map.get(config, :user_flag, false) do
      conn = Plug.Conn.fetch_cookies(conn)

      case Map.get(conn.req_cookies, @cookie_name) do
        candidate when is_binary(candidate) ->
          case normalize(candidate, config) do
            {:ok, normalized} -> normalized
            :error -> default
          end

        _missing ->
          default
      end
    else
      default
    end
  end

  def value(_conn, config) when is_map(config), do: default_value(config)

  def normalize(candidate, config) when is_binary(candidate) and is_map(config) do
    if String.valid?(candidate) and String.length(candidate) <= @max_length do
      normalized = String.trim(candidate)

      if normalized == "" do
        {:ok, ""}
      else
        flags =
          if Map.get(config, :multiple_flags, false) do
            normalized
            |> String.split(",", trim: false)
            |> Enum.map(&(String.trim(&1) |> String.downcase()))
            |> Enum.reject(&(&1 == ""))
          else
            [String.downcase(normalized)]
          end

        if flags != [] and Enum.all?(flags, &allowed?(&1, config)) do
          {:ok, Enum.join(flags, ",")}
        else
          :error
        end
      end
    else
      :error
    end
  end

  def normalize(_candidate, _config), do: :error

  defp default_value(config) do
    candidate = Map.get(config, :default_user_flag, "country")

    case normalize(to_string(candidate || "country"), config) do
      {:ok, normalized} when normalized != "" -> normalized
      _other -> "country"
    end
  end

  defp allowed?("country", _config), do: true

  defp allowed?(flag, config) do
    flag in allowed_values(config)
  end

  defp fallback_country_code(config) do
    config
    |> Map.get(:country_flag_fallback, %{})
    |> case do
      fallback when is_map(fallback) -> Map.get(fallback, :code) || Map.get(fallback, "code")
      _other -> nil
    end
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp user_flags(config) do
    config
    |> Map.get(:user_flags, %{})
    |> case do
      flags when is_map(flags) -> flags
      _other -> %{}
    end
    |> Enum.into(%{}, fn {flag, label} ->
      {flag |> to_string() |> String.trim() |> String.downcase(), label}
    end)
  end
end
