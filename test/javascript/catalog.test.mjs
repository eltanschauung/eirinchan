import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const catalogSource = await readFile(path.join(projectRoot, "priv/static/js/catalog.js"), "utf8");

function catalogWindow() {
  const dom = new JSDOM(
    `<!doctype html><html><body class="active-catalog">
      <div id="Grid">
        <div class="mix post-filter-hidden" data-id="100" style="display:none"></div>
        <div class="mix" data-id="200"></div>
      </div>
    </body></html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/catalog.html"}
  );

  const {window} = dom;
  window.active_page = "catalog";
  window.board_name = "bant";
  window.onReady = (callback) => callback();
  window.localStorage.setItem(
    "hiddenthreads",
    JSON.stringify({bant: {200: Math.floor(Date.now() / 1000)}})
  );
  window.eval(jquerySource);
  window.eval(catalogSource);
  return window;
}

test("catalog hiding owns only the catalog-thread-hidden class", () => {
  const window = catalogWindow();
  const filtered = window.document.querySelector('.mix[data-id="100"]');
  const manuallyHidden = window.document.querySelector('.mix[data-id="200"]');

  assert.equal(filtered.classList.contains("post-filter-hidden"), true);
  assert.equal(filtered.style.display, "none");
  assert.equal(manuallyHidden.classList.contains("catalog-thread-hidden"), true);
  assert.equal(manuallyHidden.style.display, "");

  window.jQuery(window.document).trigger("filter_page");
  assert.equal(filtered.classList.contains("post-filter-hidden"), true);
  assert.equal(filtered.style.display, "none");
  assert.equal(manuallyHidden.classList.contains("catalog-thread-hidden"), true);
  window.close();
});

test("clearing catalog-hidden threads preserves post-filter visibility", () => {
  const window = catalogWindow();
  const filtered = window.document.querySelector('.mix[data-id="100"]');
  const manuallyHidden = window.document.querySelector('.mix[data-id="200"]');

  window.jQuery(window.document).trigger("clear_hidden_threads");

  assert.equal(manuallyHidden.classList.contains("catalog-thread-hidden"), false);
  assert.equal(filtered.classList.contains("post-filter-hidden"), true);
  assert.equal(filtered.style.display, "none");
  window.close();
});
