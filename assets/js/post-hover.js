(function (window, document) {
  "use strict";

  var $ = window.jQuery;
  if (!$) return;

  var ready = window.onReady || function (callback) {
    $(callback);
  };

  ready(function () {
    var linkSelector =
      'div.body a:not([rel="nofollow"]), p.intro span.mentioned a';
    var requestCache = Object.create(null);

    function cacheContainer() {
      var container = $('form[name="postcontrols"]').first();
      return container.length ? container : $("body").first();
    }

    function boardValue(element) {
      var owner = $(element).closest("[data-board]").first();
      return owner.length ? String(owner.attr("data-board") || "") : "";
    }

    function threadIdFor(element) {
      var thread = $(element).closest('div.thread[id^="thread_"]').first();
      if (!thread.length) return "0";
      return String(thread.attr("id") || "").replace(/^thread_/, "") || "0";
    }

    function findThread(board, threadId) {
      return $('div.thread[id="thread_' + threadId + '"]').filter(function () {
        return boardValue(this) === board;
      }).first();
    }

    function findPost(board, postId) {
      return $(
        'div.post[id="reply_' + postId + '"], div.post[id="op_' + postId + '"]'
      ).filter(function () {
        return boardValue(this) === board;
      }).first();
    }

    function parseFetchedDocument(response) {
      if (response && response.nodeType === 9) return $(response);

      if (typeof response !== "string" || !response.trim()) return $();

      if (typeof window.DOMParser === "function") {
        var parsed = new window.DOMParser().parseFromString(response, "text/html");
        return $(parsed);
      }

      return $();
    }

    function mergeReplies(board, threadId, replies) {
      var thread = findThread(board, threadId);
      if (!thread.length) return;

      var firstReply = thread.find(".post.reply:first");
      var refreshTarget = thread.find("#thread-refresh-target");

      replies.each(function () {
        var reply = $(this);
        var replyId = String(reply.attr("id") || "");
        if (!replyId || findPost(board, replyId.replace(/^reply_/, "")).length) return;

        var cachedReply = reply.hide().addClass("hidden");
        if (firstReply.length) {
          firstReply.before(cachedReply);
        } else if (refreshTarget.length) {
          refreshTarget.append(cachedReply);
        }
      });
    }

    function cacheFetchedThread(thread, board) {
      thread
        .attr("data-board", board)
        .hide()
        .attr("data-cached", "yes")
        .prependTo(cacheContainer());
    }

    function openingFiles(post) {
      if (!post.hasClass("op")) return $();

      var thread = post.closest("div.thread").first();
      if (!thread.length) return $();

      return thread.children(".files").first();
    }

    function cacheStandalonePost(board, threadId, post) {
      if (!post || !post.length) return $();

      var wrapper = $("<div>")
        .addClass("thread")
        .attr("id", "thread_" + threadId)
        .attr("data-board", board)
        .attr("data-cached", "yes")
        .hide();
      var files = openingFiles(post);

      if (files.length) wrapper.append(files.clone(true, true));
      wrapper.append(post.first().clone(true, true));
      cacheContainer().prepend(wrapper);

      return findPost(board, String(post.attr("id") || "").replace(/^(?:op|reply)_/, ""));
    }

    function cacheTargetFromDocument(target, fetchedDocument) {
      var existing = findPost(target.board, target.postId);
      if (existing.length) return existing;

      var fetchedThread = fetchedDocument.find('div[id^="thread_"]').first();
      if (!fetchedThread.length) return $();

      var fetchedThreadId = String(fetchedThread.attr("id") || "").replace(
        /^thread_/,
        ""
      );
      var fetchedReplies = fetchedDocument.find("div.post.reply");
      var fetchedPost = fetchedDocument
        .find("#reply_" + target.postId + ", #op_" + target.postId)
        .first();

      if (
        fetchedThreadId === target.sourceThreadId &&
        target.sourceBoard === target.board
      ) {
        mergeReplies(target.board, target.sourceThreadId, fetchedReplies);
      } else if (findThread(target.board, fetchedThreadId).length) {
        mergeReplies(target.board, fetchedThreadId, fetchedReplies);
      } else {
        cacheFetchedThread(fetchedThread, target.board);
      }

      existing = findPost(target.board, target.postId);
      if (existing.length) return existing;

      return cacheStandalonePost(target.board, fetchedThreadId, fetchedPost);
    }

    function requestDocument(url, callback) {
      var cached = requestCache[url];

      if (cached) {
        if (cached.state === "loaded") callback(cached.document);
        else cached.callbacks.push(callback);
        return;
      }

      cached = requestCache[url] = {state: "pending", callbacks: [callback]};

      $.ajax({
        url: url,
        context: document.body,
        success: function (response) {
          cached.state = "loaded";
          cached.document = parseFetchedDocument(response);

          var callbacks = cached.callbacks.slice();
          cached.callbacks.length = 0;
          callbacks.forEach(function (pendingCallback) {
            pendingCallback(cached.document);
          });
        },
        error: function () {
          delete requestCache[url];
        }
      });
    }

    function targetForLink(link) {
      var href = link.attr("href") || "";
      var hrefMatch = href.match(/\/([^/]+)\/res\/[^#?]+#(\d+)$/);
      var textMatch;
      var postId;

      if (link.is("[data-thread]")) {
        postId = link.attr("data-thread");
      } else if (link.is("[data-highlight-reply]")) {
        postId = link.attr("data-highlight-reply");
      } else {
        textMatch = link.text().trim().match(/^>>(?:>\/([^/]+)\/)?(\d+)$/);
        if (!textMatch) return null;
        postId = textMatch[2];
      }

      if (!/^\d+$/.test(String(postId || ""))) return null;

      var sourceBoard = boardValue(link);
      if (!sourceBoard) return null;

      var board = sourceBoard;
      if (link.is("[data-thread]")) {
        board = $('form[name="post"] input[name="board"]').val() || sourceBoard;
      } else if (textMatch && textMatch[1]) {
        board = textMatch[1];
      } else if (hrefMatch && hrefMatch[1]) {
        board = hrefMatch[1];
      }

      return {
        board: String(board),
        postId: String(postId),
        sourceBoard: sourceBoard,
        sourceThreadId: threadIdFor(link),
        requestUrl: href.replace(/#.*$/, ""),
        threadLink: link.is("[data-thread]")
      };
    }

    function previewPost(post, target) {
      var preview = post.clone();

      preview.find(">.reply, >br").remove();
      preview.find("span.mentioned").remove();
      preview.find("a.post_anchor").remove();

      var files = openingFiles(post);
      if (files.length && !preview.children(".files").length) {
        preview.prepend(files.clone(true, true));
      }

      return preview
        .attr("id", "post-hover-" + target.postId)
        .attr("data-board", target.board)
        .addClass("post-hover reply post")
        .css({
          "border-style": "solid",
          "box-shadow": "1px 1px 1px #999",
          display: "block",
          position: "absolute",
          "font-style": "normal",
          "z-index": "100"
        });
    }

    function postIsFullyVisible(post) {
      if (!post.is(":visible")) return false;

      var top = post.offset().top;
      var viewportTop = $(window).scrollTop();
      var viewportBottom = viewportTop + $(window).height();
      return top >= viewportTop && top + post.height() <= viewportBottom;
    }

    function installHover(linkElement) {
      var link = $(linkElement);
      var target = targetForLink(link);
      if (!target) return;

      var post = $();
      var hovered = false;
      var lastPointer = {x: 0, y: 0};

      function show() {
        if (!post.length) return;

        if (postIsFullyVisible(post)) {
          post.addClass("highlighted");
          return;
        }

        $(".post-hover").remove();
        $("body").first().append(previewPost(post, target));
        link.trigger("mousemove");
      }

      link
        .hover(
          function (event) {
            hovered = true;
            lastPointer = {x: event.pageX, y: event.pageY};
            post = findPost(target.board, target.postId);

            if (post.length) {
              show();
              return;
            }

            requestDocument(target.requestUrl, function (fetchedDocument) {
              post = findPost(target.board, target.postId);
              if (!post.length) {
                post = cacheTargetFromDocument(target, fetchedDocument);
              }

              if (hovered && post && post.length) show();
            });
          },
          function () {
            hovered = false;
            if (post && post.length) post.removeClass("highlighted");
            $(".post-hover").remove();
          }
        )
        .mousemove(function (event) {
          var preview = $(
            '#post-hover-' +
              target.postId +
              '[data-board="' +
              target.board +
              '"]'
          );
          if (!preview.length) return;

          var viewportTop = $(window).scrollTop();
          if (target.threadLink) viewportTop = 0;

          var pointerY = event.pageY;
          if (target.threadLink) pointerY -= $(window).scrollTop();

          var top = (pointerY || lastPointer.y) - 10;
          if (pointerY < viewportTop + 15) {
            top = viewportTop;
          } else if (
            pointerY >
            viewportTop + $(window).height() - preview.height() - 15
          ) {
            top = viewportTop + $(window).height() - preview.height() - 15;
          }

          preview.css("left", event.pageX ? event.pageX : lastPointer.x).css("top", top);
        });
    }

    function initHover(root) {
      var scope = root ? $(root) : $(document);

      scope
        .filter(linkSelector)
        .add(scope.find(linkSelector))
        .each(function () {
          if (this.dataset.postHoverBound === "true") return;
          this.dataset.postHoverBound = "true";
          installHover(this);
        });
    }

    initHover(document.body);
    window.init_hover = initHover;

    $(document).on("fragment_init", function (_event, root) {
      initHover(root);
    });
    $(document).on("new_post", function (_event, root) {
      initHover(root);
    });
  });
})(window, document);
