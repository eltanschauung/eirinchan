import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import {JSDOM} from "jsdom";

const source = await readFile(new URL("../../assets/js/polls.js", import.meta.url), "utf8");
const widget = id => `<section class="post-poll" data-poll-post-id="${id}"><div class="poll-question">Question?</div><div class="poll-options"><label><input type="radio" name="poll-${id}" value="0">First</label><label><input type="radio" name="poll-${id}" value="1">Second</label><button type="button" class="poll-vote">Vote</button></div><div class="poll-results" hidden></div><p class="poll-status"></p></section>`;
const voted = (label = "First", total = 1) => ({voted: true, total, results: [{label, choice: 0, count: total}, {label: "Second", choice: 1, count: 0}]});
const response = (body, ok = true) => ({ok, json: async () => body});
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => {resolve = yes; reject = no;}); return {promise, resolve, reject}; };

async function setup(t, html = widget(1), handler = null) {
  const dom = new JSDOM(`<!doctype html><meta name="csrf-token" content="old-token"><form id="postcontrols">${html}</form>`, {url: "https://example.test/test/", runScripts: "outside-only"});
  t.after(() => dom.window.close());
  const w = dom.window, requests = [];
  w.fetch = async (url, options) => {
    requests.push({url, options});
    if (handler) { const handled = handler(url, options); if (handled !== undefined) return handled; }
    if (url === "/csrf-token") return response({csrf_token: "fresh-token"});
    if (url.includes("/vote")) return response({data: voted()});
    const ids = url.split("ids=")[1].split(",");
    return response({data: Object.fromEntries(ids.map(id => [id, {voted: false}]))});
  };
  w.eval(source); w.document.dispatchEvent(new w.Event("DOMContentLoaded"));
  const flush = async () => { await new Promise(resolve => w.setTimeout(resolve, 12)); };
  const choose = (id = 1, value = "0") => {
    const input = w.document.querySelector(`[data-poll-post-id="${id}"] input[value="${value}"]`);
    input.checked = true; input.dispatchEvent(new w.Event("change", {bubbles: true}));
  };
  await flush();
  return {w, requests, flush, choose, vote: () => w.document.querySelector(".poll-vote").click()};
}

test("status loads in bounded batches and duplicate/cloned widgets get independent radio groups", async t => {
  const {w, requests} = await setup(t, widget(1) + widget(1) + Array.from({length: 50}, (_, n) => widget(n + 2)).join(""));
  assert.equal(requests.length, 2);
  assert.equal(requests[0].url.split("ids=")[1].split(",").length, 50);
  assert.equal(requests[1].url.split("ids=")[1].split(",").length, 1);
  const names = [...w.document.querySelectorAll('[data-poll-post-id="1"] input[value="0"]')].map(input => input.name);
  assert.notEqual(names[0], names[1]);
  assert.equal(w.document.querySelector(".poll-results").hidden, true);
});

test("large pages cap receipt reads at two concurrent batches", async t => {
  const pending = [deferred(), deferred()];
  let reads = 0;
  const {requests, flush} = await setup(t, Array.from({length: 101}, (_, n) => widget(n + 1)).join(""), url => {
    if (url.includes("/state") && reads < 2) return pending[reads++].promise;
  });
  assert.equal(requests.length, 2);
  const ids = requests[0].url.split("ids=")[1].split(",");
  pending[0].resolve(response({data: Object.fromEntries(ids.map(id => [id, {voted: false}]))}));
  await flush();
  assert.equal(requests.length, 3);
  pending[1].resolve(response({data: {}}));
  await flush();
});

test("voting refreshes CSRF and displays results without submitting the enclosing delete/report form", async t => {
  const {w, requests, flush, choose, vote} = await setup(t);
  let submits = 0; w.document.querySelector("form").addEventListener("submit", e => {submits++; e.preventDefault();});
  choose(1, "1"); vote(); await flush();
  assert.equal(submits, 0);
  const request = requests.find(r => r.url.includes("/vote"));
  assert.deepEqual(JSON.parse(request.options.body), {choice: 1});
  assert.equal(request.options.headers["X-CSRF-Token"], "fresh-token");
  assert.equal(request.options.credentials, "same-origin");
  assert.equal(w.document.querySelector('meta[name="csrf-token"]').content, "fresh-token");
  assert.equal(w.document.querySelector(".poll-options").hidden, true);
  assert.match(w.document.querySelector(".poll-results").textContent, /Total votes: 1/);
});

test("a duplicate click cannot issue a second write while one is in flight", async t => {
  const pending = deferred();
  const {w, requests, flush, choose, vote} = await setup(t, widget(1), url => url.includes("/vote") ? pending.promise : undefined);
  choose(); vote(); vote(); await flush();
  assert.equal(requests.filter(r => r.url.includes("/vote")).length, 1);
  assert.equal(w.document.querySelector(".poll-vote").disabled, true);
  pending.resolve(response({data: voted()})); await flush();
  assert.equal(w.document.querySelector(".poll-results").hidden, false);
});

test("late initial status cannot undo a completed vote", async t => {
  const pending = deferred();
  const {w, choose, vote, flush} = await setup(t, widget(1), url => url.includes("/state") ? pending.promise : undefined);
  choose(); vote(); await flush();
  pending.resolve(response({data: {1: {voted: false}}})); await flush();
  assert.equal(w.document.querySelector(".poll-options").hidden, true);
  assert.match(w.document.querySelector(".poll-results").textContent, /Total votes: 1/);
});

test("updater replacement retains a choice and busy state, and a late vote updates the replacement", async t => {
  const pending = deferred();
  const {w, choose, vote, flush} = await setup(t, widget(1), url => url.includes("/vote") ? pending.promise : undefined);
  choose(1, "1"); vote(); await flush();
  w.document.querySelector(".post-poll").outerHTML = widget(1); await flush();
  assert.equal(w.document.querySelector('input[value="1"]').checked, true);
  assert.equal(w.document.querySelector(".poll-vote").disabled, true);
  pending.resolve(response({data: voted()})); await flush();
  assert.equal(w.document.querySelector(".poll-results").hidden, false);
});

test("refreshing results uses text nodes and cannot regress totals from an older snapshot", async t => {
  let count = 0;
  const {w, flush} = await setup(t, widget(1), url => url.includes("/state") ? response({data: {1: voted('<img src=x onerror="alert(1)">', ++count === 1 ? 3 : 1)}}) : undefined);
  assert.equal(w.document.querySelector(".poll-results img"), null);
  assert.match(w.document.querySelector(".poll-results").textContent, /<img src=x/);
  w.document.querySelector(".poll-refresh").click(); await flush();
  assert.match(w.document.querySelector(".poll-results").textContent, /Total votes: 3/);
});

test("explicit stale-CSRF responses retry once with a fresh token", async t => {
  let writes = 0;
  const {requests, choose, vote, flush, w} = await setup(t, widget(1), url => url.includes("/vote") ? (++writes === 1 ? response({csrf: true, error: "stale"}, false) : response({data: voted()})) : undefined);
  choose(); vote(); await flush();
  assert.equal(writes, 2);
  assert.equal(requests.filter(r => r.url === "/csrf-token").length, 2);
  assert.equal(w.document.querySelector(".poll-results").hidden, false);
});

test("failed writes remain retryable with the selected option intact", async t => {
  let writes = 0;
  const {w, choose, vote, flush} = await setup(t, widget(1), url => url.includes("/vote") ? (++writes === 1 ? Promise.reject(new Error("Network failure")) : response({data: voted()})) : undefined);
  choose(1, "1"); vote(); await flush();
  assert.equal(w.document.querySelector(".poll-vote").disabled, false);
  assert.equal(w.document.querySelector('input[value="1"]').checked, true);
  assert.match(w.document.querySelector(".poll-status").textContent, /Network failure/);
  vote(); await flush();
  assert.equal(writes, 2);
  assert.equal(w.document.querySelector(".poll-results").hidden, false);
});

test("choosing an option is required and repeated initialization never adds duplicate handlers", async t => {
  const {w, requests, choose, vote, flush} = await setup(t);
  w.eval(source); w.document.dispatchEvent(new w.Event("DOMContentLoaded"));
  vote(); await flush();
  assert.match(w.document.querySelector(".poll-status").textContent, /Choose an option/);
  assert.equal(requests.filter(r => r.url.includes("/vote")).length, 0);
  choose(); vote(); await flush();
  assert.equal(requests.filter(r => r.url.includes("/vote")).length, 1);
});

test("a cached vote is restored on newly inserted or cloned post widgets", async t => {
  const {w, flush, requests} = await setup(t, widget(1), url => url.includes("/state") ? response({data: {1: voted()}}) : undefined);
  w.document.querySelector("form").insertAdjacentHTML("beforeend", widget(1)); await flush();
  assert.equal(requests.length, 1);
  assert.equal(w.document.querySelectorAll(".poll-results:not([hidden])").length, 2);
});
