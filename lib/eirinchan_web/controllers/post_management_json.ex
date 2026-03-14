defmodule EirinchanWeb.PostManagementJSON do
  alias Eirinchan.Posts.PublicIds

  def show(%{post: post}) do
    %{data: post_data(post)}
  end

  defp post_data(post) do
    %{
      id: PublicIds.public_id(post),
      board_id: post.board_id,
      thread_id: PublicIds.thread_public_id(post),
      name: post.name,
      email: post.email,
      subject: post.subject,
      body: post.body,
      file_path: post.file_path,
      thumb_path: post.thumb_path,
      spoiler: post.spoiler,
      extra_files:
        Enum.map(post.extra_files || [], fn file ->
          %{
            id: file.id,
            file_path: file.file_path,
            thumb_path: file.thumb_path,
            spoiler: file.spoiler
          }
        end)
    }
  end
end
