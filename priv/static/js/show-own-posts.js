(function () {
  "use strict";

  function parsePostId(value) {
    var parsed = parseInt(value, 10);
    return isNaN(parsed) ? null : parsed;
  }

  function readCookie(name, fallback) {
    var runtime = window.EirinchanRuntime || {};

    if (typeof runtime.readCookie === "function") {
      return runtime.readCookie(name, fallback);
    }

    var escapedName = String(name).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    var match = document.cookie.match(new RegExp("(?:^|; )" + escapedName + "=([^;]*)"));
    return match ? decodeURIComponent(match[1]) : fallback;
  }

  function showYousEnabled() {
    return readCookie("show_yous", "true") !== "false";
  }

  function readOwnPosts() {
    try {
      return JSON.parse(localStorage.own_posts || "{}");
    } catch (_error) {
      return {};
    }
  }

  function writeOwnPosts(value) {
    localStorage.own_posts = JSON.stringify(value);
  }

  function rememberOwnPosts(board, postIds) {
    if (!showYousEnabled() || !board || !postIds.length) return;

    var ownPosts = readOwnPosts();
    var boardPosts = ownPosts[board] || [];

    postIds.forEach(function (postId) {
      var normalized = String(postId);

      if (boardPosts.indexOf(normalized) === -1) {
        boardPosts.push(normalized);
      }
    });

    ownPosts[board] = boardPosts;
    writeOwnPosts(ownPosts);
  }

  function addQuoteMarker(link) {
    var next = link.nextSibling;

    while (next && next.nodeType === 3 && /^\s*$/.test(next.nodeValue)) {
      next = next.nextSibling;
    }

    if (next && next.nodeType === 1 && next.tagName === "SMALL" && $(next).text() === _("(You)")) {
      return;
    }

    $(link).after(" <small>" + _("(You)") + "</small>");
  }

  function markQuoteLinks(links, ownedByPostId) {
    $(links).each(function () {
      var postId = this.getAttribute("data-cite-reply") || this.getAttribute("data-highlight-reply");

      if (postId && ownedByPostId[postId]) {
        addQuoteMarker(this);
      }
    });
  }

  function markOwnedPosts(root, board, postIds) {
    if (!showYousEnabled()) return;

    var ownedByPostId = {};

    postIds.forEach(function (postId) {
      ownedByPostId[String(postId)] = true;
    });

    $(root)
      .find(".post.op, .post.reply")
      .each(function () {
        var match = (this.id || "").match(/^(?:op|reply)_(\d+)$/);

        if (!match || !ownedByPostId[match[1]]) return;

        var post = $(this);

        if (post.is(".you")) return;

        post.addClass("you");

        if (!post.find(".own_post").length) {
          var name = post.find("span.name").first();

          if (name.length) {
            name.append(' <span class="own_post">' + _("(You)") + "</span>");
          }
        }
      });

    markQuoteLinks($(root).find("div.body a[data-cite-reply], div.body a[data-highlight-reply]"), ownedByPostId);
    markQuoteLinks($(root).find("span.mentioned a[data-highlight-reply]"), ownedByPostId);
    rememberOwnPosts(board, postIds);
  }

  function collectPostIds(root) {
    var postIds = {};

    $(root)
      .find('.post_no[id^="post_no_"], a[data-cite-reply], a[data-highlight-reply]')
      .each(function () {
        var postId = null;

        if (this.hasAttribute("data-cite-reply")) {
          postId = parsePostId(this.getAttribute("data-cite-reply"));
        } else if (this.hasAttribute("data-highlight-reply")) {
          postId = parsePostId(this.getAttribute("data-highlight-reply"));
        } else {
          postId = parsePostId((this.id || "").replace("post_no_", ""));
        }

        if (postId !== null) {
          postIds[postId] = true;
        }
      });

    return Object.keys(postIds);
  }

  function threadBoard(root) {
    var thread = $(root);

    if (!thread.is(".thread[data-board]")) {
      thread = thread.closest(".thread[data-board]");
    }

    return thread.attr("data-board") || null;
  }

  function applyCachedMarkers(root, board) {
    var cached = readOwnPosts()[board] || [];

    if (cached.length) {
      markOwnedPosts(root, board, cached);
    }
  }

  function processThread(root) {
    if (!showYousEnabled()) return;

    var board = threadBoard(root);
    var postIds = collectPostIds(root);

    if (!board || !postIds.length) return;

    applyCachedMarkers(root, board);

    $.ajax({
      type: "POST",
      url: "/api/you-markers/" + encodeURIComponent(board),
      contentType: "application/json",
      dataType: "json",
      data: JSON.stringify({ post_ids: postIds })
    }).done(function (response) {
      if (response && response.enabled !== false) {
        markOwnedPosts(root, board, response.post_ids || []);
      }
    });
  }

  function threadsIn(root) {
    var container = $(root);
    return container.filter(".thread[data-board]").add(container.find(".thread[data-board]"));
  }

  function processThreads(root) {
    threadsIn(root || document.body).each(function () {
      processThread(this);
    });
  }

  var currentBoard = null;

  $(function () {
    if (!showYousEnabled()) return;

    currentBoard = $('input[name="board"]').first().val();
    processThreads(document.body);
  });

  $(document).on("ajax_after_post", function (_event, post) {
    if (showYousEnabled() && currentBoard) {
      rememberOwnPosts(currentBoard, [post.id]);
    }
  });

  $(document).on("new_post", function (_event, postElement) {
    if (!showYousEnabled()) return;

    var thread = $(postElement).closest(".thread[data-board]")[0] || postElement;
    processThread(thread);
  });

  $(document).on("fragment_init", function (_event, root) {
    processThreads(root);
  });
})();
