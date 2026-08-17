(function (window, document, $) {
  "use strict";

  var badgeSelector = ".poster_id.standard_poster_id[data-poster-id]";
  var selectedByThread = Object.create(null);

  function threadFor(node) {
    return node && node.closest ? node.closest("div.thread") : null;
  }

  function threadKey(thread) {
    if (!thread) return null;

    var board = thread.getAttribute("data-board") || window.board_name || "";
    var threadId =
      thread.getAttribute("data-thread-id") ||
      String(thread.getAttribute("id") || "").replace(/^thread_/, "");

    return board && threadId ? board + ":" + threadId : null;
  }

  function directPosts(thread) {
    return Array.prototype.filter.call(thread.children, function (child) {
      return child.matches && child.matches("div.post.op, div.post.reply");
    });
  }

  function postBadge(post) {
    return post.querySelector(badgeSelector);
  }

  function applyToThread(thread) {
    var key = threadKey(thread);
    if (!key) return;

    var selectedId = selectedByThread[key] || null;

    directPosts(thread).forEach(function (post) {
      var badge = postBadge(post);
      var matches = Boolean(
        badge && selectedId && badge.getAttribute("data-poster-id") === selectedId
      );

      if (matches) {
        post.classList.add("poster-id-highlighted", "highlighted");
      } else if (post.classList.contains("poster-id-highlighted")) {
        post.classList.remove("poster-id-highlighted", "highlighted");
      }

      if (badge) badge.setAttribute("aria-pressed", matches ? "true" : "false");
    });
  }

  function threadsIn(root) {
    if (!root) return [];

    var threads = [];
    if (root.matches && root.matches("div.thread")) threads.push(root);
    if (root.querySelectorAll) {
      threads = threads.concat(Array.prototype.slice.call(root.querySelectorAll("div.thread")));
    }

    return threads;
  }

  function apply(root) {
    var seen = [];

    threadsIn(root || document.body).forEach(function (thread) {
      if (seen.indexOf(thread) === -1) {
        seen.push(thread);
        applyToThread(thread);
      }
    });
  }

  function activate(badge) {
    var thread = threadFor(badge);
    var key = threadKey(thread);
    var posterId = badge && badge.getAttribute("data-poster-id");
    if (!thread || !key || !posterId) return;

    if (selectedByThread[key] === posterId) {
      delete selectedByThread[key];
    } else {
      selectedByThread[key] = posterId;
    }

    applyToThread(thread);
  }

  function badgeFromEvent(event) {
    return event.target && event.target.closest
      ? event.target.closest(badgeSelector)
      : null;
  }

  document.addEventListener(
    "click",
    function (event) {
      var badge = badgeFromEvent(event);
      if (!badge || (event.button !== undefined && event.button !== 0)) return;

      event.preventDefault();
      event.stopPropagation();
      activate(badge);
    },
    true
  );

  document.addEventListener(
    "keydown",
    function (event) {
      var badge = badgeFromEvent(event);
      if (!badge || (event.key !== "Enter" && event.key !== " ")) return;

      event.preventDefault();
      event.stopPropagation();
      activate(badge);
    },
    true
  );

  window.EirinchanPosterIdHighlighting = {
    apply: apply,
    clear: function (thread) {
      var key = threadKey(thread);
      if (!key) return;
      delete selectedByThread[key];
      applyToThread(thread);
    }
  };

  if ($) {
    $(function () {
      apply(document.body);
    });
    $(document).on("fragment_init new_post", function (_event, fragment) {
      var thread = threadFor(fragment);
      apply(thread || fragment);
    });
  } else if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      apply(document.body);
    });
  } else {
    apply(document.body);
  }
})(window, document, window.jQuery);
