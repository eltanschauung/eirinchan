defmodule EirinchanWeb.ModDashboardJSON do
  alias Eirinchan.Posts.PublicIds

  def show(%{data: data}), do: %{data: data}

  def recent(%{posts: posts}) do
    %{
      data:
        Enum.map(posts, fn post ->
          %{
            id: PublicIds.public_id(post),
            board_id: post.board_id,
            thread_id: PublicIds.thread_public_id(post),
            subject: post.subject,
            body: post.body,
            inserted_at: post.inserted_at
          }
        end)
    }
  end
end
