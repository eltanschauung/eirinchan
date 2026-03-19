defmodule EirinchanWeb.ModeratorPermissionsTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.ModeratorPermissions

  test "matches vichan role hierarchy for core moderation actions" do
    janitor = %{role: "janitor"}
    moderator = %{role: "mod"}
    admin = %{role: "admin"}

    assert ModeratorPermissions.allowed?(janitor, :delete)
    assert ModeratorPermissions.allowed?(janitor, :deletefile)
    assert ModeratorPermissions.allowed?(janitor, :spoilerimage)
    assert ModeratorPermissions.allowed?(janitor, :reports)
    refute ModeratorPermissions.allowed?(janitor, :ban)
    refute ModeratorPermissions.allowed?(janitor, :manageusers)

    assert ModeratorPermissions.allowed?(moderator, :ban)
    assert ModeratorPermissions.allowed?(moderator, :manageusers)
    assert ModeratorPermissions.allowed?(moderator, :noticeboard_post)
    refute ModeratorPermissions.allowed?(moderator, :themes)
    refute ModeratorPermissions.allowed?(moderator, :news)
    refute ModeratorPermissions.allowed?(moderator, :editpost)

    assert ModeratorPermissions.allowed?(admin, :themes)
    assert ModeratorPermissions.allowed?(admin, :news)
    assert ModeratorPermissions.allowed?(admin, :editpost)
    assert ModeratorPermissions.allowed?(admin, :deleteusers)
    assert ModeratorPermissions.allowed?(admin, :show_ip_global)
  end
end
