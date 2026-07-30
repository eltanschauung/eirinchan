import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const watcherSource = await readFile(
  path.join(projectRoot, "priv/static/js/thread-watcher.js"),
  "utf8"
);

test("watcher menu integration is installed when Menu already exists", async () => {
  const dom = new JSDOM("<!doctype html><html><body></body></html>", {
    runScripts: "outside-only",
    url: "https://example.test/bant/"
  });
  const {window} = dom;
  const items = [];
  const callbacks = [];

  window.eval(jquerySource);
  window.Menu = {
    add_item(id, label) {
      items.push({id, label});
    },
    onclick(callback) {
      callbacks.push(callback);
    }
  };

  window.eval(watcherSource);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded", {bubbles: true}));
  await new Promise((resolve) => window.setTimeout(resolve, 0));

  assert.deepEqual(items, [{id: "watch_thread_menu", label: "Watch"}]);
  assert.equal(callbacks.length, 1);

  window.jQuery(window.document).trigger("menu_ready");
  assert.equal(items.length, 1);
  assert.equal(callbacks.length, 1);
  window.close();
});
