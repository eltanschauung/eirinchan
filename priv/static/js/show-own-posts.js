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

  var quoteAnnotationOrder = {
    op: 0,
    you: 1,
    "cross-thread": 2
  };

  function nextNonWhitespaceSibling(node) {
    var next = node.nextSibling;

    while (next && next.nodeType === 3 && /^\s*$/.test(next.nodeValue)) {
      next = next.nextSibling;
    }

    return next;
  }

  function quoteAnnotationKind(marker) {
    if (!marker || marker.nodeType !== 1 || marker.tagName !== "SMALL") return null;

    var explicitKind = marker.getAttribute("data-quote-annotation");
    if (explicitKind) return explicitKind;

    var text = $(marker).text();

    if (text === _("(OP)")) return "op";
    if (text === _("(You)")) return "you";
    if (text === _("(Cross-Thread)")) return "cross-thread";

    return null;
  }

  function normalizeQuoteAnnotations(group) {
    var markers = Array.prototype.slice.call(group.children).filter(function (child) {
      return child.tagName === "SMALL";
    });
    var markersByKind = {};

    markers.forEach(function (marker) {
      var kind = quoteAnnotationKind(marker);

      if (!kind || markersByKind[kind]) {
        marker.remove();
        return;
      }

      marker.setAttribute("data-quote-annotation", kind);
      markersByKind[kind] = marker;
    });

    markers = Object.keys(markersByKind)
      .sort(function (left, right) {
        var leftOrder =
          Object.prototype.hasOwnProperty.call(quoteAnnotationOrder, left)
            ? quoteAnnotationOrder[left]
            : Number.MAX_SAFE_INTEGER;
        var rightOrder =
          Object.prototype.hasOwnProperty.call(quoteAnnotationOrder, right)
            ? quoteAnnotationOrder[right]
            : Number.MAX_SAFE_INTEGER;

        return leftOrder - rightOrder;
      })
      .map(function (kind) {
        return markersByKind[kind];
      });

    group.textContent = "";

    markers.forEach(function (marker, index) {
      if (index) group.appendChild(document.createTextNode(" "));
      group.appendChild(marker);
    });
  }

  function quoteAnnotationGroup(link) {
    var next = nextNonWhitespaceSibling(link);

    if (
      next &&
      next.nodeType === 1 &&
      next.hasAttribute("data-quote-annotations")
    ) {
      normalizeQuoteAnnotations(next);
      return next;
    }

    var group = document.createElement("span");
    group.className = "quote-annotations";
    group.setAttribute("data-quote-annotations", "");
    link.parentNode.insertBefore(group, link.nextSibling);
    link.parentNode.insertBefore(document.createTextNode(" "), group);

    var legacyNode = group.nextSibling;

    while (legacyNode) {
      var followingNode = legacyNode.nextSibling;

      if (legacyNode.nodeType === 3 && /^\s*$/.test(legacyNode.nodeValue)) {
        legacyNode.remove();
      } else {
        var kind = quoteAnnotationKind(legacyNode);
        if (!kind) break;

        legacyNode.setAttribute("data-quote-annotation", kind);
        group.appendChild(legacyNode);
      }

      legacyNode = followingNode;
    }

    normalizeQuoteAnnotations(group);
    return group;
  }

  function addQuoteMarker(link) {
    var group = quoteAnnotationGroup(link);

    if (!group.querySelector('[data-quote-annotation="you"]')) {
      var marker = document.createElement("small");
      marker.setAttribute("data-quote-annotation", "you");
      marker.textContent = _("(You)");
      group.appendChild(marker);
    }

    normalizeQuoteAnnotations(group);
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
      .filter(".post.op, .post.reply")
      .add($(root).find(".post.op, .post.reply"))
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

  function ownedPostIds(root) {
    var postIds = [];

    $(root)
      .filter(".post[id]")
      .add($(root).find(".post[id]"))
      .each(function () {
        if (!this.classList.contains("you") && !this.querySelector(".own_post")) return;

        var match = (this.id || "").match(/^(?:op|reply)_(\d+)$/);

        if (match) postIds.push(match[1]);
      });

    return postIds;
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

  function rememberRenderedMarkers(root) {
    threadsIn(root || document.body).each(function () {
      var board = threadBoard(this);
      var postIds = ownedPostIds(this);

      if (board && postIds.length) rememberOwnPosts(board, postIds);
    });
  }

  function prepareReplacement(current, replacement) {
    var postBoard = threadBoard(current);
    var currentPostIds = ownedPostIds(current);

    if (postBoard) {
      if (currentPostIds.length) {
        rememberOwnPosts(postBoard, currentPostIds);
      }

      applyCachedMarkers(replacement, postBoard);
    }

    rememberRenderedMarkers(current);

    threadsIn(replacement).each(function () {
      var board = threadBoard(this);
      if (board) applyCachedMarkers(this, board);
    });
  }

  window.EirinchanShowOwnPosts = {
    prepareReplacement: prepareReplacement
  };

  var currentBoard = null;

  $(function () {
    if (!showYousEnabled()) return;

    currentBoard = $('input[name="board"]').first().val();
    processThreads(document.body);
  });

  $(document).on("ajax_after_post", function (_event, post, submittedForm) {
    var submittedBoard = $(submittedForm).find('input[name="board"]').first().val();
    var board = submittedBoard || currentBoard;

    if (showYousEnabled() && board && post && post.id) {
      rememberOwnPosts(board, [post.id]);
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
