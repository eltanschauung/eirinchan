defmodule EirinchanWeb.BanManagementJSON do
  alias EirinchanWeb.{IpPresentation, PostView}

  def index(%{bans: bans, board: board, moderator: moderator}) do
    %{data: Enum.map(bans, &ban_data(&1, moderator, board))}
  end

  def show(%{ban: ban, board: board, moderator: moderator}) do
    %{data: ban_data(ban, moderator, board)}
  end

  defp ban_data(ban, moderator, board) do
    %{
      id: ban.id,
      board_id: ban.board_id,
      mod_user_id: ban.mod_user_id,
      ip_subnet:
        if(PostView.can_view_ip?(moderator, board),
          do: IpPresentation.display_ip(ban.ip_subnet, moderator),
          else: nil
        ),
      reason: ban.reason,
      expires_at: ban.expires_at,
      active: ban.active
    }
  end
end
