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

  test "body_html renders inactive OP gap warnings with the public ban styling" do
    config = Config.compose(%{early_404_gap: true})
    post = %Post{body: "waow", inactive: true, thread_id: nil}

    html = PostView.body_html(post, %BoardRecord{uri: "bant"}, post, config)

    assert html ==
             ~s|waow<span class="public_ban">(This thread is inactive and will enter a gap soon.)</span>|
  end

  test "body_html renders public ban messages like vichan and strips the hidden tag from body text" do
    config = Config.compose()
    post = %Post{body: "waow\n<tinyboard ban message>USER WAS BANNED FOR THIS POST</tinyboard>"}

    html = PostView.body_html(post, %BoardRecord{uri: "bant"}, post, config)

    assert html == ~s|waow<span class="public_ban">(USER WAS BANNED FOR THIS POST)</span>|
  end

  test "poster ids render in post identity and stay thread-local" do
    config =
      Config.compose(%{
        poster_ids: true,
        poster_id_length: 5,
        secure_trip_salt: "poster-id-test-salt"
      })

    board = %BoardRecord{uri: "bant", title: "Bant"}

    op = %Post{
      id: 100,
      thread_id: nil,
      poster_id: Eirinchan.PosterIds.build_label("198.51.100.0/24", 100, config),
      inserted_at: ~N[2026-03-31 12:00:00]
    }

    reply_same_thread = %Post{
      id: 101,
      thread_id: 100,
      poster_id: Eirinchan.PosterIds.build_label("198.51.100.0/24", 100, config),
      inserted_at: ~N[2026-03-31 12:01:00]
    }

    reply_other_thread = %Post{
      id: 102,
      thread_id: 200,
      poster_id: Eirinchan.PosterIds.build_label("198.51.100.0/24", 200, config),
      inserted_at: ~N[2026-03-31 12:02:00]
    }

    op_id = PostView.poster_id(op, config)
    same_thread_id = PostView.poster_id(reply_same_thread, config)
    other_thread_id = PostView.poster_id(reply_other_thread, config)

    assert op_id == "8d634"
    assert op_id == same_thread_id
    assert other_thread_id == "iqmka"
    assert other_thread_id != same_thread_id
    assert String.length(op_id) == 5

    html =
      PostComponents.post_identity_html(%{
        post: reply_same_thread,
        config: config,
        board: board
      })

    badge = PostView.poster_identity_badge(reply_same_thread, config)

    assert badge.class == "poster_id standard_poster_id"
    assert badge.style =~ "background-color:"
    assert badge.style =~ "border-radius: 6px;"
    assert html =~ ~s(class="poster_id standard_poster_id")
    assert html =~ same_thread_id
  end

  test "poster ids render from persisted poster_id when ip_subnet is absent" do
    config = Config.compose(%{poster_ids: true})
    board = %BoardRecord{uri: "bant", title: "Bant"}
    post = %Post{id: 100, thread_id: nil, ip_subnet: nil, poster_id: "abcde"}

    assert PostView.poster_id(post, config) == "abcde"

    html =
      PostComponents.post_identity_html(%{
        post: post,
        config: config,
        board: board
      })

    badge = PostView.poster_identity_badge(post, config)

    assert badge.class == "poster_id standard_poster_id"
    assert badge.style =~ "background-color:"
    assert html =~ ~s(class="poster_id standard_poster_id")
    assert html =~ "abcde"
  end

  test "april fools teams replace poster ids with styled team badges" do
    config = Config.compose(%{april_fools_teams: true})
    board = %BoardRecord{uri: "bant", title: "Bant"}
    post = %Post{
      id: 100,
      thread_id: nil,
      team: 2,
      ip_subnet: "198.51.100.0/24",
      inserted_at: ~N[2026-03-31 12:00:00]
    }

    badge = PostView.poster_identity_badge(post, config)
    html = PostComponents.post_identity_html(%{post: post, config: config, board: board})

    assert PostView.poster_id(post, config) == "Judaism ✡"
    assert badge.label == "Judaism ✡"
    assert badge.class == "poster_id april_fools_team"
    assert badge.style =~ "#000080"
    assert html =~ ~s(class="poster_id april_fools_team")
    assert html =~ "Judaism ✡"
  end

  test "catalog threads with no file use the dedicated no-file image" do
    config = Config.compose()
    post = %Post{id: 100, thread_id: nil, file_path: nil, thumb_path: nil, embed: nil}

    assert PostView.catalog_media_path(post, config) == "/static/no_file.png"
  end

  test "catalog deleted files still use the deleted image" do
    config = Config.compose()
    post = %Post{id: 100, thread_id: nil, file_path: "deleted", thumb_path: nil, embed: nil}

    assert PostView.catalog_media_path(post, config) == "/static/deleted.png"
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

  test "body_html keeps malformed multi-arrow quote lines green" do
    config = Config.compose()

    html =
      PostView.body_html(
        %Post{body: ">>whale\n>>>>whale\n>>123"},
        %BoardRecord{uri: "bant"},
        %Post{id: 1},
        config
      )

    assert html =~ ~s(<span class="quote">&gt;&gt;whale</span>)
    assert html =~ ~s(<span class="quote">&gt;&gt;&gt;&gt;whale</span>)
    assert length(Regex.scan(~r/<span class="quote">/u, html)) == 2
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

  test "file_image_html pre-renders the full image shell for expandable images" do
    config = Config.compose()

    file = %{
      file_name: "example.jpg",
      file_path: "/bant/src/example.jpg",
      thumb_path: "/bant/thumb/example.jpg",
      image_width: 640,
      image_height: 480
    }

    html = PostView.file_image_html(file, config)

    assert html =~ ~s(class="full-image")
    assert html =~ ~s(data-full-image-src="/bant/src/example.jpg")
  end

  test "file_image_html does not pre-render the full image shell for videos" do
    config = Config.compose()

    file = %{
      file_name: "example.mp4",
      file_path: "/bant/src/example.mp4",
      thumb_path: "/bant/thumb/example.jpg",
      file_type: "video/mp4",
      image_width: 640,
      image_height: 480
    }

    html = PostView.file_image_html(file, config)

    refute html =~ ~s(class="full-image")
    assert html =~ ~s(data-video-file="true")
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

  test "file_selector_shell keeps the native file input available and hides the dropzone by default" do
    html =
      Phoenix.LiveViewTest.render_component(&PostComponents.file_selector_shell/1,
        input_name: "file",
        input_id: "upload_file",
        multiple: false,
        upload_by_url_enabled: false
      )

    assert html =~ ~s(data-native-upload)
    assert html =~ ~r/<input[^>]+data-upload-file[^>]*>/
    refute html =~ ~r/<input[^>]+data-upload-file[^>]+hidden/
    assert html =~ ~r/<div[^>]+data-file-selector-shell[^>]+hidden/
  end
end

defmodule EirinchanWeb.PostViewQuoteTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Runtime.Config
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.PostView

  test "body_html resolves local cross-thread quote links to the cited thread" do
    board = board_fixture(%{config_overrides: %{slugify: true}})
    target_thread = thread_fixture(board, %{subject: "Cross target thread"})
    target_reply = reply_fixture(board, target_thread, %{body: "Target reply"})
    current_thread = thread_fixture(board, %{subject: "Current thread"})

    html =
      PostView.body_html(
        %Eirinchan.Posts.Post{body: ">>#{PublicIds.public_id(target_reply)}"},
        board,
        current_thread,
        Config.compose(nil, %{}, board.config_overrides)
      )

    expected_href =
      ThreadPaths.thread_path(board, target_thread, Config.compose(nil, %{}, board.config_overrides)) <>
        "##{PublicIds.public_id(target_reply)}"

    assert html =~ ~s(data-highlight-reply="#{PublicIds.public_id(target_reply)}")
    assert html =~ ~s(href="#{expected_href}")
    assert html =~ ~s|<small>(Cross-Thread)</small>|
  end

  test "body_html leaves missing local quote ids as plain text" do
    board = board_fixture()
    thread = thread_fixture(board)

    html =
      PostView.body_html(
        %Eirinchan.Posts.Post{body: ">>999999"},
        board,
        thread,
        Config.compose(nil, %{}, board.config_overrides)
      )

    assert html == "&gt;&gt;999999"
  end
end
