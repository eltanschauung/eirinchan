defmodule EirinchanWeb.ParamTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.Param

  test "parses only complete integer parameters" do
    assert Param.integer(" 42 ") == {:ok, 42}
    assert Param.integer(7) == {:ok, 7}
    assert Param.integer("42oops") == :error
    assert Param.integer(nil) == :error
  end

  test "bounds resource-sensitive integers and defaults malformed values" do
    assert Param.bounded_integer("50", 25, min: 1, max: 100) == 50
    assert Param.bounded_integer("999999", 25, min: 1, max: 100) == 100
    assert Param.bounded_integer("-5", 25, min: 1, max: 100) == 1
    assert Param.bounded_integer("invalid", 25, min: 1, max: 100) == 25
  end

  test "accepts only positive PostgreSQL integer identifiers" do
    assert Param.database_id("2147483647") == {:ok, 2_147_483_647}
    assert Param.database_id("2147483648") == :error
    assert Param.database_id(0) == :error
    assert Param.database_id("invalid") == :error
  end
end
