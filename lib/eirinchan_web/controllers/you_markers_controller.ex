defmodule EirinchanWeb.YouMarkersController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias EirinchanWeb.ShowYous

  def show(conn, %{"board" => board_uri} = params) do
    case Boards.get_board_by_uri(board_uri) do
      nil ->
        send_resp(conn, :not_found, "Board not found")

      board ->
        post_ids =
          params
          |> Map.get("post_ids", [])
          |> normalize_post_ids()

        owned_post_ids =
          conn
          |> ShowYous.owned_public_ids(board, post_ids)
          |> MapSet.to_list()
          |> Enum.sort()

        json(conn, %{enabled: ShowYous.enabled?(conn), post_ids: owned_post_ids})
    end
  end

  defp normalize_post_ids(post_ids) when is_list(post_ids) do
    post_ids
    |> Enum.map(fn
      value when is_integer(value) -> value
      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_post_ids(_post_ids), do: []
end
