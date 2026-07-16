import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const optionsSource = await readFile(path.join(projectRoot, "assets/js/options.js"), "utf8");

function optionsWindow() {
  const dom = new JSDOM(
    `<!doctype html><html><body>
      <a id="options-link" href="#">[Options]</a>
      <div id="options_handler" style="display:none">
        <div id="options_background"></div>
        <div id="options_div">
          <button id="options_close" type="button">Close</button>
          <div id="options_tablist">
            <div id="options-tab-icon-general" class="options_tab_icon"><div>General</div></div>
            <div id="options-tab-icon-watcher" class="options_tab_icon"><div>Watcher</div></div>
            <div id="options-exit-tab" class="options_tab_icon"><div>Exit</div></div>
          </div>
          <div id="options-tab-general" class="options_tab" style="display:none"><h2>General</h2></div>
          <div id="options-tab-watcher" class="options_tab" style="display:none"><h2>Watcher</h2></div>
        </div>
      </div>
    </body></html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/index.html"}
  );

  dom.window._ = (value) => value;
  dom.window.eval(jquerySource);
  dom.window.jQuery.fx.off = true;
  dom.window.eval(optionsSource);
  dom.window.Options.add_tab("general", "home", "General");
  dom.window.Options.add_tab("watcher", "eye", "Watcher");
  return dom.window;
}

test("pre-rendered option tab icons switch the visible tab", () => {
  const window = optionsWindow();
  const {document, Options} = window;

  Options.show();
  const originalWatcherIcon = document.getElementById("options-tab-icon-watcher");
  const watcherIcon = originalWatcherIcon.cloneNode(true);
  originalWatcherIcon.replaceWith(watcherIcon);
  watcherIcon.click();

  assert.equal(document.getElementById("options-tab-icon-general").classList.contains("active"), false);
  assert.equal(document.getElementById("options-tab-icon-watcher").classList.contains("active"), true);
  assert.equal(document.getElementById("options-tab-general").style.display, "none");
  assert.notEqual(document.getElementById("options-tab-watcher").style.display, "none");
});

test("legacy option markup renders as controls and is sanitized", () => {
  const window = optionsWindow();
  const {document, Options} = window;

  Options.extend_tab(
    "general",
    '<label id="show-yous" onclick="window.compromised=true"><input type="checkbox">Show (You)s<script>window.compromised=true</script></label>' +
      '<a id="unsafe-link" href="//attacker.test">unsafe</a>' +
      '<a id="safe-link" href="/bant/">safe</a>'
  );

  const label = document.getElementById("show-yous");
  assert.ok(label);
  assert.equal(label.getAttribute("onclick"), null);
  assert.ok(label.querySelector('input[type="checkbox"]'));
  assert.equal(label.querySelector("script"), null);
  assert.equal(window.compromised, undefined);
  assert.equal(label.textContent, "Show (You)s");
  assert.equal(document.getElementById("unsafe-link").hasAttribute("href"), false);
  assert.equal(document.getElementById("safe-link").getAttribute("href"), "/bant/");
});
