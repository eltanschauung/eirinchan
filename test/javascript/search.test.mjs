import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const source = await readFile(path.join(projectRoot, "assets/js/search.js"), "utf8");

function searchWindow(html = '<form id="advanced-search"></form>') {
  const dom = new JSDOM(`<!doctype html><html><body>${html}</body></html>`, {
    runScripts: "outside-only",
    url: "https://example.test/search.php"
  });
  dom.window.eval(source);
  return dom.window;
}

test("image hashing matches the server's base64 MD5 representation", () => {
  const window = searchWindow();
  const bytes = new TextEncoder().encode("abc");
  assert.equal(window.EirinchanSearch.md5Base64(bytes.buffer), "kAFQmDzST7DWlj99KOF/cg==");
});

test("search initialization leaves a server-rendered form usable", () => {
  const window = searchWindow(`
    <form id="advanced-search" data-search-history-key="search-test">
      <input name="text" value="tea">
      <button type="submit" name="scope" value="selected">Search</button>
    </form>
    <ol id="search-history-list"></ol>
  `);

  window.document.dispatchEvent(new window.Event("DOMContentLoaded"));

  assert.equal(window.document.querySelector('[name="text"]').value, "tea");
  assert.match(window.document.getElementById("search-history-list").textContent, /Stored only/);
});

test("search history renders only same-origin search URLs", () => {
  const window = searchWindow(`
    <form id="advanced-search" data-search-history-key="search-test"></form>
    <ol id="search-history-list"></ol>
  `);

  window.localStorage.setItem("search-test", JSON.stringify([
    {url: "javascript:alert(1)", label: "unsafe scheme"},
    {url: "https://attacker.test/search.php", label: "external"},
    {url: "/feedback", label: "wrong path"},
    null,
    {url: "/search.php?text=tea", label: "valid"}
  ]));
  window.document.dispatchEvent(new window.Event("DOMContentLoaded"));

  const links = [...window.document.querySelectorAll("#search-history-list a")];
  assert.equal(links.length, 1);
  assert.equal(links[0].textContent, "valid");
  assert.equal(links[0].getAttribute("href"), "/search.php?text=tea");
});

test("the local hash picker never submits a file and clears stale hashes", () => {
  const window = searchWindow(`
    <form id="advanced-search" data-search-history-key="search-test">
      <input id="search-image-hash" name="image_hash" value="stale-hash">
      <input id="search-image-file" type="file">
      <button id="search-image-drop" type="button">Drop image here</button>
    </form>
    <ol id="search-history-list"></ol>
  `);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded"));

  const drop = new window.Event("drop", {bubbles: true, cancelable: true});
  Object.defineProperty(drop, "dataTransfer", {
    value: {files: [{size: 65 * 1024 * 1024}]}
  });
  window.document.getElementById("search-image-drop").dispatchEvent(drop);

  const form = window.document.getElementById("advanced-search");
  const data = new window.FormData(form);
  assert.equal(data.get("image_hash"), "");
  assert.equal(data.has("search-image-file"), false);
  assert.equal(window.document.getElementById("search-image-file").hasAttribute("name"), false);
  assert.match(window.document.getElementById("search-image-drop").textContent, /too large/i);
});
