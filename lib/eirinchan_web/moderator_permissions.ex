defmodule EirinchanWeb.ModeratorPermissions do
  @moduledoc false

  alias Eirinchan.Moderation

  @role_rank %{
    "janitor" => 10,
    "mod" => 20,
    "admin" => 30
  }

  @permission_roles %{
    show_ip: "mod",
    show_ip_global: "admin",
    delete: "janitor",
    ban: "mod",
    bandelete: "mod",
    deletebyip: "mod",
    deletebyip_global: "admin",
    ban24: "admin",
    sticky: "mod",
    cycle: "mod",
    lock: "mod",
    bumplock: "mod",
    editpost: "admin",
    move: "admin",
    deletefile: "janitor",
    spoilerimage: "janitor",
    reports: "janitor",
    report_dismiss: "janitor",
    report_dismiss_ip: "janitor",
    report_dismiss_post: "janitor",
    feedback: "janitor",
    feedback_delete: "janitor",
    feedback_mark_read: "janitor",
    feedback_comment: "janitor",
    view_banlist: "mod",
    unban: "mod",
    view_notes: "janitor",
    remove_notes: "admin",
    newboard: "admin",
    manageboards: "admin",
    deleteboard: "admin",
    manageusers: "mod",
    promoteusers: "admin",
    editusers: "admin",
    change_password: "janitor",
    deleteusers: "admin",
    createusers: "admin",
    modlog: "admin",
    create_pm: "janitor",
    rebuild: "admin",
    search_posts: "janitor",
    noticeboard: "janitor",
    noticeboard_post: "mod",
    noticeboard_delete: "admin",
    public_ban: "mod",
    themes: "admin",
    news: "admin",
    news_delete: "admin",
    edit_pages: "mod",
    view_ban_appeals: "mod",
    ban_appeals: "mod",
    recent: "mod"
  }

  def rank(%{role: role}), do: rank(role)
  def rank(role) when is_binary(role), do: Map.get(@role_rank, role, 0)
  def rank(_), do: 0

  def allowed?(moderator, permission)
  def allowed?(nil, _permission), do: false

  def allowed?(moderator, permission) do
    required_role = Map.fetch!(@permission_roles, permission)
    rank(moderator) >= rank(required_role)
  end

  def allowed_on_board?(moderator, board, permission) do
    allowed?(moderator, permission) and Moderation.board_access?(moderator, board)
  end
end
