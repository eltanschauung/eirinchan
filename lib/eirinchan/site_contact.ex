defmodule Eirinchan.SiteContact do
  @moduledoc false

  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings

  @default_email "example@example.com"

  def email(overrides \\ Settings.current_instance_config()) do
    Config.compose(nil, overrides, %{})
    |> Map.get(:contact_email)
    |> normalize_email()
  end

  defp normalize_email(value) when is_binary(value) do
    case String.trim(value) do
      "" -> @default_email
      email -> email
    end
  end

  defp normalize_email(_value), do: @default_email
end
