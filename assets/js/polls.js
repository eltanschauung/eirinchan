(function () {
  "use strict";
  if (window.EirinchanPolls) return;

  var states = new Map(), choices = new Map(), busy = new Set(), pending = new Set();
  var initialized = new WeakSet(), serial = 0, scheduled = false, csrfRefresh = null;
  var loadingIds = new Set(), loadingBatches = 0;
  var selector = ".post-poll[data-poll-post-id]";

  function idOf(widget) {
    var id = widget.getAttribute("data-poll-post-id");
    return /^[1-9]\d{0,18}$/.test(id || "") ? id : null;
  }
  function widgets(id) {
    return document.querySelectorAll('.post-poll[data-poll-post-id="' + id + '"]');
  }
  function status(id, message) {
    widgets(id).forEach(function (widget) { var node = widget.querySelector(".poll-status"); if (node) node.textContent = message; });
  }
  function trimCache(map) {
    while (map.size > 500) map.delete(map.keys().next().value);
  }
  function validState(data) {
    return data && (data.voted === false || (data.voted === true &&
      Number.isSafeInteger(data.total) && data.total >= 1 && Array.isArray(data.results) &&
      data.results.length >= 2 && data.results.length <= 6 &&
      data.results.every(function (r) { return typeof r.label === "string" && Number.isSafeInteger(r.count) && r.count >= 0; }) &&
      data.results.reduce(function (n, r) { return n + r.count; }, 0) === data.total));
  }
  function remember(id, data) {
    if (!validState(data)) throw new Error("Invalid poll response. Please retry.");
    var previous = states.get(id);
    // Late initial/status requests must not put a completed vote back into
    // voting mode or replace newer totals with an older snapshot.
    if (previous && previous.data.voted && (!data.voted || previous.data.total > data.total)) return;
    states.delete(id); states.set(id, {data: data, at: Date.now()}); trimCache(states);
    widgets(id).forEach(render);
  }
  function render(widget) {
    var id = idOf(widget), cached = states.get(id), data = cached && cached.data;
    var options = widget.querySelector(".poll-options"), results = widget.querySelector(".poll-results");
    var button = widget.querySelector(".poll-vote");
    if (!options || !results || !button) return;
    options.hidden = Boolean(data && data.voted);
    results.hidden = !options.hidden;
    widget.querySelectorAll('input[type="radio"]').forEach(function (input) {
      input.disabled = busy.has(id);
      input.checked = input.value === choices.get(id);
    });
    button.disabled = busy.has(id);
    if (!data || !data.voted) return;

    var list = document.createElement("ol");
    data.results.forEach(function (result) {
      var row = document.createElement("li"), text = document.createElement("span"), bar = document.createElement("progress");
      text.textContent = result.label + " — " + result.count + " (" + (100 * result.count / data.total).toFixed(1) + "%)";
      bar.max = data.total; bar.value = result.count; bar.setAttribute("aria-label", result.label);
      row.append(text, bar); list.append(row);
    });
    var total = document.createElement("div"), refresh = document.createElement("button");
    total.textContent = "Total votes: " + data.total;
    refresh.type = "button"; refresh.className = "poll-refresh"; refresh.textContent = "Refresh results";
    results.replaceChildren(list, total, refresh);
  }
  async function jsonRequest(url, options) {
    var controller = new AbortController(), timeout = window.setTimeout(function () { controller.abort(); }, 10000);
    try {
      var response = await window.fetch(url, Object.assign({credentials: "same-origin", cache: "no-store", signal: controller.signal}, options));
      var payload;
      try { payload = await response.json(); } catch (_) { throw new Error("Unable to contact the poll. Please retry."); }
      if (!response.ok) {
        var error = new Error(typeof payload.error === "string" ? payload.error : "Poll request failed. Please retry.");
        error.csrf = payload.csrf === true; throw error;
      }
      return payload;
    } finally { window.clearTimeout(timeout); }
  }
  function csrfToken() {
    if (!csrfRefresh) {
      csrfRefresh = jsonRequest("/csrf-token", {headers: {Accept: "*/*"}}).then(function (payload) {
        if (typeof payload.csrf_token !== "string" || !payload.csrf_token) throw new Error("Please refresh the page before voting.");
        var meta = document.querySelector('meta[name="csrf-token"]');
        if (meta) meta.setAttribute("content", payload.csrf_token);
        document.querySelectorAll('input[name="_csrf_token"]').forEach(function (input) { input.value = payload.csrf_token; });
        return payload.csrf_token;
      }).finally(function () { csrfRefresh = null; });
    }
    return csrfRefresh;
  }
  async function submit(id, choice) {
    if (busy.has(id)) return;
    busy.add(id); widgets(id).forEach(render); status(id, "Submitting vote…");
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          var token = await csrfToken();
          var payload = await jsonRequest("/api/polls/" + id + "/vote", {
            method: "POST", headers: {Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": token},
            body: JSON.stringify({choice: choice})
          });
          remember(id, payload.data); status(id, ""); break;
        } catch (error) {
          if (!error.csrf || attempt > 0) throw error;
        }
      }
    } catch (error) { status(id, error.name === "AbortError" ? "Request timed out. Retry to check your vote safely." : error.message); }
    finally { busy.delete(id); widgets(id).forEach(render); }
  }
  async function load(ids) {
    try {
      var payload = await jsonRequest("/api/polls/state?ids=" + ids.join(","), {headers: {Accept: "application/json"}});
      ids.forEach(function (id) {
        if (payload.data && payload.data[id]) { remember(id, payload.data[id]); if (!busy.has(id)) status(id, ""); }
        else status(id, "This poll is no longer available.");
      });
    } catch (_) {
      ids.forEach(function (id) {
        if (!busy.has(id) && !(states.get(id) && states.get(id).data.voted)) status(id, "Could not load your vote. You can retry voting safely.");
      });
    }
  }
  function queue(id) {
    if (loadingIds.has(id)) return;
    pending.add(id);
    if (scheduled) return;
    scheduled = true;
    window.setTimeout(function () {
      scheduled = false;
      drain();
    }, 0);
  }
  function drain() {
    // A long thread should not occupy the server's whole database pool with
    // parallel status requests. New/replaced copies join the same receipt read.
    while (loadingBatches < 2 && pending.size) {
      var ids = Array.from(pending).slice(0, 50);
      ids.forEach(function (id) { pending.delete(id); loadingIds.add(id); });
      loadingBatches++;
      (function (batch) {
        load(batch).finally(function () {
          batch.forEach(function (id) { loadingIds.delete(id); });
          loadingBatches--; drain();
        });
      }(ids));
    }
  }
  function hydrate(widget) {
    var id = idOf(widget);
    if (!id || !widget.querySelector(".poll-options") || !widget.querySelector(".poll-status") || !widget.querySelector(".poll-results") || !widget.querySelector(".poll-vote")) return;
    if (!initialized.has(widget)) {
      initialized.add(widget); serial++;
      widget.querySelectorAll('input[type="radio"]').forEach(function (input) { input.name = "poll-" + id + "-" + serial; });
    }
    render(widget);
    var cached = states.get(id);
    if (!cached || Date.now() - cached.at > 30000) queue(id);
  }
  function scan(root) {
    if (root.matches && root.matches(selector)) hydrate(root);
    if (root.querySelectorAll) root.querySelectorAll(selector).forEach(hydrate);
  }
  function start() {
    if (!document.body || window.EirinchanPolls.started) return;
    window.EirinchanPolls.started = true; scan(document);
    new MutationObserver(function (records) {
      records.forEach(function (record) { record.addedNodes.forEach(function (node) { if (node.nodeType === 1) scan(node); }); });
    }).observe(document.body, {childList: true, subtree: true});
    document.addEventListener("change", function (event) {
      if (!event.target.matches('.post-poll input[type="radio"]')) return;
      var id = idOf(event.target.closest(selector));
      if (id && /^[0-5]$/.test(event.target.value)) { choices.set(id, event.target.value); trimCache(choices); widgets(id).forEach(render); }
    });
    document.addEventListener("click", function (event) {
      var button = event.target.closest && event.target.closest(".poll-vote, .poll-refresh");
      if (!button) return;
      var widget = button.closest(selector), id = widget && idOf(widget);
      if (!id) return;
      event.preventDefault(); event.stopPropagation();
      if (button.classList.contains("poll-refresh")) { status(id, "Loading results…"); queue(id); return; }
      var selected = widget.querySelector('input[type="radio"]:checked');
      if (!selected) { status(id, "Choose an option first."); return; }
      if (/^[0-5]$/.test(selected.value)) submit(id, Number(selected.value));
    });
    window.addEventListener("focus", function () { scan(document); });
    window.addEventListener("pageshow", function (event) { if (event.persisted) scan(document); });
  }
  window.EirinchanPolls = {started: false};
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, {once: true});
  else start();
}());
