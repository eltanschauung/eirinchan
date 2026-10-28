defmodule Eirinchan.AuthAdmissionTest do
  use ExUnit.Case, async: false
  alias Eirinchan.AuthAdmission

  test "an uninitialized or replaced authority fails closed" do
    key = {Eirinchan.LockAuthority, :authority}
    original = :persistent_term.get(key)

    try do
      for invalid <- [nil, self()] do
        :persistent_term.put(key, invalid)

        assert {:error, :unavailable} =
                 AuthAdmission.acquire(make_ref(), [:identity], 1, fn ->
                   flunk("verification admitted")
                 end)
      end
    after
      :persistent_term.put(key, original)
    end
  end

  test "rejected and raised admission checks release every acquired lock" do
    family = make_ref()
    assert {:error, 7} = AuthAdmission.acquire(family, [:identity], 1, fn -> {:error, 7} end)

    assert_raise RuntimeError, "synthetic", fn ->
      AuthAdmission.acquire(family, [:identity], 1, fn -> raise "synthetic" end)
    end

    assert {:ok, lease} = AuthAdmission.acquire(family, [:identity], 1, fn -> :ok end)
    assert :ok = AuthAdmission.release(lease)
  end

  test "an unavailable counter authority fails closed without leaking a slot" do
    family = make_ref()

    assert {:error, :unavailable} =
             AuthAdmission.acquire(family, [:identity], 1, fn -> exit(:noproc) end)

    assert {:ok, lease} = AuthAdmission.acquire(family, [:identity], 1, fn -> :ok end)
    assert :ok = AuthAdmission.release(lease)
  end

  test "failure authority restart does not forget an in-flight request" do
    family = make_ref()
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    monitor = Process.monitor(owner)

    assert {:ok, lease} =
             AuthAdmission.acquire(family, [:identity], 1, fn ->
               assert Process.alive?(owner)
               :ok
             end)

    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    replacement = spawn(fn -> receive do: (:stop -> :ok) end)

    try do
      assert {:error, 1} =
               AuthAdmission.acquire(family, [:identity], 1, fn ->
                 assert Process.alive?(replacement)
                 :ok
               end)
    after
      AuthAdmission.release(lease)
      send(replacement, :stop)
    end
  end

  test "partial identity allocation is rolled back without releasing another caller" do
    family = make_ref()
    assert {:ok, first} = AuthAdmission.acquire(family, [:b], 3, fn -> :ok end)
    assert {:error, 1} = AuthAdmission.acquire(family, [:a, :b], 3, fn -> :ok end)
    assert {:ok, other} = AuthAdmission.acquire(family, [:a], 3, fn -> :ok end)
    AuthAdmission.release(other)
    AuthAdmission.release(first)
  end
end
