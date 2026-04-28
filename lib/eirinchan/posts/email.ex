defmodule Eirinchan.Posts.Email do
  @moduledoc false

  @sage_commands ["sage", "polite sage"]

  def sage?(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in @sage_commands))
  end

  def sage?(_value), do: false
end
