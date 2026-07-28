import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

const sources = await Promise.all(
  [
    "priv/static/js/jquery.min.js",
    "assets/js/options.js",
    "assets/js/options/general.js",
    "priv/static/js/thread-watcher.js",
    "assets/js/navarrows2.js",
    "assets/js/post-filter.js",
    "assets/js/image-hover.js",
    "assets/js/show-own-posts-options.js",
    "assets/js/webm-settings.js"
  ].map((relativePath) => readFile(path.join(projectRoot, relativePath), "utf8"))
);

function optionsShell() {
  return `
    <div class="boardlist">
      <span id="admin_options_links">
        <button id="watcher-link" type="button">Watcher</button>
        <a id="admin-link" href="/manage">[Admin]</a>
        <a id="options-link" href="#">[Options]</a>
      </span>
    </div>
    <div id="options_handler" style="display:none">
      <div id="options_background"></div>
      <div id="options_div">
        <button id="options_close" type="button">Close</button>
        <div id="options_tablist">
          <div id="options-tab-icon-general" class="options_tab_icon"><div>General</div></div>
          <div id="options-tab-icon-watcher" class="options_tab_icon"><div>Watcher</div></div>
          <div id="options-exit-tab" class="options_tab_icon"><div>Exit</div></div>
        </div>
        <div id="options-tab-general" class="options_tab" style="display:none">
          <h2>General</h2>
          <div id="general-preferences"></div>
          <div id="options-storage-controls">
            <button id="options-storage-export" type="button">Export</button>
            <button id="options-storage-import" type="button">Import</button>
            <button id="options-storage-erase" type="button">Erase</button>
            <input id="options-storage-output" type="text" hidden>
          </div>
        </div>
        <div id="options-tab-watcher" class="options_tab" style="display:none">
          <h2>Watcher</h2>
          <div id="watcher-tab-content"></div>
        </div>
      </div>
    </div>
  `;
}

async function menuSignature(activePage) {
  const dom = new JSDOM(`<!doctype html><html><head></head><body>${optionsShell()}</body></html>`, {
    runScripts: "outside-only",
    url: `https://example.test/${activePage}/`
  });
  const {window} = dom;
  window._ = (value) => value;
  window.active_page = activePage;
  window.board_name = activePage === "recent" ? "" : "bant";
  window.EirinchanRuntime = {
    preferenceCookieMaxAge: 31_536_000,
    readCookie(_name, fallback) {
      return fallback;
    },
    writeCookie() {},
    requestJson() {
      return Promise.resolve({});
    }
  };

  for (const source of sources) window.eval(source);
  window.jQuery.fx.off = true;
  window.document.dispatchEvent(new window.Event("DOMContentLoaded", {bubbles: true}));
  await new Promise((resolve) => window.setTimeout(resolve, 0));

  const signature = {
    tabs: Array.from(window.document.querySelectorAll("#options_tablist > div")).map(
      (element) => element.id
    ),
    general: [
      "options-storage-controls",
      "add-nav-arrows",
      "imageHover",
      "catalogImageHover",
      "imageHoverFollowCursor",
      "show-yous"
    ].map((id) => [id, !!window.document.getElementById(id)]),
    filters: [
      "options-tab-filter",
      "filter-control",
      "filter-use-regex",
      "set-filter",
      "clear",
      "filter-list"
    ].map((id) => [id, !!window.document.getElementById(id)]),
    webm: [
      "options-tab-webm",
      "webm-settings-menu",
      ...Array.from(
        window.document.querySelectorAll("#webm-settings-menu input"),
        (input) => input.name
      )
    ]
  };

  assert.equal(typeof window.setting, "function");
  assert.equal(typeof window.changeSetting, "function");

  window.close();
  return signature;
}

test("every public page receives the board-index Options menu", async () => {
  const indexSignature = await menuSignature("index");

  for (const activePage of ["thread", "catalog", "ukko", "search", "recent", "news"]) {
    assert.deepEqual(
      await menuSignature(activePage),
      indexSignature,
      `${activePage} Options menu differs from index`
    );
  }
});
