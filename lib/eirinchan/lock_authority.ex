defmodule Eirinchan.LockAuthority do
  @moduledoc false
  @key {__MODULE__, :authority}

  # A replacement lock server has forgotten live operations. A deliberate
  # application restart drains old request processes before capturing it.
  def initialize do
    :persistent_term.put(@key, Process.whereis(:global_name_server))
    :ok
  end

  def available? do
    expected = :persistent_term.get(@key, nil)

    is_pid(expected) and Process.alive?(expected) and
      Process.whereis(:global_name_server) == expected
  end
end
