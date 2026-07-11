defmodule EirinchanWeb.ChangesetErrors do
  @moduledoc false

  def translate(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
        opts
        |> Enum.find_value(key, fn {option, value} ->
          if to_string(option) == key, do: to_string(value)
        end)
      end)
    end)
  end
end
