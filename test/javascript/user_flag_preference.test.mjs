import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const source = await readFile(path.join(projectRoot, "assets/js/user-flag-preference.js"), "utf8");

function preferenceWindow({cookie, legacy, stored} = {}) {
  const dom = new JSDOM(`<!doctype html><html><head>
    <meta name="eirinchan:board-name" content="bant">
    <meta name="eirinchan:user-flag-cookie-name" content="eirinchan_user_flag">
    <meta name="eirinchan:user-flag-allowed-values" content='["country","meiling","tenshi","us"]'>
    <meta name="eirinchan:user-flag-mode" content="multi">
    <meta name="eirinchan:preference-cookie-max-age" content="31536000">
  </head><body></body></html>`, {
    runScripts: "outside-only",
    url: "https://example.test/bant/"
  });

  const {window} = dom;
  if (stored !== undefined) window.localStorage.setItem("flag_", stored);
  if (legacy !== undefined) window.localStorage.setItem("flag_bant", legacy);
  if (cookie !== undefined) window.document.cookie = `eirinchan_user_flag=${encodeURIComponent(cookie)}; path=/`;
  window.eval(source);
  return window;
}

function appendPostForm(window, value = "country") {
  const form = window.document.createElement("form");
  form.dataset.postForm = "";
  form.innerHTML = `<input name="user_flag" value="${value}">`;
  window.document.body.append(form);
  return form;
}

test("capture-phase submit finalization wins even before deferred initialization", () => {
  const window = preferenceWindow({stored: "country,meiling"});
  const form = appendPostForm(window);

  form.dispatchEvent(new window.Event("submit", {bubbles: true, cancelable: true}));

  assert.equal(form.elements.user_flag.value, "country,meiling");
  assert.equal(new window.FormData(form).get("user_flag"), "country,meiling");
  assert.match(window.document.cookie, /eirinchan_user_flag=country%2Cmeiling/);
});

test("an explicit field change becomes the canonical preference at serialization", () => {
  const window = preferenceWindow({stored: "country,meiling"});
  const form = appendPostForm(window);
  window.EirinchanUserFlagPreference.hydrate(form);

  form.elements.user_flag.value = "tenshi";
  assert.equal(window.EirinchanUserFlagPreference.finalize(form), "tenshi");
  assert.equal(window.localStorage.getItem("flag_"), "tenshi");
  assert.equal(new window.FormData(form).get("user_flag"), "tenshi");
});

test("the server-readable cookie restores storage in a fresh browser context", () => {
  const window = preferenceWindow({cookie: "country,tenshi"});
  const form = appendPostForm(window);

  window.EirinchanUserFlagPreference.hydrate(form);

  assert.equal(form.elements.user_flag.value, "country,tenshi");
  assert.equal(window.localStorage.getItem("flag_"), "country,tenshi");
});

test("legacy per-board storage is migrated before a form can submit", () => {
  const window = preferenceWindow({legacy: "meiling"});
  const form = appendPostForm(window);

  window.EirinchanUserFlagPreference.finalize(form);

  assert.equal(form.elements.user_flag.value, "meiling");
  assert.equal(window.localStorage.getItem("flag_"), "meiling");
  assert.equal(window.localStorage.getItem("flag_bant"), null);
});

test("stale values removed from configuration cannot override the rendered default", () => {
  const window = preferenceWindow({stored: "removed-flag", cookie: "also-removed"});
  const form = appendPostForm(window, "country");

  window.EirinchanUserFlagPreference.finalize(form);

  assert.equal(form.elements.user_flag.value, "country");
  assert.equal(window.localStorage.getItem("flag_"), "country");
  assert.match(window.document.cookie, /eirinchan_user_flag=country/);
});
