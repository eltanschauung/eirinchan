defmodule Eirinchan.FailureWindowTest do
  use ExUnit.Case, async: true

  alias Eirinchan.FailureWindow

  setup do
    %{table: :ets.new(:failure_window_test, [:set, :public])}
  end

  test "retains partial counts for the full configured window", %{table: table} do
    assert :ok = FailureWindow.record(table, [{:key, 5}], 10_000, 7_200, 60, 10)
    assert FailureWindow.prune(table, 13_601) == 0
    assert :ets.member(table, :key)
    assert FailureWindow.prune(table, 17_200) == 1
  end

  test "retains a lock until its configured expiry", %{table: table} do
    assert {:error, 7_200} = FailureWindow.record(table, [{:key, 1}], 10_000, 10, 7_200, 10)
    assert FailureWindow.prune(table, 13_601) == 0
    assert {:error, 3_599} = FailureWindow.allowed?(table, [:key], 13_601)
    assert FailureWindow.prune(table, 17_200) == 1
    assert :ok = FailureWindow.allowed?(table, [:key], 17_200)
  end

  test "a fresh window applies a one-attempt threshold immediately", %{table: table} do
    assert {:error, 10} = FailureWindow.record(table, [{:key, 1}], 10_000, 60, 10, 10)
    assert {:error, 10} = FailureWindow.record(table, [{:key, 1}], 10_061, 60, 10, 10)
  end

  test "a full table fails closed for new identities", %{table: table} do
    assert :ok = FailureWindow.record(table, [{:first, 5}], 10_000, 60, 30, 1)
    assert {:error, 30} = FailureWindow.record(table, [{:second, 5}], 10_000, 60, 30, 1)
    assert :ets.info(table, :size) == 1
  end

  test "existing four-field counters remain valid across code reload", %{table: table} do
    :ets.insert(table, {:old, 2, 10_000, 0})
    assert {:error, 60} = FailureWindow.record(table, [{:old, 3}], 10_001, 300, 60, 10)
    assert :ok = FailureWindow.allowed?(table, [:old], 10_061)
    assert [{:old, 3, 10_000, 10_061, _expires}] = :ets.lookup(table, :old)

    :ets.insert(table, {:locked_old, 3, 10_000, 10_020})
    assert {:error, 19} = FailureWindow.allowed?(table, [:locked_old], 10_001)
  end
end
