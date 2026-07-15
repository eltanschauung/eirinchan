/*
 * Eirinchan live page updater.
 *
 * This keeps the public compatibility hooks from the Vichan updater while
 * isolating scheduling, transport, and page-specific DOM reconciliation.
 */
window.auto_reload_enabled = true;

(function (window, document) {
  "use strict";

  var $ = window.jQuery;
  if (!$ || typeof window.URL !== "function" || typeof window.DOMParser !== "function") {
    return;
  }

  /*
   * Released bundles may still contain the legacy updater until the bundle
   * generation task is run.  Hide the compatibility id before jQuery's ready
   * queue drains: the old callback exits, then this callback restores the id.
   */
  var maskedUpdater = document.querySelector("[data-live-updater]");
  var restoreLegacyUpdaterId = !!(maskedUpdater && maskedUpdater.id === "updater");

  if (restoreLegacyUpdaterId) {
    maskedUpdater.removeAttribute("id");
  }

  $(function () {
    var updater = document.querySelector("[data-live-updater]") || document.getElementById("updater");

    if (restoreLegacyUpdaterId && updater && !document.getElementById("updater")) {
      updater.id = "updater";
    }
    var statusInput = document.getElementById("auto_update_status");
    var statusText = document.getElementById("update_secs");
    var toggleLink = document.getElementById("update_thread");

    if (!updater || !statusInput || !statusText || !toggleLink) {
      return;
    }

    var pageKind = updater.getAttribute("data-page-kind") || detectLegacyPageKind();
    var adapter = createPageAdapter(pageKind);

    if (!adapter || !adapter.currentTarget()) {
      return;
    }

    var runtime = window.EirinchanRuntime || {};
    var settings = createSettings();
    var cookieName = "live_page_auto_update";
    var minimumDelay = positiveDelay(settings.get("min_delay_bottom", 5000), 5000);
    var errorDelay = positiveDelay(settings.get("error_delay", 30000), 30000);

    // Index pages historically refresh at a fixed five-second cadence. Keep
    // that behavior because hiding/filtering state is reconciled on each pass.
    if (pageKind === "index") {
      minimumDelay = 5000;
      errorDelay = 5000;
    }

    var state = {
      request: null,
      timer: null,
      deadline: 0,
      newItems: 0,
      originalTitle: document.title,
      windowActive: !document.hidden,
      lastRequestAt: Date.now(),
      scrollFramePending: false,
      suspended: false
    };

    function createSettings() {
      if (typeof window.script_settings === "function") {
        return new window.script_settings("auto-reload");
      }

      if (typeof script_settings === "function") {
        return new script_settings("auto-reload");
      }

      return {
        get: function (_key, fallback) {
          return fallback;
        }
      };
    }

    function positiveDelay(value, fallback) {
      var parsed = Number(value);
      return isFinite(parsed) && parsed > 0 ? parsed : fallback;
    }

    function detectLegacyPageKind() {
      if (document.body.classList.contains("active-catalog") && document.getElementById("Grid")) {
        return "catalog";
      }

      if (
        document.body.classList.contains("active-index") &&
        document.getElementById("board-refresh-target")
      ) {
        return "index";
      }

      if (
        document.querySelectorAll("div.banner").length !== 0 &&
        document.querySelectorAll(".post.op").length === 1 &&
        document.getElementById("thread-refresh-target")
      ) {
        return "thread";
      }

      return null;
    }

    function createPageAdapter(kind) {
      if (kind === "catalog") {
        return {
          kind: kind,
          currentTarget: function () {
            return document.getElementById("Grid");
          },
          apply: applyCatalogFragment
        };
      }

      if (kind === "index") {
        return {
          kind: kind,
          currentTarget: function () {
            return document.getElementById("board-refresh-target");
          },
          apply: applyBoardFragment
        };
      }

      if (kind === "thread") {
        return {
          kind: kind,
          currentTarget: function () {
            return document.getElementById("thread-refresh-target");
          },
          apply: applyThreadFragment
        };
      }

      return null;
    }

    function readLivePageCookie() {
      var value = runtime.readCookie ? runtime.readCookie(cookieName, "1") : null;

      if (value === null) {
        var match = document.cookie.match(new RegExp("(?:^|; )" + cookieName + "=([^;]*)"));
        if (!match) {
          return true;
        }

        try {
          value = decodeURIComponent(match[1]);
        } catch (_error) {
          value = match[1];
        }
      }

      return value !== "0";
    }

    function writeLivePageCookie(enabled) {
      if (runtime.writeCookie) {
        runtime.writeCookie(cookieName, enabled ? "1" : "0", {
          path: "/",
          maxAge: 60 * 60 * 24 * 365,
          sameSite: "lax"
        });
        return;
      }

      document.cookie =
        cookieName +
        "=" +
        encodeURIComponent(enabled ? "1" : "0") +
        "; path=/; max-age=" +
        60 * 60 * 24 * 365 +
        "; samesite=lax";
    }

    function enabled() {
      return statusInput.checked && !statusInput.disabled;
    }

    function setStatus(value) {
      statusText.textContent = value === null || typeof value === "undefined" ? "" : String(value);
    }

    function syncButtonState() {
      var active = enabled();
      window.auto_reload_enabled = active;
      updater.classList.toggle("paused", !active);
      updater.classList.toggle("active", active);
      toggleLink.setAttribute("aria-pressed", active ? "true" : "false");
    }

    function cancelCountdown() {
      if (state.timer !== null) {
        window.clearTimeout(state.timer);
        state.timer = null;
      }
    }

    function schedule(delay) {
      cancelCountdown();

      if (state.suspended || !enabled()) {
        syncButtonState();
        return;
      }

      state.deadline = Date.now() + positiveDelay(delay, minimumDelay);
      tickCountdown();
      syncButtonState();
    }

    function scheduleIfEnabled(delay) {
      if (!state.suspended && enabled()) {
        schedule(delay);
      }
    }

    function tickCountdown() {
      if (state.suspended || !enabled()) {
        cancelCountdown();
        syncButtonState();
        return;
      }

      var remaining = Math.max(state.deadline - Date.now(), 0);
      setStatus(Math.ceil(remaining / 1000));

      if (remaining === 0) {
        state.timer = null;
        requestRefresh(false);
        return;
      }

      state.timer = window.setTimeout(tickCountdown, Math.min(remaining, 1000));
    }

    function fragmentUrl() {
      var url = new window.URL(document.location.href);
      url.searchParams.set("fragment", "1");
      return url.toString();
    }

    function currentFragmentHash() {
      var target = adapter.currentTarget();
      return target && target.dataset ? target.dataset.fragmentMd5 || "" : "";
    }

    function quotedEtag(value) {
      return '"' + String(value || "").replace(/["\\]/g, "") + '"';
    }

    function parseFragment(markup) {
      return new window.DOMParser().parseFromString(markup, "text/html");
    }

    function elementVisible(element) {
      return !!(element && element.offsetParent);
    }

    function shouldDeferForMedia() {
      if (document.querySelector("img.full-image[src]")) {
        return true;
      }

      return (
        Array.prototype.some.call(document.querySelectorAll("audio, video"), elementVisible) ||
        Array.prototype.some.call(
          document.querySelectorAll(".video-container iframe"),
          elementVisible
        ) ||
        Array.prototype.some.call(document.querySelectorAll(".post-hover"), elementVisible)
      );
    }

    function finishRequest(request) {
      if (state.request === request) {
        state.request = null;
      }
    }

    function requestRefresh(_manual) {
      if (state.suspended) {
        return false;
      }

      if (state.request !== null) {
        scheduleIfEnabled(minimumDelay);
        return false;
      }

      if (shouldDeferForMedia()) {
        scheduleIfEnabled(minimumDelay);
        return false;
      }

      cancelCountdown();
      setStatus("0");
      state.lastRequestAt = Date.now();

      var hash = currentFragmentHash();
      var headers = hash ? { "If-None-Match": quotedEtag(hash) } : {};
      var request = $.ajax({
        url: fragmentUrl(),
        cache: false,
        dataType: "html",
        headers: headers
      });

      state.request = request;

      request.done(function (markup, textStatus, xhr) {
        finishRequest(request);

        if ((xhr && xhr.status === 304) || textStatus === "notmodified") {
          scheduleIfEnabled(minimumDelay);
          return;
        }

        var fragmentDocument = parseFragment(markup || "");
        if (!fragmentDocument) {
          handleUnknownResponse();
          return;
        }

        syncGlobalMessage(fragmentDocument);

        var result = adapter.apply(fragmentDocument);
        if (!result || result.ok !== true) {
          handleUnknownResponse();
          return;
        }

        completeSuccessfulRefresh(result);
      });

      request.fail(function (xhr, textStatus, errorThrown) {
        finishRequest(request);

        if (request.eirinchanPagehideAbort) {
          return;
        }

        if (xhr && xhr.status === 304) {
          scheduleIfEnabled(minimumDelay);
          return;
        }

        handleRequestError(xhr, textStatus, errorThrown);
      });

      request.always(function () {
        finishRequest(request);
      });

      return false;
    }

    function handleUnknownResponse() {
      setStatus(translate("Unknown error"));
      scheduleIfEnabled(errorDelay);
    }

    function handleRequestError(xhr, textStatus, errorThrown) {
      if (pageKind === "thread" && xhr && xhr.status === 404) {
        cancelCountdown();
        setStatus(translate("Thread deleted or pruned"));
        statusInput.checked = false;
        statusInput.disabled = true;
        syncButtonState();
        return;
      }

      if (textStatus === "error" && errorThrown) {
        setStatus("Error: " + errorThrown);
      } else if (textStatus) {
        setStatus(translate("Error: ") + textStatus);
      } else {
        setStatus(translate("Unknown error"));
      }

      scheduleIfEnabled(errorDelay);
    }

    function completeSuccessfulRefresh(result) {
      var newItems = result.newItems || 0;

      if (newItems > 0) {
        state.newItems += newItems;
        updateDocumentTitle();
      }

      reconcileReadState();

      if (enabled()) {
        schedule(minimumDelay);
      } else {
        setStatus(pausedStatusMessage(newItems));
      }
    }

    function pausedStatusMessage(newItems) {
      if (pageKind === "catalog") {
        return newItems > 0
          ? formatMessage("Catalog updated with {0} new thread(s)", newItems)
          : translate("No new threads found");
      }

      if (pageKind === "index") {
        return newItems > 0
          ? formatMessage("Board updated with {0} new post(s)", newItems)
          : translate("No new posts found");
      }

      return newItems > 0
        ? formatMessage("Thread updated with {0} new post(s)", newItems)
        : translate("No new posts found");
    }

    function translate(message) {
      return typeof window._ === "function" ? window._(message) : message;
    }

    function formatMessage(message, value) {
      var translated = translate(message);
      if (typeof window.fmt === "function") {
        return window.fmt(translated, [value]);
      }

      return translated.replace("{0}", value);
    }

    function numericSuffix(value) {
      var match = String(value || "").match(/(\d+)$/);
      return match ? parseInt(match[1], 10) : 0;
    }

    function syncGlobalMessage(fragmentDocument) {
      var replacement = fragmentDocument.querySelector("#global-message-refresh-target");
      var current = document.getElementById("global-message-refresh-target");

      if (replacement && current) {
        current.replaceWith(replacement);
      }
    }

    function dispatchNewPost(post) {
      if (!post) {
        return;
      }

      if (
        window.EirinchanFrontend &&
        typeof window.EirinchanFrontend.dispatchNewPost === "function"
      ) {
        window.EirinchanFrontend.dispatchNewPost(post);
      } else {
        $(document).trigger("new_post", post);
      }
    }

    function initFragment(root, options) {
      if (
        root &&
        window.EirinchanFrontend &&
        typeof window.EirinchanFrontend.initFragment === "function"
      ) {
        window.EirinchanFrontend.initFragment(root, options || {});
      }
    }

    function copyFragmentHash(source, destination) {
      if (source && destination && source.dataset && source.dataset.fragmentMd5) {
        destination.dataset.fragmentMd5 = source.dataset.fragmentMd5;
      }
    }

    function applyCatalogFragment(fragmentDocument) {
      var replacement = fragmentDocument.getElementById("Grid");
      var current = document.getElementById("Grid");

      if (!replacement || !current) {
        return { ok: false };
      }

      var maximumCurrentId = 0;
      Array.prototype.forEach.call(current.children, function (node) {
        if (node.classList && node.classList.contains("mix")) {
          maximumCurrentId = Math.max(maximumCurrentId, numericSuffix(node.getAttribute("data-id")));
        }
      });

      var newItems = 0;
      var nextChildren = document.createDocumentFragment();

      Array.prototype.forEach.call(replacement.childNodes, function (node) {
        var clone = node.cloneNode(true);

        if (
          clone.nodeType === 1 &&
          clone.classList.contains("mix") &&
          numericSuffix(clone.getAttribute("data-id")) > maximumCurrentId
        ) {
          newItems += 1;
        }

        nextChildren.appendChild(clone);
      });

      while (current.firstChild) {
        current.removeChild(current.firstChild);
      }
      current.appendChild(nextChildren);
      copyFragmentHash(replacement, current);
      initFragment(current, { reason: "auto-reload-catalog" });

      return { ok: true, newItems: newItems };
    }

    function captureBoardState(current) {
      var result = {
        maximumPostId: 0,
        threads: {},
        checkedPostIds: {}
      };
      var threads = current.querySelector("#board-threads");

      if (!threads) {
        return result;
      }

      Array.prototype.forEach.call(threads.querySelectorAll(".post[id]"), function (post) {
        result.maximumPostId = Math.max(result.maximumPostId, numericSuffix(post.id));
      });

      Array.prototype.forEach.call(threads.querySelectorAll(".thread[id]"), function (thread) {
        result.threads[thread.id] = {
          hidden: thread.classList.contains("thread-hidden"),
          display: thread.style.display || "",
          watched: thread.dataset ? thread.dataset.watched : null
        };
      });

      Array.prototype.forEach.call(threads.querySelectorAll("input.delete:checked[id]"), function (input) {
        result.checkedPostIds[input.id] = true;
      });

      return result;
    }

    function restoreBoardState(replacement, saved) {
      Array.prototype.forEach.call(
        replacement.querySelectorAll("#board-threads .thread[id]"),
        function (thread) {
          var prior = saved.threads[thread.id];
          if (!prior) {
            return;
          }

          if (prior.hidden) {
            thread.classList.add("thread-hidden");
          }
          if (prior.display) {
            thread.style.display = prior.display;
          }
          if (prior.watched !== null && thread.dataset) {
            thread.dataset.watched = prior.watched;
          }
        }
      );

      Array.prototype.forEach.call(
        replacement.querySelectorAll("#board-threads input.delete[id]"),
        function (input) {
          if (saved.checkedPostIds[input.id]) {
            input.checked = true;
          }
        }
      );
    }

    function applyBoardFragment(fragmentDocument) {
      var replacement = fragmentDocument.getElementById("board-refresh-target");
      var current = document.getElementById("board-refresh-target");
      var replacementPages = fragmentDocument.getElementById("board-pages-target");
      var currentPages = document.getElementById("board-pages-target");

      if (!replacement || !current) {
        return { ok: false };
      }

      var saved = captureBoardState(current);
      var newPostIds = [];

      restoreBoardState(replacement, saved);

      Array.prototype.forEach.call(replacement.querySelectorAll(".post[id]"), function (post) {
        if (numericSuffix(post.id) > saved.maximumPostId) {
          newPostIds.push(post.id);
        }
      });

      current.replaceWith(replacement);
      if (currentPages && replacementPages) {
        currentPages.replaceWith(replacementPages);
      }

      initFragment(replacement, { reason: "auto-reload-board" });
      newPostIds.forEach(function (id) {
        dispatchNewPost(document.getElementById(id));
      });

      return { ok: true, newItems: newPostIds.length };
    }

    function directReplyNodes(target) {
      return Array.prototype.filter.call(target.children, function (node) {
        return node.matches && node.matches("div.post.reply[id]");
      });
    }

    function preserveReplyUiState(current, replacement) {
      var currentCheckbox = current.querySelector("input.delete");
      var replacementCheckbox = replacement.querySelector("input.delete");

      if (currentCheckbox && replacementCheckbox) {
        replacementCheckbox.checked = currentCheckbox.checked;
      }

      ["highlighted", "mentioned", "filtered", "hidden"].forEach(function (className) {
        if (current.classList.contains(className)) {
          replacement.classList.add(className);
        }
      });

      if (current.style.display) {
        replacement.style.display = current.style.display;
      }
    }

    function replyVersion(reply) {
      return reply.getAttribute("data-fragment-version") || "";
    }

    function initializeChangedReply(reply, isNew) {
      initFragment(reply, { reason: isNew ? "auto-reload-thread-new" : "auto-reload-thread-change" });

      if (typeof window.syncBacklinksFromPost === "function") {
        window.syncBacklinksFromPost(reply);
      }

      if (isNew) {
        dispatchNewPost(reply);
      }
    }

    function applyThreadFragment(fragmentDocument) {
      var replacement = fragmentDocument.getElementById("thread-refresh-target");
      var current = document.getElementById("thread-refresh-target");

      if (!replacement || !current) {
        return { ok: false };
      }

      var currentById = {};
      directReplyNodes(current).forEach(function (reply) {
        currentById[reply.id] = reply;
      });

      var changedReplies = [];
      var newReplies = [];
      var nextReplies = document.createDocumentFragment();

      directReplyNodes(replacement).forEach(function (incoming) {
        var existing = currentById[incoming.id];
        var clone = incoming.cloneNode(true);
        var reply = existing;

        if (!existing) {
          reply = clone;
          newReplies.push(clone);
        } else if (replyVersion(existing) !== replyVersion(clone)) {
          preserveReplyUiState(existing, clone);
          reply = clone;
          changedReplies.push(clone);
        }

        nextReplies.appendChild(reply);
        nextReplies.appendChild(document.createElement("br")).className = "clear";
      });

      while (current.firstChild) {
        current.removeChild(current.firstChild);
      }
      current.appendChild(nextReplies);

      changedReplies.forEach(function (reply) {
        initializeChangedReply(reply, false);
      });
      newReplies.forEach(function (reply) {
        initializeChangedReply(reply, true);
      });

      copyFragmentHash(replacement, current);
      current.dataset.boardPageNum = replacement.dataset.boardPageNum || "";
      current.dataset.boardPagePath = replacement.dataset.boardPagePath || "";

      if (current.dataset.boardPageNum) {
        $("#thread_stats_page").text(current.dataset.boardPageNum);
      }
      if (current.dataset.boardPagePath) {
        $("#thread-return, #thread-return-top").attr("href", current.dataset.boardPagePath);
      }

      if (typeof window.sync_thread_seen === "function") {
        window.sync_thread_seen();
      }
      window.time_loaded = Date.now();

      return { ok: true, newItems: newReplies.length };
    }

    function updateDocumentTitle() {
      document.title = state.newItems
        ? "(" + state.newItems + ") " + state.originalTitle
        : state.originalTitle;
    }

    function viewportAtBottom() {
      var bottom = document.getElementById("bottom") || document.querySelector('a[name="bottom"]');
      var bottomY = null;

      if (bottom && bottom.getBoundingClientRect) {
        bottomY = bottom.getBoundingClientRect().top + window.scrollY;
      } else {
        var lastPost = document.querySelector("div.post:last-of-type");
        if (lastPost && lastPost.getBoundingClientRect) {
          var rect = lastPost.getBoundingClientRect();
          bottomY = rect.bottom + window.scrollY;
        }
      }

      return bottomY !== null && $(window).scrollTop() + $(window).height() >= bottomY;
    }

    function reconcileReadState() {
      if (pageKind !== "thread") {
        return;
      }

      if (state.newItems && state.windowActive && viewportAtBottom()) {
        state.newItems = 0;
        updateDocumentTitle();
      }
    }

    function handleThreadScroll() {
      state.scrollFramePending = false;
      reconcileReadState();

      if (
        viewportAtBottom() &&
        enabled() &&
        state.request === null &&
        Date.now() - state.lastRequestAt > minimumDelay
      ) {
        requestRefresh(true);
      }
    }

    function queueThreadScroll() {
      if (state.scrollFramePending) {
        return;
      }

      state.scrollFramePending = true;
      if (typeof window.requestAnimationFrame === "function") {
        window.requestAnimationFrame(handleThreadScroll);
      } else {
        window.setTimeout(handleThreadScroll, 16);
      }
    }

    $(window).on("focus.eirinchanLiveUpdater", function () {
      state.windowActive = true;

      if (pageKind !== "thread") {
        state.newItems = 0;
        updateDocumentTitle();
      } else {
        reconcileReadState();
      }

      if (settings.get("reset_focus", true) && enabled() && state.request === null) {
        schedule(minimumDelay);
      }
    });

    $(window).on("blur.eirinchanLiveUpdater", function () {
      state.windowActive = false;
    });

    if (pageKind === "thread") {
      $(window).on("scroll.eirinchanLiveUpdater", queueThreadScroll);
    }

    $(window).on("pagehide.eirinchanLiveUpdater", function () {
      state.suspended = true;
      cancelCountdown();
      if (state.request && typeof state.request.abort === "function") {
        state.request.eirinchanPagehideAbort = true;
        state.request.abort();
      }
    });

    $(window).on("pageshow.eirinchanLiveUpdater", function () {
      state.suspended = false;
      scheduleIfEnabled(minimumDelay);
    });

    $(statusInput).on("change.eirinchanLiveUpdater", function () {
      writeLivePageCookie(statusInput.checked);

      if (enabled()) {
        schedule(minimumDelay);
      } else {
        cancelCountdown();
        setStatus("");
      }

      syncButtonState();
    });

    $(toggleLink).on("click.eirinchanLiveUpdater", function (event) {
      event.preventDefault();
      statusInput.checked = !statusInput.checked;
      $(statusInput).trigger("change");
    });

    statusInput.checked = readLivePageCookie();
    syncButtonState();

    if (typeof window.add_title_collector === "function") {
      window.add_title_collector(function () {
        return state.newItems;
      });
    }

    if (enabled()) {
      schedule(minimumDelay);
    }
  });
})(window, document);
