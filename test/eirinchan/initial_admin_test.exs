defmodule Eirinchan.InitialAdminTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.InitialAdmin

  test "creates exactly one all-board administrator with Argon2id credentials" do
    assert {:ok, admin} = InitialAdmin.create("first-admin", "correct horse battery staple")

    assert admin.username == "first-admin"
    assert admin.role == "admin"
    assert admin.all_boards
    assert admin.password_salt == "argon2id:v1"
    assert String.starts_with?(admin.password_hash, "$argon2id$")

    assert {:error, :administrator_exists} =
             InitialAdmin.create("second-admin", "another long password")
  end

  test "returns normal credential validation errors" do
    assert {:error, changeset} = InitialAdmin.create("", "short")
    assert "can't be blank" in errors_on(changeset).username
    assert "should be at least 12 character(s)" in errors_on(changeset).password
  end
end
