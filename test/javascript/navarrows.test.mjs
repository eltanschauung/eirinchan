import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const source = await readFile(path.join(projectRoot, "priv/static/js/navarrows2.js"), "utf8");

test("the disabled navigation-arrow preference hides pre-rendered arrows", () => {
  const dom = new JSDOM(
    `<!doctype html><html><body>
      <div class="navarrow navarrow-top"></div>
      <div class="navarrow navarrow-bottom"></div>
    </body></html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/index.html"}
  );

  dom.window.active_page = "index";
  dom.window.document.cookie = "navarrows=false; path=/";
  dom.window.eval(source);
  dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));

  for (const arrow of dom.window.document.querySelectorAll(".navarrow")) {
    assert.equal(arrow.style.display, "none");
  }
});
