defmodule Eirinchan.PostsFixtures do
  alias Eirinchan.BoardsFixtures
  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds

  def thread_fixture(board \\ nil, attrs \\ %{}) do
    board = board || BoardsFixtures.board_fixture()

    {:ok, thread, _meta} =
      board
      |> Posts.create_post(
        attrs
        |> Enum.into(%{body: "Opening post body", subject: "Opening subject", post: "New Topic"}),
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    thread
  end

  def reply_fixture(board, thread, attrs \\ %{}) do
    {:ok, reply, _meta} =
      Posts.create_post(
        board,
        attrs
        |> Enum.into(%{
          thread: Integer.to_string(PublicIds.public_id(thread)),
          body: "Reply body",
          post: "New Reply"
        }),
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    reply
  end
end
