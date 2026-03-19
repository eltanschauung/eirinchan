defmodule EirinchanWeb.PublicControllerHelpers do
  @moduledoc false

  alias Eirinchan.ThreadWatcher
  alias EirinchanWeb.FragmentHash

  @empty_watcher_metrics %{watcher_count: 0, watcher_unread_count: 0, watcher_you_count: 0}
  @public_extra_stylesheets ["/stylesheets/eirinchan-public.css", "/stylesheets/eirinchan-bant.css"]

  def fragment_options(params) do
    [fragment?: fragment_request?(params), fragment_md5?: fragment_md5_request?(params)]
  end

  def fragment_request?(%{"fragment" => value}) when value in ["1", "true", "yes"], do: true
  def fragment_request?(_params), do: false

  def fragment_md5_request?(%{"fragment" => "md5"}), do: true
  def fragment_md5_request?(_params), do: false

  def render_fragment_md5(view, template, assigns, cache_key) do
    FragmentHash.md5(view, template, assigns, cache_key: cache_key)
  end

  def dynamic_fragment_stamp(assigns, watch_key) do
    {
      own_post_ids_stamp(Keyword.get(assigns, :own_post_ids, MapSet.new())),
      Keyword.get(assigns, :show_yous, false),
      :erlang.phash2(Keyword.get(assigns, watch_key, %{})),
      moderator_stamp(Keyword.get(assigns, :current_moderator)),
      Keyword.get(assigns, :secure_manage_token),
      Keyword.get(assigns, :mobile_client?, false)
    }
  end

  def watcher_metrics(conn) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) -> ThreadWatcher.watch_metrics(token)
      _ -> @empty_watcher_metrics
    end
  end

  def thread_watch_state(conn, board_uri) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) -> ThreadWatcher.watch_state_for_board(token, board_uri)
      _ -> %{}
    end
  end

  def thread_watch(conn, board_uri, thread_id) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) ->
        ThreadWatcher.watch_state_for_board(token, board_uri)
        |> Map.get(thread_id, empty_thread_watch(thread_id))

      _ ->
        empty_thread_watch(thread_id)
    end
  end

  def moderator_body_class(conn, active_page, opts \\ []) do
    extra_classes =
      opts
      |> Keyword.get(:extra_classes, [])
      |> List.wrap()

    moderator_class =
      if conn.assigns[:current_moderator], do: "is-moderator", else: "is-not-moderator"

    ["8chan", "vichan", moderator_class | extra_classes ++ [active_page]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def primary_stylesheet(conn),
    do: conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"

  def data_stylesheet(conn) do
    conn
    |> primary_stylesheet()
    |> Path.basename()
  end

  def extra_stylesheets, do: @public_extra_stylesheets

  defp own_post_ids_stamp(%MapSet{} = ids), do: :erlang.phash2(ids)
  defp own_post_ids_stamp(ids) when is_list(ids), do: ids |> Enum.sort() |> :erlang.phash2()
  defp own_post_ids_stamp(_ids), do: 0

  defp moderator_stamp(nil), do: nil
  defp moderator_stamp(moderator), do: {moderator.id, moderator.role}

  defp empty_thread_watch(thread_id) do
    %{watched: false, unread_count: 0, last_seen_post_id: thread_id}
  end
end
