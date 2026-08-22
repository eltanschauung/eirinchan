defmodule Eirinchan.Statistics.Week do
  @moduledoc false

  alias Eirinchan.Statistics.LocalCalendar

  def start_at(%DateTime{} = datetime, calendar \\ LocalCalendar) do
    local = calendar.local_naive(datetime)
    date = NaiveDateTime.to_date(local)
    days_since_sunday = rem(Date.day_of_week(date), 7)

    date
    |> Date.add(-days_since_sunday)
    |> NaiveDateTime.new!(~T[00:00:00])
    |> calendar.utc_datetime()
  end

  def completed_week_start(%DateTime{} = period_end, calendar \\ LocalCalendar) do
    local = calendar.local_naive(period_end)
    date = NaiveDateTime.to_date(local)

    if NaiveDateTime.to_time(local) == ~T[00:00:00] and Date.day_of_week(date) == 7 do
      date
      |> Date.add(-7)
      |> NaiveDateTime.new!(~T[00:00:00])
      |> calendar.utc_datetime()
    end
  end

  def end_at(%DateTime{} = week_start, calendar \\ LocalCalendar) do
    week_start
    |> calendar.local_naive()
    |> NaiveDateTime.to_date()
    |> Date.add(7)
    |> NaiveDateTime.new!(~T[00:00:00])
    |> calendar.utc_datetime()
  end
end
