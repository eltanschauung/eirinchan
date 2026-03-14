defmodule EirinchanWeb.ThreadManagementJSON do
  alias Eirinchan.Posts.PublicIds

  def show(%{thread: thread}) do
    %{data: thread_data(thread)}
  end

  defp thread_data(thread) do
    %{
      id: PublicIds.public_id(thread),
      board_id: thread.board_id,
      sticky: thread.sticky,
      locked: thread.locked,
      cycle: thread.cycle,
      sage: thread.sage,
      slug: thread.slug
    }
  end
end
