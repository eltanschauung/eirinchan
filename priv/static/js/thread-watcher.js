(function () {
  "use strict";

  var state = {
    watcherTab: null,
    watcherContent: null,
    fragmentRequest: null,
    fragmentRefreshQueued: false,
    pending: Object.create(null),
    optionsHookInstalled: false
  };

  function translate(message) {
    return typeof window._ === "function" ? window._(message) : message;
  }

  function integer(value, fallback) {
    var parsed = parseInt(value, 10);
    return isNaN(parsed) ? fallback : parsed;
  }

  function dispatch(name, detail) {
    var event;

    if (typeof window.CustomEvent === "function") {
      event = new CustomEvent(name, { detail: detail });
    } else {
      event = document.createEvent("CustomEvent");
      event.initCustomEvent(name, false, false, detail);
    }

    document.dispatchEvent(event);

    if (window.jQuery) {
      window.jQuery(document).trigger(name, [detail]);
    }
  }

  function csrfToken(trigger) {
    var form = trigger && trigger.closest ? trigger.closest("form") : null;
    var field =
      (form && form.querySelector('input[name="_csrf_token"]')) ||
      document.querySelector('meta[name="csrf-token"]') ||
      document.querySelector('input[name="_csrf_token"]');

    if (!field) {
      return null;
    }

    return field.content || field.value || null;
  }

  function metricsFrom(source) {
    source = source || {};

    return {
      watcher_count: integer(source.watcher_count, 0),
      watcher_unread_count: integer(source.watcher_unread_count, 0),
      watcher_you_count: integer(source.watcher_you_count, 0)
    };
  }

  function metricsFromResponse(response) {
    return metricsFrom({
      watcher_count: response.headers.get("x-watcher-count"),
      watcher_unread_count: response.headers.get("x-watcher-unread-count"),
      watcher_you_count: response.headers.get("x-watcher-you-count")
    });
  }

  function currentMetrics() {
    var dataset = document.body && document.body.dataset ? document.body.dataset : {};

    return metricsFrom({
      watcher_count: dataset.watcherCount || window.watcher_count,
      watcher_unread_count: dataset.watcherUnreadCount || window.watcher_unread_count,
      watcher_you_count: dataset.watcherYouCount || window.watcher_you_count
    });
  }

  function updateMetrics(source) {
    var metrics = metricsFrom(source);
    var body = document.body;
    var link = document.getElementById("watcher-link");

    window.watcher_count = metrics.watcher_count;
    window.watcher_unread_count = metrics.watcher_unread_count;
    window.watcher_you_count = metrics.watcher_you_count;

    if (body && body.dataset) {
      body.dataset.watcherCount = String(metrics.watcher_count);
      body.dataset.watcherUnreadCount = String(metrics.watcher_unread_count);
      body.dataset.watcherYouCount = String(metrics.watcher_you_count);
    }

    if (link) {
      var label =
        translate("Watcher") +
        (metrics.watcher_count > 0 ? " (" + metrics.watcher_count + ")" : "");

      link.title = label;
      link.setAttribute("aria-label", label);
      link.dataset.count = String(metrics.watcher_count);
      link.dataset.unreadCount = String(metrics.watcher_unread_count);
      link.classList.toggle("has-unread", metrics.watcher_unread_count > 0);
      link.classList.toggle("replies-quoting-you", metrics.watcher_you_count > 0);
    }

    dispatch("watcher:metrics", metrics);
    return metrics;
  }

  function elementBoardUri(element) {
    if (!element) {
      return window.board_name || "";
    }

    if (element.dataset && element.dataset.board) {
      return element.dataset.board;
    }

    var container = element.closest ? element.closest("[data-board]") : null;
    if (container && container.dataset) {
      return container.dataset.board || "";
    }

    return window.board_name || "";
  }

  function elementThreadId(element) {
    if (!element) {
      return "";
    }

    if (element.dataset && element.dataset.threadId) {
      return String(element.dataset.threadId);
    }

    var container = element.closest ? element.closest("[data-thread-id]") : null;
    if (container && container.dataset) {
      return String(container.dataset.threadId || "");
    }

    return "";
  }

  function sameThread(element, boardUri, threadId) {
    return (
      elementBoardUri(element) === String(boardUri || "") &&
      elementThreadId(element) === String(threadId || "")
    );
  }

  function eachThreadControl(boardUri, threadId, callback) {
    Array.prototype.forEach.call(document.querySelectorAll("[data-thread-watch]"), function (control) {
      if (sameThread(control, boardUri, threadId)) {
        callback(control);
      }
    });
  }

  function eachThreadContainer(boardUri, threadId, callback) {
    Array.prototype.forEach.call(
      document.querySelectorAll(".thread[data-thread-id]"),
      function (thread) {
        if (sameThread(thread, boardUri, threadId)) {
          callback(thread);
        }
      }
    );
  }

  function setControlWatched(control, watched) {
    control.dataset.watched = watched ? "true" : "false";

    if (control.classList.contains("watch-thread-link")) {
      control.classList.toggle("watched", watched);
      control.title = (watched ? translate("Unwatch") : translate("Watch")) + " Thread";
    } else {
      control.textContent = watched ? "[" + translate("Unwatch") + "]" : "[" + translate("Watch") + "]";
    }
  }

  function syncThread(boardUri, threadId, watched) {
    eachThreadControl(boardUri, threadId, function (control) {
      setControlWatched(control, watched);
    });

    eachThreadContainer(boardUri, threadId, function (thread) {
      thread.dataset.watched = watched ? "true" : "false";
    });

    dispatch("watcher:changed", {
      board: boardUri,
      thread_id: integer(threadId, threadId),
      watched: !!watched
    });
  }

  function pendingKey(boardUri, threadId) {
    return encodeURIComponent(boardUri) + ":" + encodeURIComponent(threadId);
  }

  function setPending(boardUri, threadId, pending) {
    var key = pendingKey(boardUri, threadId);

    if (pending) {
      state.pending[key] = true;
    } else {
      delete state.pending[key];
    }

    eachThreadControl(boardUri, threadId, function (control) {
      if (pending) {
        control.dataset.pending = "true";
        control.setAttribute("aria-busy", "true");
      } else {
        delete control.dataset.pending;
        control.removeAttribute("aria-busy");
      }
    });
  }

  function isPending(boardUri, threadId) {
    return !!state.pending[pendingKey(boardUri, threadId)];
  }

  function watcherUrl(boardUri, threadId) {
    return "/watcher/" + encodeURIComponent(boardUri) + "/" + encodeURIComponent(threadId);
  }

  function jsonRequest(url, options) {
    var requestOptions = options || {};
    requestOptions.credentials = "same-origin";
    requestOptions.headers = requestOptions.headers || {};
    requestOptions.headers.Accept = "application/json";
    requestOptions.headers["X-Requested-With"] = "XMLHttpRequest";

    return fetch(url, requestOptions).then(function (response) {
      if (!response.ok) {
        var error = new Error("watcher request failed");
        error.status = response.status;
        throw error;
      }

      return response.text().then(function (text) {
        if (!text) {
          return {};
        }

        try {
          return JSON.parse(text);
        } catch (_error) {
          var parseError = new Error("invalid watcher response");
          parseError.status = response.status;
          throw parseError;
        }
      });
    });
  }

  function ensureWatcherTab() {
    if (!(window.Options && Options.get_tab && Options.add_tab)) {
      return null;
    }

    var tab = Options.get_tab("watcher") || Options.add_tab("watcher", "eye", translate("Watcher"));
    var content = document.getElementById("watcher-tab-content");

    if (!content) {
      content = document.createElement("div");
      content.id = "watcher-tab-content";
      content.innerHTML = '<div class="watcher-loading">' + translate("Loading...") + "</div>";

      if (tab.content && tab.content.append) {
        tab.content.append(content);
      } else if (tab.content && tab.content[0]) {
        tab.content[0].appendChild(content);
      }
    }

    state.watcherTab = tab;
    state.watcherContent = content;

    var webmTab = Options.get_tab("webm");
    if (webmTab && webmTab.icon && tab.icon && tab.icon.insertAfter) {
      tab.icon.insertAfter(webmTab.icon);
    }

    installOptionsHook();
    return tab;
  }

  function watcherTabActive() {
    var tab = state.watcherTab || ensureWatcherTab();

    if (!tab || !tab.icon) {
      return false;
    }

    if (typeof tab.icon.hasClass === "function") {
      return tab.icon.hasClass("active");
    }

    var icon = tab.icon[0] || tab.icon;
    return !!(icon && icon.classList && icon.classList.contains("active"));
  }

  function initFragment(root) {
    if (
      root &&
      window.EirinchanFrontend &&
      typeof window.EirinchanFrontend.initFragment === "function"
    ) {
      window.EirinchanFrontend.initFragment(root, { reason: "watcher-refresh" });
    }
  }

  function finishFragmentRequest(request) {
    if (state.fragmentRequest === request) {
      state.fragmentRequest = null;
    }

    if (state.fragmentRefreshQueued) {
      state.fragmentRefreshQueued = false;
      refreshWatcherTab().catch(function () {});
    }
  }

  function refreshWatcherTab(options) {
    var settings = options || {};
    ensureWatcherTab();

    if (!state.watcherContent) {
      return Promise.resolve(null);
    }

    if (state.fragmentRequest) {
      if (settings.queue !== false) {
        state.fragmentRefreshQueued = true;
      }

      return state.fragmentRequest;
    }

    var request = fetch("/watcher/fragment", {
      cache: "no-store",
      credentials: "same-origin",
      headers: {
        Accept: "text/html",
        "Cache-Control": "no-cache",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(function (response) {
        if (!response.ok) {
          var error = new Error("watcher fragment failed");
          error.status = response.status;
          throw error;
        }

        updateMetrics(metricsFromResponse(response));
        return response.text();
      })
      .then(function (html) {
        state.watcherContent.innerHTML = html;
        initFragment(state.watcherContent);
        return html;
      })
      .catch(function (error) {
        if (!settings.silent) {
          state.watcherContent.innerHTML =
            '<div class="post reply watcher-entry"><p class="body">' +
            translate("Watcher refresh failed.") +
            "</p></div>";
        }

        throw error;
      });

    state.fragmentRequest = request;

    request.then(
      function () {
        finishFragmentRequest(request);
      },
      function () {
        finishFragmentRequest(request);
      }
    );

    return request;
  }

  function installOptionsHook() {
    if (
      state.optionsHookInstalled ||
      !(window.Options && typeof Options.select_tab === "function")
    ) {
      return;
    }

    state.optionsHookInstalled = true;
    var originalSelectTab = Options.select_tab;

    Options.select_tab = function (name) {
      var result = originalSelectTab.apply(this, arguments);

      if (name === "watcher") {
        refreshWatcherTab({ queue: true }).catch(function () {});
      }

      return result;
    };
  }

  function openWatcher() {
    var tab = ensureWatcherTab();

    if (!(tab && window.Options && Options.show && Options.select_tab)) {
      window.location.assign("/watcher");
      return;
    }

    Options.show();
    Options.select_tab("watcher");
  }

  function updateMetricsFromPayload(payload) {
    if (payload && typeof payload.watcher_count !== "undefined") {
      updateMetrics(payload);
    }
  }

  function refreshActiveWatcherTab() {
    if (watcherTabActive()) {
      refreshWatcherTab({ queue: true }).catch(function () {});
    }
  }

  function toggleWatch(control) {
    var boardUri = elementBoardUri(control);
    var threadId = elementThreadId(control);

    if (!boardUri || !threadId || isPending(boardUri, threadId)) {
      return Promise.resolve(null);
    }

    var watched = control.dataset.watched === "true";
    var token = csrfToken(control);

    if (!token) {
      return Promise.reject(new Error("missing CSRF token"));
    }

    setPending(boardUri, threadId, true);

    return jsonRequest(watcherUrl(boardUri, threadId), {
      method: watched ? "DELETE" : "POST",
      headers: {
        "X-CSRF-Token": token
      }
    })
      .then(function (payload) {
        var responseBoard = payload.board || boardUri;
        var responseThread = payload.thread_id || threadId;

        syncThread(responseBoard, responseThread, !!payload.watched);
        updateMetricsFromPayload(payload);
        refreshActiveWatcherTab();
        return payload;
      })
      .catch(function (error) {
        if (error.status === 404) {
          syncThread(boardUri, threadId, false);
          refreshActiveWatcherTab();
          return null;
        }

        if (typeof window.alert === "function") {
          window.alert(translate("Watcher update failed."));
        }

        throw error;
      })
      .then(
        function (result) {
          setPending(boardUri, threadId, false);
          return result;
        },
        function (error) {
          setPending(boardUri, threadId, false);
          throw error;
        }
      );
  }

  function markSeen(boardUri, threadId, lastSeenPostId) {
    var token = csrfToken(document.body);

    if (!boardUri || !threadId || !lastSeenPostId || !token) {
      return Promise.resolve(null);
    }

    return jsonRequest(watcherUrl(boardUri, threadId), {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token
      },
      body: JSON.stringify({ last_seen_post_id: lastSeenPostId })
    })
      .then(function (payload) {
        updateMetricsFromPayload(payload);
        refreshActiveWatcherTab();
        return payload;
      })
      .catch(function (error) {
        if (error.status === 404) {
          return null;
        }

        if (window.console && console.error) {
          console.error(error);
        }

        return null;
      });
  }

  function latestVisiblePostId(thread) {
    var latest = integer(thread && thread.dataset ? thread.dataset.threadId : 0, 0);

    if (!thread) {
      return latest;
    }

    Array.prototype.forEach.call(thread.querySelectorAll(".post[id]"), function (post) {
      var match = String(post.id || "").match(/(\d+)$/);
      if (match) {
        latest = Math.max(latest, integer(match[1], 0));
      }
    });

    return latest;
  }

  function syncCurrentThreadSeen() {
    var refreshTarget = document.getElementById("thread-refresh-target");
    var thread = refreshTarget && refreshTarget.closest ? refreshTarget.closest(".thread[data-thread-id]") : null;

    if (!thread || !thread.dataset || thread.dataset.watched !== "true") {
      return Promise.resolve(null);
    }

    return markSeen(
      elementBoardUri(thread),
      elementThreadId(thread),
      latestVisiblePostId(thread)
    );
  }

  function clearAllWatches(trigger) {
    var token = csrfToken(trigger);

    if (!token || (trigger && trigger.dataset.pending === "true")) {
      return Promise.resolve(null);
    }

    if (trigger) {
      trigger.dataset.pending = "true";
      trigger.setAttribute("aria-busy", "true");
    }

    return jsonRequest("/watcher", {
      method: "DELETE",
      headers: {
        "X-CSRF-Token": token
      }
    })
      .then(function (payload) {
        Array.prototype.forEach.call(document.querySelectorAll("[data-thread-watch]"), function (control) {
          setControlWatched(control, false);
        });

        Array.prototype.forEach.call(document.querySelectorAll(".thread[data-thread-id]"), function (thread) {
          thread.dataset.watched = "false";
        });

        updateMetricsFromPayload(payload);
        refreshWatcherTab({ queue: true }).catch(function () {});
        dispatch("watcher:cleared", payload);
        return payload;
      })
      .catch(function (error) {
        if (typeof window.alert === "function") {
          window.alert(translate("Watcher update failed."));
        }

        throw error;
      })
      .then(
        function (result) {
          if (trigger) {
            delete trigger.dataset.pending;
            trigger.removeAttribute("aria-busy");
          }

          return result;
        },
        function (error) {
          if (trigger) {
            delete trigger.dataset.pending;
            trigger.removeAttribute("aria-busy");
          }

          throw error;
        }
      );
  }

  function installMenuIntegration() {
    if (!window.jQuery) {
      return;
    }

    window.jQuery(document)
      .off("menu_ready.eirinchanWatcher")
      .on("menu_ready.eirinchanWatcher", function () {
        var Menu = window.Menu;

        if (!Menu || Menu.__watchThreadMenuInstalled) {
          return;
        }

        Menu.__watchThreadMenuInstalled = true;
        Menu.add_item("watch_thread_menu", translate("Watch"));
        Menu.onclick(function (event, buffer) {
          var post = event.target.closest && event.target.closest(".post");
          var thread = post && post.closest && post.closest(".thread[data-thread-id]");
          var item = buffer.find("#watch_thread_menu");

          if (!thread) {
            item.addClass("hidden");
            return;
          }

          var control = thread.querySelector("[data-thread-watch]");
          var watched = control
            ? control.dataset.watched === "true"
            : thread.dataset.watched === "true";

          item
            .removeClass("hidden")
            .text(watched ? translate("Unwatch") : translate("Watch"))
            .off("click.eirinchanWatcher")
            .on("click.eirinchanWatcher", function (clickEvent) {
              clickEvent.preventDefault();

              if (control) {
                toggleWatch(control).catch(function () {});
              }
            });
        });
      });
  }

  function unmodifiedPrimaryClick(event) {
    return (
      (typeof event.button === "undefined" || event.button === 0) &&
      !event.metaKey &&
      !event.ctrlKey &&
      !event.shiftKey &&
      !event.altKey
    );
  }

  function installClickHandlers() {
    document.addEventListener("click", function (event) {
      var watcherLink = event.target.closest && event.target.closest("#watcher-link");

      if (watcherLink && unmodifiedPrimaryClick(event)) {
        event.preventDefault();
        openWatcher();
        return;
      }

      var clearLink = event.target.closest && event.target.closest("#watcher-unwatch-all");
      if (clearLink) {
        event.preventDefault();
        clearAllWatches(clearLink).catch(function () {});
        return;
      }

      var control = event.target.closest && event.target.closest("[data-thread-watch]");
      if (!control) {
        return;
      }

      event.preventDefault();
      toggleWatch(control).catch(function () {});
    });
  }

  function initialize() {
    updateMetrics(currentMetrics());
    ensureWatcherTab();
    installMenuIntegration();
    installClickHandlers();
  }

  window.markWatchedThreadSeen = markSeen;
  window.sync_thread_seen = syncCurrentThreadSeen;
  window.EirinchanWatcher = {
    clear: clearAllWatches,
    markSeen: markSeen,
    metrics: currentMetrics,
    open: openWatcher,
    refresh: refreshWatcherTab,
    syncThread: syncThread,
    updateMetrics: updateMetrics
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, { once: true });
  } else {
    initialize();
  }
})();
