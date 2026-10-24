defmodule Eirinchan.MediaProcessingTest do
  use ExUnit.Case, async: false
  alias Eirinchan.MediaProcessing

  setup do
    server = start_supervised!({MediaProcessing, name: __MODULE__})
    %{server: server}
  end

  test "admission is bounded and nested work reuses the current slot", %{server: server} do
    parent = self()

    task =
      Task.async(fn ->
        MediaProcessing.run(
          fn ->
            send(parent, {:started, self()})

            receive do
              :finish -> MediaProcessing.run(fn -> :nested end, server: server, limit: 1)
            end
          end,
          server: server,
          limit: 1
        )
      end)

    assert_receive {:started, worker}

    assert MediaProcessing.run(fn -> flunk("excess job was admitted") end,
             server: server,
             limit: 1
           ) == {:error, :media_busy}

    send(worker, :finish)
    assert Task.await(task) == :nested
    assert MediaProcessing.run(fn -> :next end, server: server, limit: 1) == :next
  end

  test "dead requester retains admission until its worker finishes and cleans abandoned results",
       %{server: server} do
    parent = self()

    owner =
      spawn(fn ->
        MediaProcessing.run(
          fn ->
            send(parent, {:started, self()})

            receive do
              :finish -> {:ok, :prepared_fixture}
            end
          end,
          server: server,
          limit: 1,
          cleanup: fn value -> send(parent, {:cleaned, value}) end
        )
      end)

    assert_receive {:started, worker}
    Process.exit(owner, :kill)

    assert MediaProcessing.run(fn -> :not_admitted end, server: server, limit: 1) ==
             {:error, :media_busy}

    send(worker, :finish)
    assert_receive {:cleaned, {:ok, :prepared_fixture}}
    assert MediaProcessing.run(fn -> :next end, server: server, limit: 1) == :next
  end

  test "exceptions release admission without crashing the gate", %{server: server} do
    assert_raise RuntimeError, "fixture error", fn ->
      MediaProcessing.run(fn -> raise "fixture error" end, server: server, limit: 1)
    end

    assert MediaProcessing.run(fn -> :next end, server: server, limit: 1) == :next
  end
end
