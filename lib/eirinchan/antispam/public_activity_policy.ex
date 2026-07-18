defmodule Eirinchan.Antispam.PublicActivityPolicy do
  @moduledoc """
  Resolves instance-configured limits for named public activities.

  Keeping activity policy separate from the database-backed limiter prevents
  unrelated features from accidentally sharing another feature's settings.
  """

  @search_defaults {[15, 2], [50, 2]}
  @feedback_defaults {[5, 24 * 60], [50, 2]}

  def limit_sets(activity, config) do
    case normalize_activity(activity) do
      "search" -> search_limits(config)
      "feedback" -> feedback_limits(config)
      other -> raise ArgumentError, "no public activity rate-limit policy for #{inspect(other)}"
    end
  end

  def rate_limit_message("feedback", config) do
    {count, minutes} =
      configured_tuple(config, :feedback_submissions_per_minutes, elem(@feedback_defaults, 0))

    noun = if count == 1, do: "submission", else: "submissions"

    "Feedback is limited to #{count} #{noun} per #{format_minutes(minutes)}. " <>
      "Please try again later."
  end

  def rate_limit_message(:feedback, config), do: rate_limit_message("feedback", config)

  defp search_limits(config) do
    {identity, global} = @search_defaults

    {identity_count, identity_minutes} =
      configured_tuple(config, :search_queries_per_minutes, identity)

    {global_count, global_minutes} =
      configured_tuple(config, :search_queries_per_minutes_all, global)

    [
      [
        per_ip_count: identity_count,
        per_ip_window_seconds: identity_minutes * 60,
        global_count: global_count,
        global_window_seconds: global_minutes * 60
      ]
    ]
  end

  defp feedback_limits(config) do
    {identity, global} = @feedback_defaults

    {ip_count, ip_minutes} =
      configured_tuple(config, :feedback_submissions_per_minutes, identity)

    {global_count, global_minutes} =
      configured_tuple(config, :feedback_submissions_per_minutes_all, global)

    [
      [
        per_ip_count: ip_count,
        per_ip_window_seconds: ip_minutes * 60,
        per_browser_count: 0,
        per_client_count: 0,
        global_count: 0
      ],
      [
        per_ip_count: 0,
        per_browser_count: 0,
        per_client_count: 0,
        global_count: global_count,
        global_window_seconds: global_minutes * 60
      ]
    ]
  end

  defp configured_tuple(config, key, [default_count, default_minutes]) do
    case Map.get(config, key) do
      [count, minutes]
      when is_integer(count) and count >= 0 and is_integer(minutes) and minutes > 0 ->
        {count, minutes}

      {count, minutes}
      when is_integer(count) and count >= 0 and is_integer(minutes) and minutes > 0 ->
        {count, minutes}

      _ ->
        {default_count, default_minutes}
    end
  end

  defp format_minutes(minutes) when rem(minutes, 60) == 0 do
    hours = div(minutes, 60)
    "#{hours} #{if hours == 1, do: "hour", else: "hours"}"
  end

  defp format_minutes(minutes), do: "#{minutes} #{if minutes == 1, do: "minute", else: "minutes"}"

  defp normalize_activity(activity) do
    activity
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
