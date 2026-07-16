defmodule EirinchanWeb.ChangesetErrors do
  @moduledoc false

  def translate(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  def translate_error({message, opts}) do
    Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
      opts
      |> Enum.find_value(key, fn {option, value} ->
        if to_string(option) == key, do: to_string(value)
      end)
    end)
  end
end
