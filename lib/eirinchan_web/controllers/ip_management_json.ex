defmodule EirinchanWeb.IpManagementJSON do
  alias Eirinchan.Posts.PublicIds
  alias EirinchanWeb.IpPresentation

  def show(%{ip: ip, posts: posts, notes: notes, moderator: moderator}) do
    %{
      data: %{
        ip: IpPresentation.display_ip(ip, moderator),
        posts: Enum.map(posts, &post_data(&1, moderator)),
        notes: Enum.map(notes, &note_data(&1, moderator))
      }
    }
  end

  def note(%{note: note, moderator: moderator}) do
    %{data: note_data(note, moderator)}
  end

  defp post_data(post, moderator) do
    %{
      id: PublicIds.public_id(post),
      board_id: post.board_id,
      thread_id: PublicIds.thread_public_id(post),
      ip_subnet: IpPresentation.display_ip(post.ip_subnet, moderator),
      subject: post.subject,
      body: post.body,
      inserted_at: post.inserted_at
    }
  end

  defp note_data(note, moderator) do
    %{
      id: note.id,
      ip_subnet: IpPresentation.display_ip(note.ip_subnet, moderator),
      body: note.body,
      board_id: note.board_id,
      mod_user_id: note.mod_user_id,
      inserted_at: note.inserted_at
    }
  end
end
