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

  test "output is bounded and over-limit output fails instead of being accepted as valid metadata" do
    assert {message, 125} =
             Command.run("printf", [String.duplicate("x", 10_000)], max_output_bytes: 100)

    assert message =~ "exceeded 100 bytes"
    assert {"after", 0} = Command.run("printf", ["after"])
  end

  test "command arguments remain literal and missing executables fail closed" do
    assert {"$(not-a-command); literal", 0} =
             Command.run("printf", ["%s", "$(not-a-command); literal"])

    assert {"Command executable unavailable", 127} =
             Command.run("eirinchan-test-no-such-command", [])
  end

  test "deadline kills a process group rather than waiting for a sleeping descendant" do
    started = System.monotonic_time(:millisecond)
    assert {_message, 124} = Command.run("sh", ["-c", "sleep 5 & wait"], timeout: 25)
    assert System.monotonic_time(:millisecond) - started < 2_000
  end
end
