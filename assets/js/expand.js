(function (window, document, $) {
  "use strict";
  if (!$ || typeof window.URL !== "function" || typeof window.DOMParser !== "function") return;

  // Expansion is a view owned by a board/thread identity, not by an AJAX
  // callback's captured element. The index owns its canonical preview; this
  // controller owns the complete reply snapshot and the user's expand intent.
  var states = new Map();
  var threadSelector = 'div[id^="thread_"]';

  function text(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function identity(thread) {
    if (!thread) return null;
    var match = (thread.id || "").match(/(\d+)$/);
    var id = thread.getAttribute("data-thread-id") || (match && match[1]);
    var link = thread.querySelector("p.intro a.post_no[href]");
    var href = thread.getAttribute("data-thread-url") || (link && link.getAttribute("href"));
    if (!id || !/^\d+$/.test(id) || !href) return null;
    try {
      var url = new window.URL(href, document.location.href);
      if (url.origin !== document.location.origin || !/^https?:$/.test(url.protocol)) return null;
      url.hash = "";
      var board = thread.getAttribute("data-board") || url.pathname.split("/").filter(Boolean)[0];
      if (!board) return null;
      return {key: board + "/" + id, board: board, id: id, url: url};
    } catch (_error) {
      return null;
    }
  }

  function threads(root) {
    var result = Array.from(root.querySelectorAll(threadSelector));
    if (root.matches && root.matches(threadSelector)) result.unshift(root);
    return result;
  }

  function currentThread(state) {
    return threads(document).find(function (thread) {
      var info = identity(thread);
      return info && info.key === state.info.key;
    }) || null;
  }

  function replyContainer(thread) {
    return thread.querySelector("#thread-refresh-target") || thread;
  }

  function replies(container) {
    return Array.from(container.children).filter(function (node) {
      return node.matches("div.post.reply[id]");
    });
  }

  function preview(thread) {
    return replies(replyContainer(thread)).map(function (node) { return node.cloneNode(true); });
  }

  function version(thread) {
    return thread.getAttribute("data-preview-version") || "";
  }

  function reusable(current, incoming) {
    var stamp = incoming.getAttribute("data-fragment-version");
    return current && stamp && stamp === current.getAttribute("data-fragment-version");
  }

  function mergePreview(full, incoming) {
    var byId = new Map(incoming.map(function (node) { return [node.id, node]; }));
    var known = new Set(full.map(function (node) { return node.id; }));
    var result = full.map(function (node) {
      var fresh = byId.get(node.id);
      return fresh && !reusable(node, fresh) ? fresh : node;
    });
    incoming.forEach(function (node) { if (!known.has(node.id)) result.push(node); });
    return result;
  }

  function renderReplies(thread, nodes, state) {
    var container = replyContainer(thread);
    var old = replies(container);
    var anchor = document.createComment("expanded thread replies");
    var tail = Array.from(container.children).reverse().find(function (node) {
      return node.matches("br.clear");
    });
    container.insertBefore(anchor, old[0] || tail || null);
    old.forEach(function (node) {
      var separator = node.nextElementSibling;
      node.remove();
      if (separator && separator.nodeType === 1 && separator.tagName === "BR") separator.remove();
    });
    var fragment = document.createDocumentFragment();
    var previewIds = new Set(state.preview.map(function (node) { return node.id; }));
    nodes.forEach(function (node) {
      node.classList.toggle("expanded", state.expanded && !previewIds.has(node.id));
      fragment.appendChild(node);
      var separator = document.createElement("br");
      separator.className = "clear";
      fragment.appendChild(separator);
    });
    anchor.replaceWith(fragment);
  }

  function control(thread, state) {
    thread.querySelectorAll("span.omitted:not(.hide-expanded)").forEach(function (span) {
      span.style.display = "none";
    });
    var span = thread.querySelector("[data-thread-expansion-control]");
    if (!span) {
      span = document.createElement("span");
      span.className = "omitted hide-expanded";
      span.setAttribute("data-thread-expansion-control", "");
      var omitted = thread.querySelector("span.omitted:not(.hide-expanded)");
      var op = thread.querySelector(".post.op");
      var anchor = omitted || (op && op.querySelector("div.body")) || op;
      if (anchor) anchor.insertAdjacentElement("afterend", span);
      else thread.appendChild(span);
    }
    span.replaceChildren();
    if (state.request) span.appendChild(document.createTextNode(text("Loading replies...") + " "));
    if (state.error) {
      span.appendChild(document.createTextNode(text("Could not load expanded replies.") + " "));
      span.appendChild(action("retry", "Retry"));
      span.appendChild(document.createTextNode(" "));
    }
    span.appendChild(action("collapse", "Hide expanded replies"));
    span.appendChild(document.createTextNode("."));
    thread.setAttribute("data-thread-expanded", "true");
  }

  function action(name, label) {
    var link = document.createElement("a");
    link.href = "#";
    link.dataset.threadExpansionAction = name;
    link.textContent = text(label);
    return link;
  }

  function initFragment(root) {
    if (window.EirinchanFrontend && typeof window.EirinchanFrontend.initFragment === "function") {
      window.EirinchanFrontend.initFragment(root, {reason: "thread-expansion"});
    } else {
      $(document).trigger("fragment_init", [root]);
    }
  }

  function intentChanged() {
    $(document).trigger("thread_expansion_changed");
  }

  function selectionActive() {
    return !!document.querySelector("input.delete:checked");
  }

  function valid(state, request) {
    return states.get(state.info.key) === state && state.expanded && state.request === request;
  }

  function fail(state, request) {
    if (!valid(state, request)) return;
    state.request = null;
    state.error = true;
    state.needsRefresh = false;
    var thread = currentThread(state);
    if (thread) control(thread, state);
  }

  function snapshot(markup, state) {
    var parsed = new window.DOMParser().parseFromString(markup, "text/html");
    var target = parsed.getElementById("thread-refresh-target");
    if (target) {
      var board = target.getAttribute("data-board");
      var id = target.getAttribute("data-thread-id");
      if ((board && board !== state.info.board) || (id && id !== state.info.id)) return null;
      return replies(target);
    }
    // Legacy/static thread documents still have an identifiable OP. Never treat
    // a login/error/unknown document as an authoritative empty reply snapshot.
    if (!parsed.getElementById("op_" + state.info.id)) return null;
    return Array.from(parsed.querySelectorAll("div.post.reply[id]"));
  }

  function load(state) {
    if (state.request || !state.expanded || !currentThread(state)) return;
    if (selectionActive()) { control(currentThread(state), state); return; }
    var url = new window.URL(state.info.url.href);
    url.searchParams.set("fragment", "1");
    var requestVersion = state.version;
    var request = $.ajax({
      url: url.href,
      dataType: "html",
      headers: state.etag ? {"If-None-Match": state.etag} : {},
      timeout: 15000
    });
    state.request = request;
    state.error = false;
    control(currentThread(state), state);
    request.done(function (markup, status, xhr) {
      if (!valid(state, request)) return;
      var thread = currentThread(state);
      if (!thread) { forget(state); return; }
      if (selectionActive()) {
        state.request = null;
        state.needsRefresh = true;
        control(thread, state);
        return;
      }
      if (requestVersion !== state.version) {
        state.request = null;
        load(state);
        return;
      }
      if ((xhr && xhr.status === 304) || status === "notmodified") {
        if (!state.loaded) { fail(state, request); return; }
      } else {
        var incoming = snapshot(markup || "", state);
        if (!incoming) { fail(state, request); return; }
        var current = new Map(replies(replyContainer(thread)).map(function (node) { return [node.id, node]; }));
        var changed = [];
        var added = [];
        var next = incoming.map(function (node) {
          if (reusable(current.get(node.id), node)) return current.get(node.id);
          changed.push(node);
          if (!current.has(node.id)) added.push(node);
          return node;
        });
        state.preview = state.previewCount > 0
          ? incoming.slice(-state.previewCount).map(function (node) { return node.cloneNode(true); }) : [];
        renderReplies(thread, next, state);
        state.loaded = true;
        state.etag = xhr && xhr.getResponseHeader ? xhr.getResponseHeader("ETag") : null;
      }
      state.request = null;
      state.needsRefresh = false;
      control(thread, state);
      initFragment(thread);
      (changed || []).forEach(function (post) {
        if (typeof window.syncBacklinksFromPost === "function") window.syncBacklinksFromPost(post);
      });
      (added || []).forEach(function (post) {
        if (window.EirinchanFrontend && typeof window.EirinchanFrontend.dispatchNewPost === "function") {
          window.EirinchanFrontend.dispatchNewPost(post);
        } else $(document).trigger("new_post", [post]);
      });
    }).fail(function (_xhr, status) {
      if (status !== "abort") fail(state, request);
    }).always(function () {
      if (state.request === request) state.request = null;
    });
  }

  function forget(state) {
    states.delete(state.info.key);
    var request = state.request;
    state.request = null;
    state.expanded = false;
    if (request && typeof request.abort === "function") request.abort();
  }

  function open(thread) {
    var info = identity(thread);
    if (!info) return;
    var state = states.get(info.key);
    if (state) {
      if (state.error) load(state);
      return;
    }
    state = {info: info, expanded: true, loaded: false, request: null, error: false,
      etag: null, preview: preview(thread), previewCount: replies(replyContainer(thread)).length,
      version: version(thread), needsRefresh: true};
    states.set(info.key, state);
    intentChanged();
    load(state);
  }

  function collapse(thread) {
    var info = identity(thread);
    var state = info && states.get(info.key);
    if (!state) return;
    forget(state);
    var current = new Map(replies(replyContainer(thread)).map(function (node) { return [node.id, node]; }));
    renderReplies(thread, state.preview.map(function (node) {
      return reusable(current.get(node.id), node) ? current.get(node.id) : node;
    }), state);
    thread.removeAttribute("data-thread-expanded");
    thread.querySelectorAll("[data-thread-expansion-control]").forEach(function (span) { span.remove(); });
    thread.querySelectorAll("span.omitted:not(.hide-expanded)").forEach(function (span) { span.style.display = ""; });
    intentChanged();
    initFragment(thread);
  }

  function init(root) {
    root = root && root.jquery ? root[0] : root || document;
    if (!root || !root.querySelectorAll) return;
    var spans = Array.from(root.querySelectorAll("span.omitted:not(.hide-expanded)"));
    if (root.matches && root.matches("span.omitted:not(.hide-expanded)")) spans.unshift(root);
    spans.forEach(function (span) {
      if (!span.closest(threadSelector) || span.querySelector("a")) return;
      var label = text("Click reply to view.");
      var original = span.textContent;
      var position = original.indexOf(label);
      if (position < 0) return;
      span.replaceChildren(document.createTextNode(original.slice(0, position)),
        action("expand", "Click to expand"), document.createTextNode("." + original.slice(position + label.length)));
    });
  }

  function prepareReplacement(current, replacement) {
    var incoming = new Map(threads(replacement).map(function (thread) {
      var info = identity(thread);
      return [info && info.key, thread];
    }));
    threads(current).forEach(function (thread) {
      var info = identity(thread);
      var state = info && states.get(info.key);
      if (!state) return;
      var next = incoming.get(info.key);
      if (!next) { forget(state); return; }
      var stamp = version(next);
      state.needsRefresh = state.needsRefresh || !stamp || stamp !== state.version;
      state.preview = preview(next);
      state.previewCount = state.preview.length;
      state.version = stamp;
      state.info = identity(next);
      var expanded = replies(replyContainer(thread));
      renderReplies(next, mergePreview(expanded, replies(replyContainer(next))), state);
      control(next, state);
    });
  }

  function afterReplacement(root) {
    threads(root).forEach(function (thread) {
      var info = identity(thread);
      var state = info && states.get(info.key);
      if (state && state.needsRefresh) load(state);
    });
  }

  window.EirinchanThreadExpansion = {
    init: init,
    prepareReplacement: prepareReplacement,
    afterReplacement: afterReplacement,
    isLoading: function () { return Array.from(states.values()).some(function (state) { return !!state.request; }); }
  };
  window.EirinchanInitExpand = function (root) { init(root && root.jquery ? root[0] : root); };
  window.expand_fun = function (event) { event.preventDefault(); open(this.closest(threadSelector)); };

  $(document).on("click.eirinchanThreadExpansion", "[data-thread-expansion-action]", function (event) {
    event.preventDefault();
    var thread = this.closest(threadSelector);
    if (!thread) return;
    if (this.dataset.threadExpansionAction === "collapse") collapse(thread);
    else open(thread);
  });
  $(document).on("fragment_init.eirinchanThreadExpansion new_post.eirinchanThreadExpansion", function (_event, root) { init(root || document); });
  $(document).on("change.eirinchanThreadExpansion", "input.delete", function () {
    states.forEach(function (state) {
      if (selectionActive()) {
        var request = state.request;
        state.request = null;
        if (request) {
          state.needsRefresh = true;
          if (typeof request.abort === "function") request.abort();
          var thread = currentThread(state);
          if (thread) control(thread, state);
        }
      } else if (state.needsRefresh) load(state);
    });
  });
  $(window).on("pagehide.eirinchanThreadExpansion", function () {
    states.forEach(function (state) {
      var request = state.request;
      state.request = null;
      state.needsRefresh = true;
      if (request) {
        if (typeof request.abort === "function") request.abort();
      }
    });
  });
  $(window).on("pageshow.eirinchanThreadExpansion", function () {
    states.forEach(function (state) {
      if (!currentThread(state)) forget(state);
      else if (state.needsRefresh) load(state);
    });
  });
  $(function () { init(document); });
})(window, document, window.jQuery);
