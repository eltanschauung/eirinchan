$(document).ready(function () {
  if (active_page !== "index" && active_page !== "ukko") {
    return;
  }

  if (!localStorage.hiddenthreads) {
    localStorage.hiddenthreads = "{}";
  }

  var hiddenThreads = JSON.parse(localStorage.hiddenthreads);

  function storeHiddenThreads() {
    localStorage.hiddenthreads = JSON.stringify(hiddenThreads);
  }

  function pruneHiddenThreads() {
    var cutoff = Math.round(Date.now() / 1000) - 60 * 60 * 24 * 7;

    for (var board in hiddenThreads) {
      if (!Object.prototype.hasOwnProperty.call(hiddenThreads, board)) {
        continue;
      }

      for (var postId in hiddenThreads[board]) {
        if (
          Object.prototype.hasOwnProperty.call(hiddenThreads[board], postId) &&
          hiddenThreads[board][postId] < cutoff
        ) {
          delete hiddenThreads[board][postId];
        }
      }
    }

    storeHiddenThreads();
  }

  function threadBoard(thread) {
    return $(thread).data("board");
  }

  function threadId(thread) {
    var directId = $(thread).data("thread-id");

    if (directId) {
      return String(directId);
    }

    return String(
      $(thread).find("div.post.op > p.intro > a.post_no:eq(1)").first().text() || ""
    );
  }

  function isThreadHidden(thread) {
    var board = threadBoard(thread);
    var id = threadId(thread);

    return !!(board && id && hiddenThreads[board] && hiddenThreads[board][id]);
  }

  function removeThreadMarker(thread) {
    $(thread).children(".thread-hidden-marker").remove();
  }

  function clearThreadVisibilityStyles(thread) {
    $(thread)
      .find(
        ".post.reply, .omitted, br, div.post.op > .body, div.post.op > .files, div.post.op > .video-container, div.post.reply > .body, div.post.reply > .files, div.post.reply > .video-container"
      )
      .each(function () {
        this.style.removeProperty("display");

        if (!this.getAttribute("style")) {
          this.removeAttribute("style");
        }
      });
  }

  function buildThreadMarker(thread) {
    var marker = $(thread).find("div.post.op > p.intro").first().clone();

    marker.addClass("thread-hidden");
    marker.addClass("thread-hidden-marker");
    marker.find(".thread-top-controls").remove();
    marker.find("button, input").remove();
    marker.find('a[href]:not([href$=".html"])').remove();
    marker.html(marker.html().replace(" [] ", " "));
    marker.html(marker.html().replace(" [] ", " "));

    $('<a class="unhide-thread-link" style="margin-right:5px;" href="#">[+]</a><span> </span>')
      .insertBefore(marker.find(":first"))
      .on("click", function (event) {
        event.preventDefault();
        unhideThread(thread);
      });

    return marker;
  }

  function ensureThreadMarker(thread) {
    var existingMarker = $(thread).children(".thread-hidden-marker").first();

    if (existingMarker.length) {
      return existingMarker;
    }

    var marker = buildThreadMarker(thread);
    var insertionTarget = $(thread).children().not("h2").first();

    if (insertionTarget.length) {
      marker.insertBefore(insertionTarget);
    } else {
      $(thread).append(marker);
    }

    return marker;
  }

  function hideThread(thread, options) {
    var settings = options || {};
    var board = threadBoard(thread);
    var id = threadId(thread);

    if (!board || !id) {
      return;
    }

    if (!settings.skipStore) {
      if (!hiddenThreads[board]) {
        hiddenThreads[board] = {};
      }

      hiddenThreads[board][id] = Math.round(Date.now() / 1000);
      storeHiddenThreads();
    }

    clearThreadVisibilityStyles(thread);
    ensureThreadMarker(thread);
    $(thread).addClass("thread-hidden");
  }

  function unhideThread(thread, options) {
    var settings = options || {};
    var board = threadBoard(thread);
    var id = threadId(thread);

    if (!settings.skipStore && board && id && hiddenThreads[board]) {
      delete hiddenThreads[board][id];
      storeHiddenThreads();
    }

    $(thread).removeClass("thread-hidden");
    clearThreadVisibilityStyles(thread);
    removeThreadMarker(thread);
  }

  function bindThreadControls(thread) {
    var hideLink = $(thread).find("div.post.op > p.intro .hide-thread-link").first();

    if (!hideLink.length) {
      return;
    }

    hideLink.off("click.hideThread").on("click.hideThread", function (event) {
      event.preventDefault();
      hideThread(thread);
    });
  }

  function syncThread(thread) {
    bindThreadControls(thread);

    if (isThreadHidden(thread)) {
      hideThread(thread, {skipStore: true});
    } else {
      unhideThread(thread, {skipStore: true});
    }
  }

  function syncThreads(root) {
    var scope = root ? $(root) : $(document);

    scope
      .filter(".thread")
      .add(scope.find(".thread"))
      .each(function () {
        syncThread(this);
      });
  }

  pruneHiddenThreads();
  syncThreads(document.body);
  setTimeout(function () {
    syncThreads(document.body);
  }, 0);

  $(document).on("clear_hidden_threads", function () {
    hiddenThreads = {};
    storeHiddenThreads();

    $(".thread").each(function () {
      unhideThread(this, {skipStore: true});
    });
  });

  $(document).on("fragment_init", function (_event, root) {
    syncThreads(root);
  });

  $(document).on("filter_page", function () {
    syncThreads(document.body);
  });

  $(document).on("new_post", function (_event, post) {
    var thread = $(post).closest(".thread");

    if (thread.length) {
      syncThreads(thread);
      return;
    }

    syncThreads(post);
  });
});
