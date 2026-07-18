defmodule Eirinchan.Antispam do
  @moduledoc """
  Shared flood and public-activity tracking for posting throttles.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Antispam.{FloodEntry, SearchQuery}
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.BrowserAbuse
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Moderation.ModUser
  alias Eirinchan.Repo

  def check_post(%BoardRecord{} = board, attrs, request, config, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = DateTime.utc_now()
    body = normalize_query(Map.get(attrs, "body")) || ""
    op? = is_nil(blank_to_nil(Map.get(attrs, "thread")))

    cond do
      too_many_links?(body, config) ->
        {:error, :toomanylinks}

      too_many_cites?(body, config) ->
        {:error, :toomanycites}

      too_many_cross_board_links?(body, config) ->
        {:error, :toomanycross}

      true ->
        dimensions = request_dimensions(request)

        post =
          %{
            board_id: board.id,
            body: body,
            body_hash: body_hash(attrs),
            op?: op?
          }
          |> Map.merge(dimensions)

        with :ok <- evaluate_dimension_limits(repo, post, config, now) do
          evaluate_filters(repo, board, post, config, now)
        end
    end
  end

  def log_post(%BoardRecord{} = board, attrs, request, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    dimensions = request_dimensions(request)

    %FloodEntry{}
    |> FloodEntry.changeset(%{
      board_id: board.id,
      ip_subnet: dimensions.ip_subnet,
      browser_ref: dimensions.browser_ref,
      client_key: dimensions.client_key,
      body_hash: body_hash(attrs)
    })
    |> repo.insert()
  end

  def log_upload_attempt(%BoardRecord{} = board, attrs, request, opts \\ []) do
    request =
      if is_nil(request_ip(request)) do
        Map.put(request, :remote_ip, "0.0.0.0")
      else
        request
      end

    log_post(board, attrs, request, opts)
  end

  def check_public_action(%BoardRecord{} = board, action, attrs, request, config, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = DateTime.utc_now()

    if moderated_request?(request) do
      :ok
    else
      entry = public_action_entry(action, attrs, request)

      with :ok <- evaluate_dimension_limits(repo, entry, config, now) do
        evaluate_filters(repo, board, entry, config, now)
      end
    end
  end

  def log_public_action(%BoardRecord{} = board, action, attrs, request, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    entry = public_action_entry(action, attrs, request)

    %FloodEntry{}
    |> FloodEntry.changeset(%{
      board_id: board.id,
      ip_subnet: entry.ip_subnet,
      browser_ref: entry.browser_ref,
      client_key: entry.client_key,
      body_hash: entry.body_hash
    })
    |> repo.insert()
  end

  def log_public_activity(activity, request, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    board_id = Keyword.get(opts, :board_id)
    dimensions = request_dimensions(request)

    %SearchQuery{}
    |> SearchQuery.changeset(%{
      board_id: board_id,
      ip_subnet: dimensions.ip_subnet,
      browser_ref: dimensions.browser_ref,
      client_key: dimensions.client_key,
      activity: normalize_activity(activity)
    })
    |> repo.insert()
  end

  def configured_public_activity_rate_limited?(request, activity, config, opts \\ []) do
    {per_identity_count, per_identity_minutes} =
      rate_limit_tuple(config, :search_queries_per_minutes, 15, 2)

    {global_count, global_minutes} =
      rate_limit_tuple(config, :search_queries_per_minutes_all, 50, 2)

    defaults = [
      per_ip_count: per_identity_count,
      per_ip_window_seconds: per_identity_minutes * 60,
      global_count: global_count,
      global_window_seconds: global_minutes * 60
    ]

    public_activity_rate_limited?(request, activity, Keyword.merge(defaults, opts))
  end

  def public_activity_rate_limited?(request, activity, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    dimensions = request_dimensions(request)
    activity = normalize_activity(activity)
    per_ip_count = Keyword.get(opts, :per_ip_count, 15)
    per_ip_window_seconds = Keyword.get(opts, :per_ip_window_seconds, 120)
    per_browser_count = Keyword.get(opts, :per_browser_count, per_ip_count)

    per_browser_window_seconds =
      Keyword.get(opts, :per_browser_window_seconds, per_ip_window_seconds)

    per_client_count = Keyword.get(opts, :per_client_count, per_ip_count)

    per_client_window_seconds =
      Keyword.get(opts, :per_client_window_seconds, per_ip_window_seconds)

    global_count = Keyword.get(opts, :global_count, 50)
    global_window_seconds = Keyword.get(opts, :global_window_seconds, 120)
    base_query = from(entry in SearchQuery, where: entry.activity == ^activity)

    limited? =
      search_dimension_limited?(
        repo,
        base_query,
        :ip_subnet,
        dimensions.ip_subnet,
        per_ip_count,
        per_ip_window_seconds
      ) or
        search_dimension_limited?(
          repo,
          base_query,
          :browser_ref,
          dimensions.browser_ref,
          per_browser_count,
          per_browser_window_seconds
        ) or
        search_dimension_limited?(
          repo,
          base_query,
          :client_key,
          dimensions.client_key,
          per_client_count,
          per_client_window_seconds
        ) or
        search_dimension_limited?(
          repo,
          base_query,
          nil,
          :global,
          global_count,
          global_window_seconds
        )

    if limited?, do: BrowserAbuse.record(dimensions, "#{activity}_rate_limit", repo: repo)
    limited?
  end

  def list_flood_entries(ip_subnet, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    from(entry in FloodEntry,
      where: entry.ip_subnet == ^normalize_ip(ip_subnet),
      order_by: [asc: entry.inserted_at]
    )
    |> repo.all()
  end

  def list_public_activity_entries(ip_subnet, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    from(entry in SearchQuery,
      where: entry.ip_subnet == ^normalize_ip(ip_subnet),
      order_by: [asc: entry.inserted_at]
    )
    |> repo.all()
  end

  def purge_old(config, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    retention_seconds = max(Map.get(config, :antispam_retention_seconds, 172_800), 0)
    cutoff = DateTime.add(DateTime.utc_now(), -retention_seconds, :second)

    {flood_count, _} =
      repo.delete_all(from entry in FloodEntry, where: entry.inserted_at < ^cutoff)

    {activity_count, _} =
      repo.delete_all(from entry in SearchQuery, where: entry.inserted_at < ^cutoff)

    flood_count + activity_count
  end

  defp search_dimension_limited?(_repo, _queryable, _field, nil, _count, _window), do: false

  defp search_dimension_limited?(_repo, _queryable, _field, _value, count, _window)
       when not is_integer(count) or count <= 0,
       do: false

  defp search_dimension_limited?(_repo, _queryable, _field, _value, _count, window)
       when not is_integer(window) or window <= 0,
       do: false

  defp search_dimension_limited?(repo, queryable, field_name, value, count, window) do
    cutoff = DateTime.add(DateTime.utc_now(), -window, :second)

    queryable
    |> maybe_query_by_dimension(field_name, value)
    |> query_since(cutoff)
    |> repo.aggregate(:count, :id)
    |> Kernel.>=(count)
  end

  defp rate_limit_tuple(config, key, default_count, default_minutes) do
    case Map.get(config, key) do
      [count, minutes] when is_integer(count) and is_integer(minutes) -> {count, minutes}
      {count, minutes} when is_integer(count) and is_integer(minutes) -> {count, minutes}
      _ -> {default_count, default_minutes}
    end
  end

  defp maybe_query_by_dimension(queryable, nil, _value), do: queryable

  defp maybe_query_by_dimension(queryable, field_name, value) do
    from(entry in queryable, where: field(entry, ^field_name) == ^value)
  end

  defp query_since(queryable, cutoff) do
    from(entry in queryable, where: entry.inserted_at >= ^cutoff)
  end

  defp evaluate_filters(repo, board, post, config, now) do
    config.filters
    |> List.wrap()
    |> Enum.reduce_while(:ok, fn filter, :ok ->
      if reject_filter_matches?(repo, board, post, filter, config, now) do
        record_browser_signal(post, "filter:#{filter_reason(filter)}", config, repo)
        {:halt, {:error, filter_reason(filter)}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp evaluate_dimension_limits(repo, post, config, now) do
    base_window = non_negative_integer(Map.get(config, :flood_time), 0)

    limits = [
      {:ip_subnet, post.ip_subnet, Map.get(config, :flood_ip_count, 1), base_window},
      {
        :browser_ref,
        post.browser_ref,
        Map.get(config, :flood_browser_count, 1),
        Map.get(config, :flood_time_browser) || base_window
      },
      {
        :client_key,
        post.client_key,
        Map.get(config, :flood_client_count, 1),
        Map.get(config, :flood_time_client) || base_window
      },
      {
        nil,
        :global,
        Map.get(config, :flood_global_count, 300),
        Map.get(config, :flood_global_window, 60)
      }
    ]

    case Enum.find(limits, fn {field_name, value, count, window} ->
           flood_dimension_limited?(repo, field_name, value, count, window, now)
         end) do
      {field_name, _value, _count, _window} ->
        record_browser_signal(post, "rate_limit:#{field_name || :global}", config, repo)
        {:error, :antispam}

      nil ->
        :ok
    end
  end

  defp flood_dimension_limited?(_repo, _field, nil, _count, _window, _now), do: false

  defp flood_dimension_limited?(_repo, _field, _value, count, _window, _now)
       when not is_integer(count) or count <= 0,
       do: false

  defp flood_dimension_limited?(_repo, _field, _value, _count, window, _now)
       when not is_integer(window) or window <= 0,
       do: false

  defp flood_dimension_limited?(repo, field_name, value, count, window, now) do
    cutoff = DateTime.add(now, -window, :second)

    FloodEntry
    |> maybe_query_by_dimension(field_name, value)
    |> query_since(cutoff)
    |> repo.aggregate(:count, :id)
    |> Kernel.>=(count)
  end

  defp reject_filter_matches?(repo, board, post, filter, config, now) do
    action = filter[:action] || filter["action"] || "reject"
    condition = filter[:condition] || filter["condition"] || %{}

    action == "reject" and condition_matches?(repo, board, post, condition, config, now)
  end

  defp condition_matches?(repo, board, post, condition, config, now) do
    Enum.all?(condition, fn
      {"flood-match", fields} -> flood_match?(repo, board, post, condition, fields, now)
      {:flood_match, fields} -> flood_match?(repo, board, post, condition, fields, now)
      {"flood-time", _} -> true
      {:flood_time, _} -> true
      {"flood-count", _} -> true
      {:flood_count, _} -> true
      {"custom", "check_thread_limit"} -> thread_limit_exceeded?(repo, board, post, config, now)
      {:custom, "check_thread_limit"} -> thread_limit_exceeded?(repo, board, post, config, now)
      {"!body", pattern} -> not regex_match?(post.body, pattern)
      {:"!body", pattern} -> not regex_match?(post.body, pattern)
      {"body", pattern} -> regex_match?(post.body, pattern)
      {:body, pattern} -> regex_match?(post.body, pattern)
      {"OP", expected} -> post.op? == truthy?(expected)
      {:OP, expected} -> post.op? == truthy?(expected)
      {"op", expected} -> post.op? == truthy?(expected)
      {:op, expected} -> post.op? == truthy?(expected)
      {_unknown, _value} -> true
    end)
  end

  defp flood_match?(repo, board, post, condition, fields, now) do
    window = condition["flood-time"] || condition[:flood_time] || condition["flood_time"] || 0

    threshold =
      condition["flood-count"] || condition[:flood_count] || condition["flood_count"] || 1

    fields = Enum.map(List.wrap(fields), &to_string/1)

    if window in [nil, 0] do
      false
    else
      recent_matching_posts(repo, board.id, post, fields, now, window) >= threshold
    end
  end

  defp recent_matching_posts(repo, board_id, post, fields, now, window_seconds) do
    cutoff = DateTime.add(now, -window_seconds, :second)

    from(entry in FloodEntry, where: entry.board_id == ^board_id and entry.inserted_at >= ^cutoff)
    |> maybe_match_ip(post, fields)
    |> maybe_match_browser(post, fields)
    |> maybe_match_client(post, fields)
    |> maybe_match_body(post, fields)
    |> repo.aggregate(:count, :id)
  end

  defp maybe_match_ip(queryable, post, fields) do
    if "ip" in fields do
      case post.ip_subnet do
        nil -> from(entry in queryable, where: false)
        ip_subnet -> from(entry in queryable, where: entry.ip_subnet == ^ip_subnet)
      end
    else
      queryable
    end
  end

  defp maybe_match_body(queryable, post, fields) do
    if "body" in fields do
      case post.body_hash do
        nil -> from(entry in queryable, where: false)
        body_hash -> from(entry in queryable, where: entry.body_hash == ^body_hash)
      end
    else
      queryable
    end
  end

  defp maybe_match_browser(queryable, post, fields) do
    if "browser" in fields do
      case post.browser_ref do
        nil -> from(entry in queryable, where: false)
        browser_ref -> from(entry in queryable, where: entry.browser_ref == ^browser_ref)
      end
    else
      queryable
    end
  end

  defp maybe_match_client(queryable, post, fields) do
    if "client" in fields do
      case post.client_key do
        nil -> from(entry in queryable, where: false)
        client_key -> from(entry in queryable, where: entry.client_key == ^client_key)
      end
    else
      queryable
    end
  end

  defp thread_limit_exceeded?(_repo, _board, %{op?: false}, _config, _now), do: false
  defp thread_limit_exceeded?(_repo, _board, _post, %{max_threads_per_hour: 0}, _now), do: false
  defp thread_limit_exceeded?(_repo, _board, _post, %{max_threads_per_hour: nil}, _now), do: false

  defp thread_limit_exceeded?(repo, board, _post, config, now) do
    cutoff = DateTime.add(now, -(60 * 60), :second)

    from(post in Eirinchan.Posts.Post,
      where: post.board_id == ^board.id and is_nil(post.thread_id) and post.inserted_at >= ^cutoff
    )
    |> repo.aggregate(:count, :id)
    |> Kernel.>=(config.max_threads_per_hour)
  end

  defp filter_reason(filter) do
    reason = filter[:reason] || filter["reason"] || "antispam"

    case reason do
      atom when is_atom(atom) ->
        atom

      "too_many_threads" ->
        :too_many_threads

      "toomanylinks" ->
        :toomanylinks

      "antispam" ->
        :antispam

      _ ->
        :antispam
    end
  end

  defp regex_match?(value, pattern) when is_binary(pattern) do
    case Regex.compile(unwrap_regex(pattern), regex_options(pattern)) do
      {:ok, regex} -> Regex.match?(regex, value || "")
      _ -> false
    end
  end

  defp regex_match?(_value, _pattern), do: false

  defp unwrap_regex("/" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [body, _flags] -> body
      _ -> rest
    end
  end

  defp unwrap_regex(pattern), do: pattern

  defp regex_options("/" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [_body, flags] ->
        Enum.reduce(String.graphemes(flags), "", fn
          "i", acc -> acc <> "i"
          "m", acc -> acc <> "m"
          "s", acc -> acc <> "s"
          "u", acc -> acc <> "u"
          _, acc -> acc
        end)

      _ ->
        ""
    end
  end

  defp regex_options(_pattern), do: ""

  defp truthy?(value) when is_boolean(value), do: value
  defp truthy?(1), do: true
  defp truthy?("1"), do: true
  defp truthy?("true"), do: true
  defp truthy?("yes"), do: true
  defp truthy?(_), do: false

  defp too_many_links?(_body, %{markup_urls: false}), do: false
  defp too_many_links?(_body, %{max_links: nil}), do: false
  defp too_many_links?(_body, %{max_links: max_links}) when max_links <= 0, do: false

  defp too_many_links?(body, config) do
    url_regex = ~r/((?:https?:\/\/|ftp:\/\/|irc:\/\/)[^\s<>()"]+)/iu

    Regex.scan(url_regex, body || "")
    |> length()
    |> Kernel.>(config.max_links)
  end

  defp too_many_cites?(_body, %{max_cites: nil}), do: false
  defp too_many_cites?(_body, %{max_cites: max_cites}) when max_cites <= 0, do: false

  defp too_many_cites?(body, config) do
    Regex.scan(~r/(^|[\s(])>>\d+((?=[\s,.)?!])|$)/um, body || "")
    |> length()
    |> Kernel.>(config.max_cites)
  end

  defp too_many_cross_board_links?(_body, %{max_cross: nil}), do: false
  defp too_many_cross_board_links?(_body, %{max_cross: max_cross}) when max_cross <= 0, do: false

  defp too_many_cross_board_links?(body, config) do
    board_regex = Map.get(config, :board_regex, "[a-zA-Z0-9_]+")

    regex =
      Regex.compile!(
        "(^|[\\s(])>>>/(?:#{board_regex})f?/(?:\\d+)?((?=[\\s,.)?!])|$)",
        "um"
      )

    Regex.scan(regex, body || "")
    |> length()
    |> Kernel.>(config.max_cross)
  end

  defp body_hash(attrs) do
    case Map.get(attrs, "body") |> normalize_query() do
      nil ->
        nil

      body ->
        :sha256
        |> :crypto.hash(body)
        |> Base.encode16(case: :lower)
    end
  end

  defp public_action_entry(action, attrs, request) do
    body = public_action_body(action, attrs)

    %{
      body: body,
      body_hash: body_hash(%{"body" => body}),
      op?: false
    }
    |> Map.merge(request_dimensions(request))
  end

  defp public_action_body(action, attrs) do
    attrs = normalize_action_attrs(attrs)

    case to_string(action) do
      "report" ->
        [
          "report",
          Map.get(attrs, "report_post_id", ""),
          normalize_query(Map.get(attrs, "reason")) || ""
        ]
        |> Enum.join(":")

      "delete" ->
        [
          if(truthy?(Map.get(attrs, "file")), do: "delete-file", else: "delete"),
          Map.get(attrs, "delete_post_id", "")
        ]
        |> Enum.join(":")

      "edit" ->
        ["edit", Map.get(attrs, "edit_post_id", Map.get(attrs, "post_id", ""))]
        |> Enum.join(":")

      other ->
        [other, normalize_query(inspect(attrs)) || ""]
        |> Enum.join(":")
    end
  end

  defp normalize_action_attrs(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp normalize_action_attrs(_attrs), do: %{}

  defp request_ip(request) do
    request
    |> Map.get(:remote_ip, Map.get(request, "remote_ip"))
    |> normalize_ip()
  end

  defp request_dimensions(request) do
    ip_subnet = request_ip(request)

    browser_ref =
      request
      |> Map.get(:browser_ref, Map.get(request, "browser_ref"))
      |> case do
        value when is_binary(value) and value != "" -> BrowserIdentity.reference(value)
        _ -> nil
      end

    client_key =
      if is_binary(ip_subnet) and is_binary(browser_ref) do
        BrowserIdentity.client_reference(ip_subnet, browser_ref)
      end

    %{ip_subnet: ip_subnet, browser_ref: browser_ref, client_key: client_key}
  end

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default

  defp record_browser_signal(post, reason, config, repo) do
    BrowserAbuse.record(post, reason,
      repo: repo,
      ttl_seconds: Map.get(config, :browser_abuse_challenge_seconds, 3_600)
    )
  end

  defp normalize_query(nil), do: nil

  defp normalize_query(query) when is_binary(query) do
    query
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_query(query), do: to_string(query)

  defp normalize_activity(activity) do
    activity
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(query) when is_binary(query) do
    query
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: to_string(value)

  defp normalize_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_ip(ip) when is_binary(ip), do: String.trim(ip)
  defp normalize_ip(_ip), do: nil

  defp moderated_request?(request) do
    case Map.get(request, :moderator) || Map.get(request, "moderator") do
      %ModUser{} -> true
      _ -> false
    end
  end
end
