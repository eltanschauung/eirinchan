defmodule EirinchanWeb.ChangesetErrorsTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.ChangesetErrors

  test "translates placeholders without converting their names to atoms" do
    changeset =
      {%{}, %{field: :string}}
      |> Ecto.Changeset.cast(%{}, [])
      |> Ecto.Changeset.add_error(
        :field,
        "invalid %{runtime_placeholder}",
        [{"runtime_placeholder", "value"}]
      )

    assert ChangesetErrors.translate(changeset) == %{
             field: ["invalid value"]
           }
  end

  test "translates a single Ecto validation error" do
    assert ChangesetErrors.translate_error(
             {"should be at least %{count} character(s)", count: 12, validation: :length}
           ) == "should be at least 12 character(s)"
  end
end
