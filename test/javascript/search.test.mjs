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
