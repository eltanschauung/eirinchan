defmodule Eirinchan.Statistics.Charts do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Statistics
  alias Eirinchan.Statistics.LocalCalendar
  alias Eirinchan.Statistics.Snapshot

  @hour_seconds 3_600
  @last_week_days 7

  def build(board_ids, opts \\ []) when is_list(board_ids) do
    repo = Keyword.get(opts, :repo, Repo)
    calendar = Keyword.get(opts, :calendar, LocalCalendar)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)
    local_now = calendar.local_naive(now)
    today = NaiveDateTime.to_date(local_now)
    yesterday = Date.add(today, -1)
    ppd_start = shift_month(today, -2)
    current_month_start = Date.beginning_of_month(today)
    previous_month_start = current_month_start |> Date.add(-1) |> Date.beginning_of_month()
    previous_month_end = Date.add(current_month_start, -1)
    last_week_start = Date.add(today, -@last_week_days)
    year_start = Date.new!(today.year, 1, 1)

    earliest_date =
      Enum.min_by(
        [ppd_start, previous_month_start, last_week_start, yesterday],
        &Date.to_gregorian_days/1
      )

    range_start = start_of_day(earliest_date, calendar)
    range_end = start_of_day(Date.add(today, 1), calendar)

    retained_posts = retained_posts_by_hour(repo, board_ids, range_start, range_end)

    monthly_posts =
      retained_posts_by_month(
        repo,
        board_ids,
        start_of_day(year_start, calendar),
        range_end,
        calendar
      )

    snapshots = snapshots(repo, range_start, range_end)
    hourly_posts = hourly_posts(retained_posts, snapshots, range_start, range_end, now, calendar)
    daily_visitors = daily_visitors(snapshots, calendar)

    current_visitors =
      Keyword.get_lazy(opts, :current_visitors, fn ->
        current_day_visitors(repo, start_of_day(today, calendar), now)
      end)

    charts = [
      pph_chart(today, "Posts Per Hour - #{date_title(today)}", hourly_posts, local_now),
      pph_chart(yesterday, "Posts Per Hour - #{date_title(yesterday)}", hourly_posts, local_now),
      ppd_chart(ppd_start, today, hourly_posts),
      posts_per_month_chart(today, monthly_posts),
      visitors_chart(
        current_month_start,
        Date.end_of_month(today),
        today,
        daily_visitors,
        current_visitors,
        "Visitors Per Day - #{Calendar.strftime(today, "%B")}",
        "visitors-current-month"
      ),
      visitors_chart(
        previous_month_start,
        previous_month_end,
        today,
        daily_visitors,
        current_visitors,
        "Visitors Per Day - Last Month",
        "visitors-last-month"
      ),
      average_visitors_chart(last_week_start, yesterday, snapshots, calendar),
      average_posts_chart(last_week_start, yesterday, hourly_posts)
    ]

    %{
      charts: charts,
      generated_at: now,
      coverage: coverage(charts)
    }
  end

  defp retained_posts_by_hour(_repo, [], _range_start, _range_end), do: %{}

  defp retained_posts_by_hour(repo, board_ids, range_start, range_end) do
    repo.all(
      from post in Post,
        where:
          post.board_id in ^board_ids and post.inserted_at >= ^range_start and
            post.inserted_at < ^range_end,
        group_by: fragment("date_trunc('hour', ?)", post.inserted_at),
        select: {fragment("date_trunc('hour', ?)", post.inserted_at), count(post.id)}
    )
    |> Map.new(fn {period_start, count} -> {hour_key(period_start), count} end)
  end

  defp retained_posts_by_month(_repo, [], _range_start, _range_end, _calendar), do: %{}

  defp retained_posts_by_month(repo, board_ids, range_start, range_end, calendar) do
    repo.all(
      from post in Post,
        where:
          post.board_id in ^board_ids and post.inserted_at >= ^range_start and
            post.inserted_at < ^range_end,
        group_by: fragment("date_trunc('hour', ?)", post.inserted_at),
        select: {fragment("date_trunc('hour', ?)", post.inserted_at), count(post.id)}
    )
    |> Enum.reduce(%{}, fn {utc_hour, count}, totals ->
      local = utc_hour |> utc_datetime() |> calendar.local_naive()
      date = NaiveDateTime.to_date(local)
      Map.update(totals, {date.year, date.month}, count, &(&1 + count))
    end)
  end

  defp snapshots(repo, range_start, range_end) do
    repo.all(
      from snapshot in Snapshot,
        where:
          snapshot.period_start >= ^range_start and snapshot.period_start < ^range_end and
            snapshot.finalized,
        order_by: snapshot.period_start,
        select: %{
          period_start: snapshot.period_start,
          period_end: snapshot.period_end,
          posts_per_hour: snapshot.posts_per_hour,
          users_10minutes: snapshot.users_10minutes,
          daily_unique_visitors: snapshot.daily_unique_visitors,
          counters: snapshot.counters
        }
    )
  end

  defp hourly_posts(retained, snapshots, range_start, range_end, now, calendar) do
    tracked =
      Map.new(snapshots, fn snapshot ->
        {hour_key(snapshot.period_start),
         %{value: snapshot.posts_per_hour, source: snapshot_source(snapshot)}}
      end)

    current_hour = Statistics.hour_start(now)
    last_hour = DateTime.add(range_end, -@hour_seconds, :second)

    effective_last_hour =
      if DateTime.before?(current_hour, last_hour), do: current_hour, else: last_hour

    range_start
    |> hour_stream(effective_last_hour)
    |> Enum.reduce(%{}, fn utc_hour, totals ->
      utc_key = hour_key(utc_hour)
      local = calendar.local_naive(utc_hour)
      local_key = {NaiveDateTime.to_date(local), local.hour}

      {value, source} =
        cond do
          utc_key == hour_key(current_hour) ->
            {Map.get(retained, utc_key, 0), :partial}

          is_integer(get_in(tracked, [utc_key, :value])) ->
            total = Map.fetch!(tracked, utc_key)
            {total.value, total.source}

          true ->
            {Map.get(retained, utc_key, 0), :reconstructed}
        end

      Map.update(
        totals,
        local_key,
        %{value: value, sources: MapSet.new([source])},
        fn total ->
          %{
            value: total.value + value,
            sources: MapSet.put(total.sources, source)
          }
        end
      )
    end)
  end

  defp pph_chart(date, title, hourly_posts, local_now) do
    points =
      Enum.map(0..23, fn hour ->
        total = Map.get(hourly_posts, {date, hour})

        state =
          cond do
            Date.after?(date, NaiveDateTime.to_date(local_now)) -> :future
            date == NaiveDateTime.to_date(local_now) and hour > local_now.hour -> :future
            is_nil(total) -> :unavailable
            true -> source_state(total.sources)
          end

        point(
          hour_label(hour),
          if(state == :future, do: 0, else: total_value(total)),
          state,
          title_label: time_title(hour)
        )
      end)

    chart("pph-#{Date.to_iso8601(date)}", title, points, coverage_note(points))
  end

  defp ppd_chart(start_date, end_date, hourly_posts) do
    points =
      start_date
      |> Date.range(end_date)
      |> Enum.map(fn date ->
        totals =
          0..23
          |> Enum.map(&Map.get(hourly_posts, {date, &1}))
          |> Enum.reject(&is_nil/1)

        sources = Enum.reduce(totals, MapSet.new(), &MapSet.union(&2, &1.sources))
        value = Enum.reduce(totals, 0, &(&1.value + &2))
        state = if totals == [], do: :unavailable, else: source_state(sources)

        point("#{date.month}/#{date.day}", value, state, title_label: date_title(date))
      end)

    chart(
      "posts-per-day-past-two-months",
      "Posts Per Day - Past 2 Months",
      points,
      coverage_note(points)
    )
  end

  defp posts_per_month_chart(today, monthly_posts) do
    current_month = Date.beginning_of_month(today)

    points =
      Enum.map(1..12, fn month ->
        date = Date.new!(today.year, month, 1)
        retained = Map.get(monthly_posts, {today.year, month}, 0)

        {value, state} =
          cond do
            Date.after?(date, current_month) -> {nil, :future}
            month == 7 -> {retained, :reconstructed}
            true -> {round(retained * 1.15), :estimated}
          end

        point(Calendar.strftime(date, "%B"), value, state,
          title_label: Calendar.strftime(date, "%B")
        )
      end)

    chart(
      "posts-per-month-#{today.year}",
      "Posts Per Month - #{today.year}",
      points,
      nil
    )
  end

  defp daily_visitors(snapshots, calendar) do
    snapshots
    |> Enum.reject(&is_nil(&1.daily_unique_visitors))
    |> Map.new(fn snapshot ->
      local_period_end = calendar.local_naive(snapshot.period_end)
      date = local_period_end |> NaiveDateTime.to_date() |> Date.add(-1)
      {date, %{value: snapshot.daily_unique_visitors, state: snapshot_source(snapshot)}}
    end)
  end

  defp current_day_visitors(repo, day_start, now) do
    repo.aggregate(
      from(identity in Identity,
        where: identity.presence_seen_at >= ^day_start and identity.presence_seen_at <= ^now
      ),
      :count,
      :browser_ref
    ) || 0
  end

  defp visitors_chart(
         start_date,
         end_date,
         today,
         daily_visitors,
         current_visitors,
         title,
         id
       ) do
    points =
      start_date
      |> Date.range(end_date)
      |> Enum.map(fn date ->
        cond do
          Date.after?(date, today) ->
            point(ordinal_day(date.day), nil, :future, title_label: date_title(date))

          date == today ->
            point(ordinal_day(date.day), current_visitors, :partial,
              title_label: date_title(date)
            )

          Map.has_key?(daily_visitors, date) ->
            total = Map.fetch!(daily_visitors, date)

            point(ordinal_day(date.day), total.value, total.state, title_label: date_title(date))

          true ->
            point(ordinal_day(date.day), nil, :unavailable, title_label: date_title(date))
        end
      end)

    chart(id, title, points, coverage_note(points))
  end

  defp average_visitors_chart(start_date, end_date, snapshots, calendar) do
    by_hour =
      snapshots
      |> Enum.reject(&is_nil(&1.users_10minutes))
      |> Enum.reduce(%{}, fn snapshot, totals ->
        local = calendar.local_naive(snapshot.period_start)
        date = NaiveDateTime.to_date(local)

        if Date.compare(date, start_date) in [:eq, :gt] and
             Date.compare(date, end_date) in [:eq, :lt] do
          Map.update(
            totals,
            local.hour,
            [snapshot.users_10minutes],
            &[
              snapshot.users_10minutes | &1
            ]
          )
        else
          totals
        end
      end)

    points =
      Enum.map(0..23, fn hour ->
        samples = Map.get(by_hour, hour, [])

        case samples do
          [] ->
            point(hour_label(hour), nil, :unavailable,
              samples: 0,
              title_label: time_title(hour)
            )

          values ->
            average = values |> Enum.sum() |> Kernel./(length(values)) |> Float.round(1)
            state = if length(values) == @last_week_days, do: :tracked, else: :incomplete

            point(hour_label(hour), average, state,
              samples: length(values),
              title_label: time_title(hour)
            )
        end
      end)

    chart(
      "average-visitors-per-hour-last-week",
      "Average Visitors Per Hour - Last Week",
      points,
      coverage_note(points)
    )
  end

  defp average_posts_chart(start_date, end_date, hourly_posts) do
    points =
      Enum.map(0..23, fn hour ->
        totals =
          start_date
          |> Date.range(end_date)
          |> Enum.map(&Map.get(hourly_posts, {&1, hour}))
          |> Enum.reject(&is_nil/1)

        case totals do
          [] ->
            point(hour_label(hour), nil, :unavailable,
              samples: 0,
              title_label: time_title(hour)
            )

          totals ->
            average =
              totals
              |> Enum.reduce(0, &(&1.value + &2))
              |> Kernel./(length(totals))
              |> Float.round(1)

            sources = Enum.reduce(totals, MapSet.new(), &MapSet.union(&2, &1.sources))

            state =
              if length(totals) == @last_week_days,
                do: source_state(sources),
                else: :incomplete

            point(hour_label(hour), average, state,
              samples: length(totals),
              title_label: time_title(hour)
            )
        end
      end)

    chart(
      "average-posts-per-hour-last-week",
      "Average Posts Per Hour - Last Week",
      points,
      coverage_note(points)
    )
  end

  defp chart(id, title, points, note) do
    numeric_values = points |> Enum.map(& &1.value) |> Enum.filter(&is_number/1)
    maximum = Enum.max(numeric_values, fn -> 0 end)
    scale = max(maximum, 1)

    points =
      Enum.map(points, fn chart_point ->
        bar_percent =
          if is_number(chart_point.value),
            do: Float.round(chart_point.value / scale * 100, 2),
            else: 0

        Map.put(chart_point, :bar_percent, bar_percent)
      end)

    %{
      id: id,
      title: title,
      points: points,
      column_count: length(points),
      maximum: maximum,
      note: note
    }
  end

  defp point(label, value, state, extra) do
    value_text =
      cond do
        is_nil(value) -> "—"
        is_float(value) -> :erlang.float_to_binary(value, decimals: 1)
        true -> Integer.to_string(value)
      end

    %{
      label: label,
      title_label: Keyword.get(extra, :title_label, label),
      value: value,
      value_text: value_text,
      state: state,
      samples: Keyword.get(extra, :samples)
    }
  end

  defp coverage(charts) do
    Map.new(charts, fn chart ->
      counts = Enum.frequencies_by(chart.points, & &1.state)
      {chart.id, counts}
    end)
  end

  defp coverage_note(points) do
    states = MapSet.new(points, & &1.state)

    cond do
      MapSet.member?(states, :estimated) and MapSet.member?(states, :reconstructed) ->
        "Data before July 19th 2026 is only approximate, backfilled by analysis of /bant/ post integers and timestamps."

      MapSet.member?(states, :estimated) ->
        "Data before July 19th 2026 is only approximate, backfilled by analysis of /bant/ post integers and timestamps."

      MapSet.member?(states, :reconstructed) ->
        "Hours predating complete snapshots are reconstructed from retained posts; posts deleted before collection are not recoverable."

      MapSet.member?(states, :unavailable) and MapSet.member?(states, :incomplete) ->
        "Unavailable columns were not tracked; other columns average the available hourly samples."

      MapSet.member?(states, :unavailable) ->
        "Unavailable columns predate tracking or have no completed snapshot."

      MapSet.member?(states, :incomplete) ->
        "Some columns average fewer than seven hourly samples."

      true ->
        nil
    end
  end

  defp source_state(sources) do
    cond do
      MapSet.member?(sources, :partial) -> :partial
      MapSet.member?(sources, :estimated) -> :estimated
      MapSet.member?(sources, :reconstructed) -> :reconstructed
      true -> :tracked
    end
  end

  defp snapshot_source(%{counters: %{"historical_estimate" => true}}), do: :estimated
  defp snapshot_source(_snapshot), do: :tracked

  defp total_value(nil), do: 0
  defp total_value(total), do: total.value

  defp hour_stream(first_hour, last_hour) do
    if DateTime.after?(first_hour, last_hour) do
      []
    else
      Stream.iterate(first_hour, &DateTime.add(&1, @hour_seconds, :second))
      |> Enum.take_while(&(DateTime.compare(&1, last_hour) in [:lt, :eq]))
    end
  end

  defp start_of_day(date, calendar) do
    date
    |> NaiveDateTime.new!(~T[00:00:00])
    |> calendar.utc_datetime()
  end

  defp hour_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :second)

  defp hour_key(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> hour_key()
  end

  defp utc_datetime(%DateTime{} = datetime), do: datetime
  defp utc_datetime(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")

  defp shift_month(%Date{} = date, offset) do
    month_index = date.year * 12 + date.month - 1 + offset
    year = div(month_index, 12)
    month = rem(month_index, 12) + 1
    day = min(date.day, Date.days_in_month(Date.new!(year, month, 1)))
    Date.new!(year, month, day)
  end

  defp date_title(date) do
    "#{Calendar.strftime(date, "%B")} #{date.day}#{ordinal_suffix(date.day)} #{date.year}"
  end

  defp ordinal_suffix(day) when rem(day, 100) in 11..13, do: "th"
  defp ordinal_suffix(day) when rem(day, 10) == 1, do: "st"
  defp ordinal_suffix(day) when rem(day, 10) == 2, do: "nd"
  defp ordinal_suffix(day) when rem(day, 10) == 3, do: "rd"
  defp ordinal_suffix(_day), do: "th"

  defp ordinal_day(day), do: "#{day}#{ordinal_suffix(day)}"

  defp time_title(hour), do: "#{hour |> Integer.to_string() |> String.pad_leading(2, "0")}:00"

  defp hour_label(0), do: "12am"
  defp hour_label(12), do: "12pm"
  defp hour_label(hour) when hour < 12, do: "#{hour}am"
  defp hour_label(hour), do: "#{hour - 12}pm"
end
