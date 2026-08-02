defmodule Eirinchan.Statistics.LocalCalendar do
  @moduledoc false

  def local_naive(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_unix(:second)
    |> :calendar.system_time_to_local_time(:second)
    |> NaiveDateTime.from_erl!()
  end

  def utc_datetime(%NaiveDateTime{} = local_datetime) do
    local_datetime
    |> NaiveDateTime.to_erl()
    |> :calendar.local_time_to_universal_time_dst()
    |> case do
      [utc_datetime | _] ->
        utc_datetime
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")

      [] ->
        raise ArgumentError, "local datetime does not exist: #{local_datetime}"
    end
  end
end
