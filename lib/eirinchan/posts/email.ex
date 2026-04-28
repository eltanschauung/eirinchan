defmodule Eirinchan.Posts.Email do
  @moduledoc false

  @sage_commands ["sage", "polite sage"]

  def normalize(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> nil
      sage?(trimmed) -> trimmed
      true -> String.replace(trimmed, " ", "%20")
    end
  end

  def normalize(_value), do: nil

  def sage?(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace("%20", " ")
    |> String.downcase()
    |> then(&(&1 in @sage_commands))
  end

  def sage?(_value), do: false
end
