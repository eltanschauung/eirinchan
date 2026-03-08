defmodule EirinchanWeb.PostViewTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Runtime.Config
  alias EirinchanWeb.PostView

  test "template_assigns exposes the compatibility contract" do
    board = %BoardRecord{uri: "files", title: "Files"}
    post = %Post{id: 10, subject: "Upload thread"}
    config = Config.compose()

    assigns = PostView.template_assigns(board, post, config)

    assert assigns.board == board
    assert assigns.board_title == "Files"
    assert assigns.post == post
    assert assigns.config == config
  end

  test "name_html wraps the name in a mailto link when email is present" do
    config = Config.compose()
    post = %Post{name: "Anonymous", email: "sage"}

    assert PostView.name_html(post, config) =~ ~s(<a class="email" href="mailto:sage">)
    assert PostView.name_html(post, config) =~ ~s(<span class="name">Anonymous</span>)
  end

  test "name_html respects hide_sage and hide_email" do
    post = %Post{name: "Anonymous", email: "sage"}

    assert PostView.name_html(post, Map.put(Config.compose(), :hide_sage, true)) ==
             ~s(<span class="name">Anonymous</span>)

    assert PostView.name_html(post, Map.put(Config.compose(), :hide_email, true)) ==
             ~s(<span class="name">Anonymous</span>)
  end
end
