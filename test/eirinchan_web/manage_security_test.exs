defmodule EirinchanWeb.ManageSecurityTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.ManageSecurity

  test "action tokens retain 128 bits of the session-bound MAC" do
    token = ManageSecurity.sign_action("session secret", "bant/delete/42")

    assert byte_size(token) == 32
    assert ManageSecurity.valid_action_token?("session secret", "bant/delete/42", token)
    refute ManageSecurity.valid_action_token?("session secret", "bant/delete/43", token)
    refute ManageSecurity.valid_action_token?("other session", "bant/delete/42", token)
  end
end
