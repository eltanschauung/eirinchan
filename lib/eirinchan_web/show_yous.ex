defmodule EirinchanWeb.ShowYous do
  alias Eirinchan.PostOwnership

  def enabled?(conn) do
    case conn.req_cookies["show_yous"] do
      "false" -> false
      _ -> true
    end
  end

  def owned_post_ids(conn, posts) do
    if enabled?(conn) do
      case conn.assigns[:browser_token] do
        token when is_binary(token) ->
          posts
          |> Enum.map(&Map.get(&1, :id))
          |> then(&PostOwnership.owned_post_ids(token, &1))

        _ ->
          MapSet.new()
      end
    else
      MapSet.new()
    end
  end
end
