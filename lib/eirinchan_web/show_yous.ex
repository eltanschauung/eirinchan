defmodule EirinchanWeb.ShowYous do
  alias Eirinchan.PostOwnership
  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds

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
          owned_internal_ids =
            posts
            |> Enum.map(&Map.get(&1, :id))
            |> then(&PostOwnership.owned_post_ids(token, &1))

          posts
          |> Enum.filter(&(MapSet.member?(owned_internal_ids, Map.get(&1, :id))))
          |> PublicIds.public_set()

        _ ->
          MapSet.new()
      end
    else
      MapSet.new()
    end
  end

  def owned_public_ids(conn, board, public_ids) do
    if enabled?(conn) do
      case conn.assigns[:browser_token] do
        token when is_binary(token) ->
          posts_by_public = Posts.public_posts_map(board, public_ids)
          owned_internal_ids = PostOwnership.owned_post_ids(token, Enum.map(Map.values(posts_by_public), & &1.id))

          posts_by_public
          |> Map.values()
          |> Enum.filter(&MapSet.member?(owned_internal_ids, &1.id))
          |> PublicIds.public_set()

        _ ->
          MapSet.new()
      end
    else
      MapSet.new()
    end
  end
end
