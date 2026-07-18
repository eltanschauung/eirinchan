defmodule Eirinchan.Statistics.RequestClassifier do
  @moduledoc false

  @rate_limit_actions ~w(catalog_search delete feedback ip_access_auth manage_login post report search watcher)

  def metrics(%Plug.Conn{} = conn) do
    action = public_action(conn)
    rate_limit = rate_limit_action(conn, action)

    ["requests.total", response_metric(conn.status), route_metric(conn, action)]
    |> append_action_metrics(action, conn.status, rate_limit)
    |> append_rate_limit_metrics(rate_limit)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp route_metric(conn, public_action) do
    case controller_action(conn) do
      {EirinchanWeb.BoardController, action} when action in [:show, :show_page] ->
        board_metric(conn, "index")

      {EirinchanWeb.BoardController, action} when action in [:catalog, :catalog_page] ->
        board_metric(conn, "catalog")

      {EirinchanWeb.PageController, action} ->
        page_metric(action)

      {EirinchanWeb.ApiController, action} ->
        known_metric("requests.api", action, ~w(boards catalog page thread threads)a)

      {EirinchanWeb.UploadedFileController, action} ->
        known_metric("requests.media", action, ~w(show show_thumb)a)

      {_controller, _action} when is_binary(public_action) ->
        "requests.action.#{public_action}"

      _other ->
        static_or_other_metric(conn.request_path)
    end
  end

  defp board_metric(conn, page) do
    case board_uri(conn) do
      nil -> "requests.board.unknown.#{page}.#{fragment_kind(conn)}"
      uri -> "requests.board.#{uri}.#{page}.#{fragment_kind(conn)}"
    end
  end

  defp board_uri(conn) do
    case conn.assigns[:current_board] do
      %{uri: uri} when is_binary(uri) -> bounded_board_uri(uri)
      _other -> nil
    end
  end

  defp bounded_board_uri(uri) do
    if Regex.match?(~r/\A[a-zA-Z0-9_]{1,64}\z/, uri), do: String.downcase(uri)
  end

  defp fragment_kind(conn) do
    case param(conn, "fragment") do
      "md5" -> "fragment_hash"
      value when value in ["1", "true", "yes"] -> "fragment_body"
      _other -> "full"
    end
  end

  defp page_metric(action) do
    known_metric(
      "requests.page",
      action,
      ~w(banners catalog faq feedback flags formatting home news page recent rss rules sitemap ukko watcher watcher_fragment)a
    )
  end

  defp known_metric(prefix, action, allowed) do
    if action in allowed, do: "#{prefix}.#{action}", else: "#{prefix}.other"
  end

  defp static_or_other_metric(path) do
    if Path.extname(path || "") == "", do: "requests.other", else: "requests.static"
  end

  defp public_action(conn) do
    case controller_action(conn) do
      {EirinchanWeb.SearchController, :show} ->
        if present?(param(conn, "search") || param(conn, "q")), do: "search"

      {EirinchanWeb.FeedbackController, :create} ->
        "feedback"

      {EirinchanWeb.IpAccessAuthController, :create} ->
        "ip_access_auth"

      {EirinchanWeb.ManagePageController, :create_session} ->
        "manage_login"

      {EirinchanWeb.ManageSessionController, :create} ->
        "manage_login"

      {EirinchanWeb.ThreadWatcherController, action}
      when action in [:create, :delete, :update, :clear] ->
        "watcher"

      {EirinchanWeb.ThemeController, :update} ->
        "theme"

      {EirinchanWeb.BoardController, action} when action in [:catalog, :catalog_page] ->
        if present?(param(conn, "search")), do: "catalog_search"

      {EirinchanWeb.PostController, action} when action in [:create, :create_json] ->
        post_action(conn)

      _other ->
        nil
    end
  end

  defp post_action(conn) do
    cond do
      present?(param(conn, "report")) -> "report"
      present?(param(conn, "delete")) or delete_post_param?(conn) -> "delete"
      true -> "post"
    end
  end

  defp delete_post_param?(conn) do
    conn
    |> params()
    |> Map.keys()
    |> Enum.any?(&String.starts_with?(to_string(&1), "delete_"))
  end

  defp rate_limit_action(conn, action) do
    marked = conn.private[:statistics_rate_limit]

    cond do
      marked in @rate_limit_actions -> marked
      conn.status == 429 and action in @rate_limit_actions -> action
      conn.status == 429 -> "other"
      true -> nil
    end
  end

  defp append_action_metrics(metrics, nil, _status, _rate_limit), do: metrics

  defp append_action_metrics(metrics, action, status, rate_limit) do
    outcome =
      cond do
        not is_nil(rate_limit) -> "rate_limited"
        status in 200..399 -> "accepted"
        status in 400..499 -> "rejected"
        true -> "error"
      end

    ["actions.#{action}.#{outcome}", "actions.#{action}.attempted" | metrics]
  end

  defp append_rate_limit_metrics(metrics, nil), do: metrics

  defp append_rate_limit_metrics(metrics, action) do
    ["rate_limits.#{action}", "rate_limits.total" | metrics]
  end

  defp response_metric(status) when status in 200..299, do: "responses.2xx"
  defp response_metric(status) when status in 300..399, do: "responses.3xx"
  defp response_metric(status) when status in 400..499, do: "responses.4xx"
  defp response_metric(status) when status in 500..599, do: "responses.5xx"
  defp response_metric(_status), do: "responses.other"

  defp controller_action(conn) do
    {conn.private[:phoenix_controller], conn.private[:phoenix_action]}
  end

  defp param(conn, key), do: Map.get(params(conn), key)

  defp params(%Plug.Conn{params: %Plug.Conn.Unfetched{}}), do: %{}
  defp params(%Plug.Conn{params: params}) when is_map(params), do: params
  defp params(_conn), do: %{}

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
