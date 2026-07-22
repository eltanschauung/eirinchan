defmodule Eirinchan.Statistics.Report do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.Repo
  alias Eirinchan.Statistics
  alias Eirinchan.Statistics.Snapshot
  alias Eirinchan.Settings

  @challenge_step_percent 80

  def build(hours, opts \\ []) when is_integer(hours) and hours > 0 do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)
    as_of = Statistics.hour_start(now)
    current_start = DateTime.add(as_of, -hours * 3_600, :second)
    previous_start = DateTime.add(current_start, -hours * 3_600, :second)

    snapshots =
      repo.all(
        from snapshot in Snapshot,
          where:
            snapshot.finalized and snapshot.period_start >= ^previous_start and
              snapshot.period_start < ^as_of,
          order_by: [asc: snapshot.period_start]
      )

    {previous, current} =
      Enum.split_with(snapshots, &DateTime.before?(&1.period_start, current_start))

    current_window = summarize(current, current_start, as_of, hours)
    previous_window = summarize(previous, previous_start, current_start, hours)

    %{
      version: 1,
      enabled: Statistics.enabled?(),
      generated_at: DateTime.to_iso8601(now),
      timeframe_hours: hours,
      as_of: DateTime.to_iso8601(as_of),
      current: current_window,
      previous: previous_window,
      traffic_comparison: traffic_comparison(current_window, previous_window, hours, opts),
      current_hour: current_hour(repo, as_of, now)
    }
  end

  defp summarize(snapshots, period_start, period_end, expected_snapshots) do
    counters = aggregate_counters(snapshots)
    visitors = Enum.map(snapshots, &(&1.users_10minutes || 0))

    %{
      period_start: DateTime.to_iso8601(period_start),
      period_end: DateTime.to_iso8601(period_end),
      expected_snapshots: expected_snapshots,
      snapshot_count: length(snapshots),
      complete: length(snapshots) == expected_snapshots,
      posts: Enum.reduce(snapshots, 0, &((&1.posts_per_hour || 0) + &2)),
      threads: Enum.reduce(snapshots, 0, &((&1.threads_per_hour || 0) + &2)),
      visitors_10minutes: visitor_summary(visitors),
      requests: Map.get(counters, "requests.total", 0),
      rate_limits: prefixed_counters(counters, "rate_limits."),
      search: search_summary(counters),
      counters: counters,
      snapshots: Enum.map(snapshots, &serialize_snapshot/1)
    }
  end

  defp traffic_comparison(current, previous, hours, opts) do
    current_requests = current.requests
    previous_requests = previous.requests
    complete = current.complete and previous.complete
    change_percent = percentage_change(current_requests, previous_requests)

    challenge_step_percent = challenge_step_percent(opts)

    challenge_increment =
      if complete and previous_requests > 0 and current_requests > previous_requests do
        div(
          (current_requests - previous_requests) * 100,
          previous_requests * challenge_step_percent
        )
      else
        0
      end

    %{
      metric: "requests.total",
      timeframe_hours: hours,
      baseline_complete: complete,
      current_requests: current_requests,
      previous_requests: previous_requests,
      change_percent: change_percent,
      challenge_step_percent: challenge_step_percent,
      suggested_challenge_increment: challenge_increment
    }
  end

  defp challenge_step_percent(opts) do
    config = Keyword.get(opts, :config, Settings.effective_instance_config())

    case Map.get(config, :statistics_challenge_step_percent, @challenge_step_percent) do
      value when is_integer(value) and value > 0 -> min(value, 10_000)
      _other -> @challenge_step_percent
    end
  end

  defp current_hour(repo, as_of, now) do
    snapshot = repo.get_by(Snapshot, period_start: as_of)

    %{
      period_start: DateTime.to_iso8601(as_of),
      elapsed_seconds: max(DateTime.diff(now, as_of, :second), 0),
      requests: if(snapshot, do: Map.get(snapshot.counters || %{}, "requests.total", 0), else: 0),
      search: search_summary(if(snapshot, do: snapshot.counters || %{}, else: %{})),
      counters: if(snapshot, do: snapshot.counters || %{}, else: %{})
    }
  end

  defp aggregate_counters(snapshots) do
    Enum.reduce(snapshots, %{}, fn snapshot, aggregate ->
      Map.merge(aggregate, snapshot.counters || %{}, fn _key, left, right -> left + right end)
    end)
  end

  defp prefixed_counters(counters, prefix) do
    counters
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, prefix) end)
    |> Map.new(fn {key, value} -> {String.replace_prefix(key, prefix, ""), value} end)
  end

  defp search_summary(counters) do
    %{
      attempts: Map.get(counters, "search.attempts", 0),
      outcomes: prefixed_counters(counters, "search.outcomes."),
      features: prefixed_counters(counters, "search.features."),
      scopes: prefixed_counters(counters, "search.scope."),
      boards: prefixed_counters(counters, "search.boards."),
      modes: prefixed_counters(counters, "search.modes."),
      result_buckets: prefixed_counters(counters, "search.results."),
      clients: %{
        networks: ranked_counters(counters, "search.clients.network."),
        user_agents: ranked_counters(counters, "search.clients.user_agent."),
        combined: ranked_counters(counters, "search.clients.combined."),
        network_features: ranked_client_features(counters, "search.client_features.network."),
        user_agent_features:
          ranked_client_features(counters, "search.client_features.user_agent."),
        combined_features: ranked_client_features(counters, "search.client_features.combined.")
      }
    }
  end

  defp ranked_counters(counters, prefix) do
    counters
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, prefix) end)
    |> Enum.map(fn {key, count} ->
      %{identifier: String.replace_prefix(key, prefix, ""), count: count}
    end)
    |> Enum.sort_by(&{-&1.count, &1.identifier})
  end

  defp ranked_client_features(counters, prefix) do
    counters
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, prefix) end)
    |> Enum.map(fn {key, count} ->
      case key |> String.replace_prefix(prefix, "") |> String.split(".", parts: 2) do
        [identifier, feature] -> %{identifier: identifier, feature: feature, count: count}
        [identifier] -> %{identifier: identifier, feature: nil, count: count}
      end
    end)
    |> Enum.sort_by(&{-&1.count, &1.identifier, &1.feature || ""})
  end

  defp visitor_summary([]), do: %{latest: 0, average: 0.0, maximum: 0}

  defp visitor_summary(values) do
    %{
      latest: List.last(values),
      average: Float.round(Enum.sum(values) / length(values), 2),
      maximum: Enum.max(values)
    }
  end

  defp percentage_change(0, 0), do: 0.0
  defp percentage_change(_current, 0), do: nil

  defp percentage_change(current, previous) do
    Float.round((current - previous) * 100 / previous, 2)
  end

  defp serialize_snapshot(snapshot) do
    %{
      timestamp: DateTime.to_iso8601(snapshot.captured_at || snapshot.period_end),
      period_start: DateTime.to_iso8601(snapshot.period_start),
      period_end: DateTime.to_iso8601(snapshot.period_end),
      posts_per_hour: snapshot.posts_per_hour || 0,
      threads_per_hour: snapshot.threads_per_hour || 0,
      users_10minutes: snapshot.users_10minutes || 0,
      counters: snapshot.counters || %{},
      daily_total_requests: snapshot.daily_total_requests,
      daily_unique_visitors: snapshot.daily_unique_visitors
    }
  end
end
