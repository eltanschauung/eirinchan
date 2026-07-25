defmodule Eirinchan.Statistics.SearchTelemetry do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  alias Eirinchan.CredentialHash
  alias Eirinchan.Statistics
  alias EirinchanWeb.RequestMeta

  @outcomes ~w(disabled empty invalid_board invalid_query invalid_terms rate_limited results unavailable)
  @filter_fields ~w(text thread post_id subject username tripcode email uid country filename image_hash width height start_date end_date)a
  @identifier_length 12

  def record(%Plug.Conn{} = conn, criteria, boards, outcome, opts \\ [])
      when is_map(criteria) and is_list(boards) do
    if Statistics.enabled?() do
      outcome = normalize_outcome(outcome)
      features = features(criteria)
      identities = identities(conn)

      metrics =
        [
          "search.attempts",
          "search.outcomes.#{outcome}",
          "search.scope.#{scope(boards, opts)}",
          "search.pages.#{page_kind(opts)}",
          "search.results.#{result_bucket(outcome, opts)}",
          "search.modes.image.#{criteria.image}",
          "search.modes.type.#{criteria.type}",
          "search.modes.results.#{criteria.results}",
          "search.modes.order.#{criteria.order}",
          "search.modes.highlight.#{if(criteria.highlight, do: "on", else: "off")}",
          single_board_metric(boards)
        ] ++
          Enum.map(features, &"search.features.#{&1}") ++
          identity_metrics(identities, features)

      now = Keyword.get(opts, :now, DateTime.utc_now(:second))
      Statistics.record_metrics(metrics, now)

      if outcome == "results" do
        Statistics.record_search_terms(search_terms(criteria), now)
      end
    end

    :ok
  end

  defp search_terms(criteria) do
    Enum.flat_map(@filter_fields, fn
      :country ->
        criteria
        |> Map.get(:country)
        |> to_string()
        |> String.split(",", trim: true)
        |> Enum.map(&{:country, &1})

      field ->
        case Map.get(criteria, field) do
          nil -> []
          "" -> []
          %Date{} = value -> [{field, Date.to_iso8601(value)}]
          value -> [{field, to_string(value)}]
        end
    end)
  end

  defp features(criteria) do
    selected =
      Enum.flat_map(@filter_fields, fn field ->
        if present?(Map.get(criteria, field)), do: [Atom.to_string(field)], else: []
      end)

    selected ++
      if(criteria.image != "all", do: ["image_#{criteria.image}"], else: []) ++
      if(criteria.type != "all", do: ["type_#{criteria.type}"], else: []) ++
      if(criteria.results != "posts", do: ["results_#{criteria.results}"], else: []) ++
      if(criteria.order != "latest", do: ["order_#{criteria.order}"], else: []) ++
      if(criteria.highlight, do: ["highlight"], else: [])
  end

  defp identities(conn) do
    network_source =
      conn
      |> RequestMeta.effective_remote_ip()
      |> RequestMeta.ip_to_string()

    agent_source =
      conn
      |> get_req_header("user-agent")
      |> List.first()
      |> normalize_agent()

    %{
      network: fingerprint(network_source, :search_statistics_network),
      user_agent: fingerprint(agent_source, :search_statistics_user_agent),
      combined: fingerprint(network_source <> <<0>> <> agent_source, :search_statistics_client)
    }
  end

  defp identity_metrics(identities, features) do
    base =
      Enum.map(identities, fn {dimension, identifier} ->
        "search.clients.#{dimension}.#{identifier}"
      end)

    feature_metrics =
      for {dimension, identifier} <- identities,
          feature <- features do
        "search.client_features.#{dimension}.#{identifier}.#{feature}"
      end

    base ++ feature_metrics
  end

  defp fingerprint(value, purpose),
    do: value |> CredentialHash.fingerprint(purpose, @identifier_length) |> String.downcase()

  defp normalize_agent(nil), do: "unknown"

  defp normalize_agent(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.slice(0, 512)
    |> case do
      "" -> "unknown"
      normalized -> normalized
    end
  end

  defp scope(boards, opts) do
    cond do
      Keyword.get(opts, :scope) == "all" -> "all_boards"
      length(boards) == 1 -> "single_board"
      length(boards) > 1 -> "multiple_boards"
      true -> "no_board"
    end
  end

  defp single_board_metric([%{uri: uri}]) when is_binary(uri) do
    if Regex.match?(~r/\A[a-zA-Z0-9_]{1,64}\z/, uri),
      do: "search.boards.#{String.downcase(uri)}"
  end

  defp single_board_metric(_boards), do: nil

  defp page_kind(opts) do
    if positive_integer(Keyword.get(opts, :page), 1) > 1, do: "pagination", else: "initial"
  end

  defp result_bucket(outcome, _opts) when outcome != "results", do: outcome

  defp result_bucket("results", opts) do
    cond do
      Keyword.get(opts, :capped?, false) -> "capped"
      positive_integer(Keyword.get(opts, :result_count), 0) == 0 -> "zero"
      Keyword.get(opts, :result_count) == 1 -> "one"
      Keyword.get(opts, :result_count) in 2..10 -> "two_to_ten"
      Keyword.get(opts, :result_count) in 11..50 -> "eleven_to_fifty"
      Keyword.get(opts, :result_count) in 51..100 -> "fifty_one_to_one_hundred"
      true -> "over_one_hundred"
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp positive_integer(_value, default), do: default

  defp normalize_outcome(outcome) when is_atom(outcome),
    do: normalize_outcome(Atom.to_string(outcome))

  defp normalize_outcome(outcome) when outcome in @outcomes, do: outcome
  defp normalize_outcome(_outcome), do: "unavailable"

  defp present?(nil), do: false
  defp present?(false), do: false
  defp present?(""), do: false
  defp present?(_value), do: true
end
