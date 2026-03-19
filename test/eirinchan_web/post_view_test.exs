defmodule EirinchanWeb.PostViewTest do
  use ExUnit.Case, async: true
  require Phoenix.LiveViewTest

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Runtime.Config
  alias EirinchanWeb.PostComponents
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

  test "body_html marks owned quote targets server-side" do
    config = Config.compose()
    post = %Post{body: ">>123"}

    html =
      PostView.body_html(post, %BoardRecord{uri: "bant"}, %Post{id: 1}, config,
        own_post_ids: MapSet.new([123]),
        show_yous: true
      )

    assert html =~ ~s|<small>(You)</small>|
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

  test "post_number_links_html explicitly returns citeReply result" do
    html =
      PostView.post_number_links_html(670, "/bant/res/668.html#670", "/bant/res/668.html#q670")

    assert html =~ ~s(data-cite-reply="670")
    assert html =~ ~s(data-cite-mode="inline")
  end

  test "post_number_links_html can use vichan navigation mode" do
    html =
      PostView.post_number_links_html(
        670,
        "/bant/res/668.html#670",
        "/bant/res/668.html#q670",
        ["data-quote-to": 670],
        :navigate
      )

    assert html =~ ~s(data-cite-reply="670")
    assert html =~ ~s(data-cite-mode="navigate")
    refute html =~ "onclick="
  end

  test "file_image_html uses blurred spoiler class on the normal thumbnail" do
    config = Config.compose()

    file = %{
      file_name: "example.jpg",
      file_path: "/bant/src/example.jpg",
      thumb_path: "/bant/thumb/example.jpg",
      image_width: 640,
      image_height: 480,
      spoiler: true
    }

    html = PostView.file_image_html(file, config)

    assert html =~ ~s(class="post-image spoiler-image")
    assert html =~ ~s(src="/bant/thumb/example.jpg")
  end

  test "embed_html rejects raw html payloads" do
    config = Config.compose()

    assert PostView.embed_html("<script>alert(1)</script>", config) == nil
  end

  test "embed_html escapes capture replacements before applying template" do
    config = %{
      Config.compose()
      | embedding: [[~r/^x:(.+)$/i, "<iframe src=\"https://example.test/embed/$1\"></iframe>"]]
    }

    html = PostView.embed_html(~s|x:\"><script>alert(1)</script>|, config)

    assert html =~ "&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"
    refute html =~ ~s|""><script>|
  end

  test "file_inline_details_text uses the inline file format" do
    file = %{file_size: 3481, image_width: 979, image_height: 199}

    assert PostView.file_inline_details_text(file) == "3.4 KB , 979x199"
  end

  test "site_footer renders configured footer entries" do
    html =
      Phoenix.LiveViewTest.render_component(&PostComponents.site_footer/1,
        entries: ["Line one", "Line two"]
      )

    assert html =~ "Line one"
    assert html =~ "Line two"
  end
end
