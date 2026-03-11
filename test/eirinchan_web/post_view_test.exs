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

  test "reply body clears below large media for multiline text" do
    config = Config.compose()

    post = %Post{
      thread_id: 1,
      body: "line1\nline2\nline3\nline4\nline5",
      file_path: "/bant/src/example.jpg",
      thumb_path: "/bant/thumb/example.jpg",
      image_width: 2200,
      image_height: 1700,
      file_name: "example.jpg",
      file_type: "image/jpeg",
      file_md5: "abc"
    }

    html = PostView.reply_body_container_html(post, %BoardRecord{uri: "bant"}, post, config)

    assert html =~ ~s(style="clear:left;margin-left:0;padding-right:0.5em;margin-top:0.35em")
  end

  test "short replies keep wrapped layout beside media" do
    config = Config.compose()

    post = %Post{
      thread_id: 1,
      body: "short reply",
      file_path: "/bant/src/example.jpg",
      thumb_path: "/bant/thumb/example.jpg",
      image_width: 2200,
      image_height: 1700,
      file_name: "example.jpg",
      file_type: "image/jpeg",
      file_md5: "abc"
    }

    html = PostView.reply_body_container_html(post, %BoardRecord{uri: "bant"}, post, config)

    refute html =~ ~s(clear:left)
  end

  test "medium-width media clears below multiline text" do
    config = Config.compose()

    post = %Post{
      thread_id: 1,
      body: "line1\nline2\nline3",
      file_path: "/bant/src/example.jpg",
      thumb_path: "/bant/thumb/example.jpg",
      image_width: 900,
      image_height: 900,
      file_name: "example.jpg",
      file_type: "image/jpeg",
      file_md5: "abc"
    }

    html = PostView.reply_body_container_html(post, %BoardRecord{uri: "bant"}, post, config)

    assert html =~ ~s(clear:left)
  end

  test "large media clears below short multiline replies" do
    config = Config.compose()

    post = %Post{
      id: 679,
      thread_id: 1,
      body: ">>678\nsad but true",
      file_path: "/bant/src/example.jpg",
      thumb_path: "/bant/thumb/example.jpg",
      image_width: 1200,
      image_height: 900,
      file_name: "example.jpg",
      file_type: "image/jpeg",
      file_md5: "abc"
    }

    html = PostView.reply_body_container_html(post, %BoardRecord{uri: "bant"}, post, config)

    assert html =~ ~s(clear:left)
  end

  test "body_html normalizes windows line endings before inserting br tags" do
    config = Config.compose()
    post = %Post{body: "a\r\nb\r\nc"}

    html = PostView.body_html(post, %BoardRecord{uri: "bant"}, post, config)

    assert html == "a<br/>b<br/>c"
  end

  test "body_html renders configured whale stickers" do
    config = Config.compose()
    post = %Post{body: ":gojo:waow"}

    html = PostView.body_html(post, %BoardRecord{uri: "bant"}, post, config)

    assert html =~ ~s(<img src="/whalestickers/gojo.png" title=":gojo:">waow)
  end

  test "body_html renders vichan-style inline and line formatting" do
    config = Config.compose()

    post = %Post{
      body:
        "**spoiler**\n''italic''\n'''bold'''\n==Heading==\n<truth\ntruth:red\nnipah:blue\ndesire:gold\nstake:spin\nshion:glow"
    }

    html = PostView.body_html(post, %BoardRecord{uri: "bant"}, post, config)

    assert html =~ ~s(<span class="spoiler">spoiler</span>)
    assert html =~ ~s(<em>italic</em>)
    assert html =~ ~s(<strong>bold</strong>)
    assert html =~ ~s(<span class="heading">Heading</span>)
    assert html =~ ~s(<span class="quote2">&lt;truth</span>)
    assert html =~ ~s(<span class="truth">red</span>)
    assert html =~ ~s(<span class="truthblue">blue</span>)
    assert html =~ ~s(<span class="truthgold">gold</span>)
    assert html =~ ~s(<span class="rotate">spin</span>)
    assert html =~ ~s(<span class="glow">glow</span>)
  end

  test "backlinks_html renders existing backlinks server-side" do
    post = %Post{id: 670}

    html = PostView.backlinks_html(post, %{670 => [671, 672]})

    assert html =~ ~s(<span class="mentioned">)
    assert html =~ ~s(class="mentioned-671")
    assert html =~ ~s(href="#671")
    assert html =~ ~s(class="mentioned-672")
  end
end
