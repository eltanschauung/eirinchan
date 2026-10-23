defmodule EirinchanWeb.BoardManagementJSON do
  alias EirinchanWeb.ModeratorPermissions

  def index(%{boards: boards} = assigns) do
    %{data: Enum.map(boards, &board_data(&1, assigns[:current_moderator]))}
  end

  def show(%{board: board} = assigns) do
    %{data: board_data(board, assigns[:current_moderator])}
  end

  defp board_data(board, moderator) do
    data = %{
      uri: board.uri,
      title: board.title,
      subtitle: board.subtitle
    }

    if ModeratorPermissions.allowed?(moderator, :manageboards),
      do: Map.put(data, :config_overrides, board.config_overrides),
      else: data
  end
end
