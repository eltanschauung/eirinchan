defmodule Eirinchan.TripcodeFailureSecurityTest do
  use ExUnit.Case, async: false

  test "unavailable tripcode helper never publishes the secret as part of the name" do
    path = System.get_env("PATH")

    try do
      System.put_env("PATH", "/nonexistent-eirinchan-test-bin")

      assert Eirinchan.Tripcode.split_name_and_tripcode("Anon#private-fixture", %{}) ==
               {"Anon", nil}

      assert Eirinchan.Tripcode.split_name_and_tripcode("Anon##private-fixture", %{}) ==
               {"Anon", nil}

      assert Eirinchan.Tripcode.split_name_and_tripcode("#private-fixture", %{}) == {nil, nil}

      assert Eirinchan.Tripcode.split_name_and_tripcode("ordinary name", %{}) ==
               {"ordinary name", nil}
    after
      if path, do: System.put_env("PATH", path), else: System.delete_env("PATH")
    end
  end
end
