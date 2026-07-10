defmodule Eirinchan.ModerationFixtures do
  alias Eirinchan.Moderation

  def moderator_fixture(attrs \\ %{}) do
    {:ok, moderator} =
      attrs
      |> Enum.into(%{
        username: "mod#{System.unique_integer([:positive])}",
        password: "correct horse battery staple",
        role: "admin"
      })
      |> Moderation.create_user()

    moderator
  end

  def grant_board_access_fixture(moderator, board) do
    {:ok, _access} = Moderation.grant_board_access(moderator, board)
    moderator
  end
end
