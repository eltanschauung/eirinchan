import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquery = await readFile(path.join(root, "priv/static/js/jquery.min.js"), "utf8");
const expansion = await readFile(path.join(root, "assets/js/expand.js"), "utf8");
const updater = await readFile(path.join(root, "assets/js/auto-reload.js"), "utf8");
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function eventually(fn) {
  for (let i = 0; i < 200; i++) {
    if (fn()) return;
    await delay(5);
  }
  assert.ok(fn(), "expected condition did not settle");
}
function reply(id, version = "v" + id, body = "Synthetic reply") {
  return `<div class="post reply" id="reply_${id}" data-fragment-version="${version}">${body}</div>\n<br class="clear">`;
}
function thread({board = "test", id = 100, version = "preview-v1", previews = [103]} = {}) {
  return `<div class="thread" id="thread_${id}" data-board="${board}" data-thread-id="${id}"
    data-thread-url="/${board}/res/${id}.html" data-preview-version="${version}">
    <div class="post op" id="op_${id}"><p class="intro"><a class="post_no" href="/${board}/res/${id}+50.html#${id}">${id}</a></p>
      <div class="body">Synthetic OP</div></div><span class="omitted">2 posts omitted. Click reply to view.</span>
    ${previews.map(value => Array.isArray(value) ? reply(...value) : reply(value)).join("")}<br class="clear"></div>`;
}
function board(content = thread(), hash = "board-v1") {
  return `<div id="board-refresh-target" data-fragment-md5="${hash}"><div id="board-threads">${content}</div></div>`;
}
function snapshot(ids = [101, 102, 103], {board = "test", id = 100} = {}) {
  return `<div id="thread-refresh-target" data-board="${board}" data-thread-id="${id}">${ids.map(value => Array.isArray(value) ? reply(...value) : reply(value)).join("")}</div>`;
}
async function setup(t, {withUpdater = false, content = thread(), configure} = {}) {
  const dom = new JSDOM(`<!doctype html><html><head><title>Test</title></head><body>
    <div data-live-updater data-page-kind="index" data-poll-interval-seconds="0.01">
      <input id="auto_update_status" type="checkbox"><span id="update_secs"></span><a href="#" id="update_thread">Live</a>
    </div>${board(content)}</body></html>`, {runScripts: "outside-only", url: "https://example.test/test/"});
  t.after(() => dom.window.close());
  const w = dom.window;
  w.eval(jquery);
  w._ = value => value;
  const requests = [];
  w.jQuery.ajax = options => {
    const done = [], fail = [], always = [];
    const request = {options, aborted: false,
      done(fn) { done.push(fn); return request; },
      fail(fn) { fail.push(fn); return request; },
      always(fn) { always.push(fn); return request; },
      abort() { request.aborted = true; fail.forEach(fn => fn({}, "abort")); always.forEach(fn => fn()); },
      reject(status = "error") { fail.forEach(fn => fn({}, status)); always.forEach(fn => fn()); },
      resolve(html, {status = 200, etag = '"replies-v1"'} = {}) {
        const xhr = {status, getResponseHeader(name) { return name === "ETag" ? etag : null; }};
        done.forEach(fn => fn(html, status === 304 ? "notmodified" : "success", xhr));
        always.forEach(fn => fn());
      }};
    requests.push(request);
    return request;
  };
  const initialized = [], newPosts = [];
  w.EirinchanFrontend = {
    initFragment(node) { initialized.push(node); w.jQuery(w.document).trigger("fragment_init", [node]); },
    dispatchNewPost(node) { newPosts.push(node.id); w.jQuery(w.document).trigger("new_post", [node]); }
  };
  if (configure) configure(w);
  w.eval(expansion);
  if (withUpdater) w.eval(updater);
  await eventually(() => !!w.document.querySelector('[data-thread-expansion-action="expand"]'));
  const getThread = (boardName = "test", id = 100) => Array.from(w.document.querySelectorAll(".thread")).find(node => node.dataset.board === boardName && node.dataset.threadId === String(id));
  const click = (action, boardName, id) => {
    const link = getThread(boardName, id).querySelector(`[data-thread-expansion-action="${action}"]`);
    assert.ok(link, `missing ${action} control`);
    w.jQuery(link).trigger("click");
  };
  const loads = () => requests.filter(request => new w.URL(request.options.url).pathname.includes("/res/"));
  const polls = () => requests.filter(request => !new w.URL(request.options.url).pathname.includes("/res/"));
  const apply = (markup) => {
    const doc = new w.DOMParser().parseFromString(markup, "text/html");
    const incoming = doc.getElementById("board-refresh-target");
    const current = w.document.getElementById("board-refresh-target");
    w.EirinchanThreadExpansion.prepareReplacement(current, incoming);
    current.replaceWith(incoming);
    w.EirinchanThreadExpansion.afterReplacement(incoming);
    w.EirinchanFrontend.initFragment(incoming);
  };
  return {dom, w, requests, initialized, newPosts, getThread, click, loads, polls, apply};
}

test("expansion fetches the full canonical thread and initializes only new replies", async t => {
  const h = await setup(t);
  const old = h.w.document.getElementById("reply_103");
  h.click("expand");
  assert.equal(h.loads().length, 1);
  assert.equal(new h.w.URL(h.loads()[0].options.url).pathname, "/test/res/100.html");
  assert.equal(new h.w.URL(h.loads()[0].options.url).searchParams.get("fragment"), "1");
  assert.equal(h.w.EirinchanThreadExpansion.isLoading(), true);
  h.loads()[0].resolve(snapshot());
  assert.equal(h.w.EirinchanThreadExpansion.isLoading(), false);
  assert.deepEqual(Array.from(h.getThread().querySelectorAll(".reply"), node => node.id), ["reply_101", "reply_102", "reply_103"]);
  assert.equal(h.w.document.getElementById("reply_103"), old);
  assert.deepEqual(h.newPosts, ["reply_101", "reply_102"]);
  assert.equal(h.getThread().querySelector("span.omitted:not(.hide-expanded)").style.display, "none");
  assert.ok(h.getThread().querySelector('[data-thread-expansion-action="collapse"]'));
});

test("an unrelated index update preserves expanded nodes without another request", async t => {
  const h = await setup(t);
  h.click("expand"); h.loads()[0].resolve(snapshot());
  const retained = h.w.document.getElementById("reply_101");
  retained.dataset.localUi = "retained";
  h.apply(board(thread() + thread({id: 200, previews: [201]}), "another-thread-changed"));
  assert.equal(h.w.document.getElementById("reply_101"), retained);
  assert.equal(retained.dataset.localUi, "retained");
  assert.equal(h.loads().length, 1);
  assert.ok(h.getThread().querySelector(".hide-expanded"));
  assert.ok(h.getThread("test", 200));
});

test("changed expanded threads revalidate conditionally and reconcile edits, deletions and new replies", async t => {
  const h = await setup(t);
  h.click("expand"); h.loads()[0].resolve(snapshot());
  const unchanged = h.w.document.getElementById("reply_102");
  h.apply(board(thread({version: "preview-v2", previews: [[104, "v104", "New preview"]]})));
  assert.ok(h.w.document.getElementById("reply_101"), "no transient collapse while loading");
  assert.equal(h.loads().length, 2);
  assert.equal(h.loads()[1].options.headers["If-None-Match"], '"replies-v1"');
  h.loads()[1].resolve(snapshot([102, [103, "edited", "Edited reply"], 104]));
  assert.equal(h.w.document.getElementById("reply_101"), null);
  assert.equal(h.w.document.getElementById("reply_102"), unchanged);
  assert.equal(h.w.document.getElementById("reply_103").textContent, "Edited reply");
  assert.equal(h.getThread().querySelectorAll(".reply").length, 3);
  h.click("collapse");
  assert.deepEqual(Array.from(h.getThread().querySelectorAll(".reply"), node => node.id), ["reply_104"]);
  assert.equal(h.getThread().querySelector(".hide-expanded"), null);
});

test("a pending expansion resolves into the current node after replacement", async t => {
  const h = await setup(t);
  const old = h.getThread();
  h.click("expand");
  h.apply(board(thread()));
  assert.equal(old.isConnected, false);
  h.loads()[0].resolve(snapshot());
  assert.ok(h.getThread().querySelector("#reply_101"));
  assert.equal(old.querySelector("#reply_101"), null);
  assert.equal(h.loads().length, 1);
});

test("a superseded snapshot is discarded and coalesced into one fresh request", async t => {
  const h = await setup(t);
  h.click("expand");
  h.apply(board(thread({version: "new-preview", previews: [104]})));
  h.loads()[0].resolve(snapshot());
  assert.equal(h.w.document.getElementById("reply_101"), null);
  assert.equal(h.loads().length, 2);
  h.loads()[1].resolve(snapshot([102, 103, 104]));
  assert.ok(h.w.document.getElementById("reply_102"));
  assert.ok(h.w.document.getElementById("reply_104"));
});

test("collapse cancels pending work and a late callback cannot reopen it", async t => {
  const h = await setup(t);
  h.click("expand");
  const obsolete = h.loads()[0];
  h.click("collapse");
  assert.equal(obsolete.aborted, true);
  obsolete.resolve(snapshot());
  assert.equal(h.w.document.getElementById("reply_101"), null);
  assert.equal(h.getThread().querySelector(".hide-expanded"), null);
  assert.equal(h.w.EirinchanThreadExpansion.isLoading(), false);
  h.click("expand");
  obsolete.resolve(snapshot([999]));
  h.loads()[1].resolve(snapshot([102, 103]));
  assert.equal(h.w.document.getElementById("reply_999"), null);
  assert.ok(h.w.document.getElementById("reply_102"));
});

test("a removed thread aborts its request and releases its expansion state", async t => {
  const h = await setup(t);
  h.click("expand"); const obsolete = h.loads()[0];
  h.apply(board(""));
  assert.equal(obsolete.aborted, true);
  obsolete.resolve(snapshot());
  assert.equal(h.w.document.querySelector(".thread"), null);
  h.apply(board(thread())); h.click("expand");
  assert.equal(h.loads().length, 2);
  assert.equal(h.loads()[1].options.headers["If-None-Match"], undefined);
});

test("failed or malformed expansion keeps the preview and offers a bounded retry", async t => {
  const h = await setup(t);
  h.click("expand");
  h.w.EirinchanInitExpand(h.w.jQuery(h.getThread()));
  h.loads()[0].reject("timeout");
  assert.equal(h.w.EirinchanThreadExpansion.isLoading(), false);
  assert.ok(h.w.document.getElementById("reply_103"));
  h.click("retry");
  assert.equal(h.loads()[1].options.timeout, 15000);
  h.loads()[1].resolve("<html><body>Unrelated page</body></html>");
  assert.ok(h.getThread().querySelector('[data-thread-expansion-action="retry"]'));
  assert.ok(h.w.document.getElementById("reply_103"));
  h.click("retry"); h.loads()[2].resolve(snapshot([102, 103]));
  assert.ok(h.w.document.getElementById("reply_102"));
});

test("a mismatched thread snapshot cannot replace a different thread's replies", async t => {
  const h = await setup(t);
  h.click("expand"); h.loads()[0].resolve(snapshot([999], {board: "other", id: 100}));
  assert.equal(h.w.document.getElementById("reply_999"), null);
  assert.ok(h.getThread().querySelector('[data-thread-expansion-action="retry"]'));
});

test("selecting a post aborts expansion refreshes and protects its controls until selection clears", async t => {
  const h = await setup(t);
  h.click("expand"); h.loads()[0].resolve(snapshot());
  const post = h.w.document.getElementById("reply_102");
  const input = h.w.document.createElement("input");
  input.type = "checkbox"; input.className = "delete"; post.appendChild(input);
  h.apply(board(thread({version: "changed"})));
  const pending = h.loads()[1];
  input.checked = true;
  h.w.jQuery(input).trigger("change");
  assert.equal(pending.aborted, true);
  pending.resolve(snapshot([101, [102, "changed", "Changed"], 103]));
  assert.equal(input.isConnected, true);
  assert.equal(input.checked, true);
  input.checked = false; h.w.jQuery(input).trigger("change");
  assert.equal(h.loads().length, 3);
  h.loads()[2].resolve(snapshot([101, [102, "changed", "Changed"], 103]));
  assert.equal(h.w.document.getElementById("reply_102").textContent, "Changed");
});

test("repeated expansion/collapse/refresh cycles leave no duplicate separators or stale controls", async t => {
  const h = await setup(t);
  for (let i = 0; i < 3; i++) {
    h.click("expand"); h.loads().at(-1).resolve(snapshot());
    h.apply(board(thread({version: "cycle-" + i})));
    h.loads().at(-1).resolve(snapshot());
    assert.equal(h.getThread().querySelectorAll(".reply").length, 3);
    assert.equal(h.getThread().querySelectorAll("br").length, 4);
    h.click("collapse");
    assert.equal(h.getThread().querySelectorAll(".reply").length, 1);
    assert.equal(h.getThread().querySelectorAll("br").length, 2);
    assert.equal(h.getThread().querySelectorAll(".hide-expanded").length, 0);
  }
});

test("a 304 revalidation retains expanded content and unchanged node identity", async t => {
  const h = await setup(t);
  h.click("expand"); h.loads()[0].resolve(snapshot());
  const retained = h.w.document.getElementById("reply_101");
  h.apply(board(thread({version: "op-changed"})));
  h.loads()[1].resolve("", {status: 304});
  assert.equal(h.w.document.getElementById("reply_101"), retained);
  assert.equal(h.w.EirinchanThreadExpansion.isLoading(), false);
});

test("board/thread identity separates identical public IDs on overboard views", async t => {
  const h = await setup(t, {content: thread({board: "a"}) + thread({board: "b"})});
  h.click("expand", "a"); h.loads()[0].resolve(snapshot([101, 103], {board: "a"}));
  h.click("expand", "b"); h.loads()[1].resolve(snapshot([102, 103], {board: "b"}));
  h.click("collapse", "a");
  assert.equal(h.getThread("a").querySelector("#reply_101"), null);
  assert.ok(h.getThread("b").querySelector("#reply_102"));
});

test("page lifecycle aborts pending fetches and resumes them on bfcache restoration", async t => {
  const h = await setup(t);
  h.click("expand");
  h.w.jQuery(h.w).trigger("pagehide");
  assert.equal(h.loads()[0].aborted, true);
  assert.equal(h.w.EirinchanThreadExpansion.isLoading(), false);
  h.w.jQuery(h.w).trigger("pageshow");
  assert.equal(h.loads().length, 2);
  h.loads()[1].resolve(snapshot());
  assert.ok(h.w.document.getElementById("reply_101"));
});

test("expanding during the first poll aborts and invalidates the stale index response", async t => {
  const h = await setup(t, {withUpdater: true});
  await eventually(() => h.polls().length === 1);
  const old = h.getThread(), poll = h.polls()[0];
  h.click("expand");
  assert.equal(poll.aborted, true);
  poll.resolve(board(thread({version: "stale"})));
  assert.equal(h.getThread(), old);
  await delay(35);
  assert.equal(h.polls().length, 1, "polling waits only while the expansion fetch is pending");
  h.loads()[0].resolve(snapshot());
  await eventually(() => h.polls().length === 2);
  h.polls()[1].resolve("", {status: 304});
  assert.ok(h.w.document.getElementById("reply_101"));
});

test("real updater replacements preserve expansion and prepare filtering before insertion", async t => {
  const calls = [];
  const h = await setup(t, {withUpdater: true, configure(w) {
    w.EirinchanPostFilter = {prepareReplacement(current, replacement) {
      calls.push([current.isConnected, w.document.contains(replacement), !!replacement.querySelector("#reply_101")]);
    }};
  }});
  h.click("expand"); h.loads()[0].resolve(snapshot());
  await eventually(() => h.polls().length === 1);
  h.polls()[0].resolve(board(thread(), "changed-elsewhere"));
  assert.ok(h.w.document.getElementById("reply_101"));
  assert.deepEqual(calls, [[true, false, true]]);
  assert.equal(h.loads().length, 1);
});
