defmodule Eirinchan.CommandTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Command

  test "returns command output" do
    assert {"bounded", 0} = Command.run("printf", ["bounded"], timeout: 1_000)
  end

  test "terminates commands that exceed the deadline" do
    assert {message, 124} = Command.run("sleep", ["5"], timeout: 25)
    assert message =~ "timed out"
  end
end
