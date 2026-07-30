import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const updaterSource = await readFile(path.join(projectRoot, "priv/static/js/auto-reload.js"), "utf8");

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function setup({deleteChecked = false, configureWindow} = {}) {
  const dom = new JSDOM(`<!doctype html><html><head><title>Board</title></head><body>
    <div id="updater" data-live-updater data-page-kind="index" data-poll-interval-seconds="0.01">
      <input id="auto_update_status" type="checkbox">
      <span id="update_secs"></span>
      <a href="#" id="update_thread" aria-pressed="true">Live</a>
    </div>
    <div id="board-refresh-target" data-fragment-md5="current">
      <input type="checkbox" class="delete" id="delete_1" ${deleteChecked ? "checked" : ""}>
    </div>
  </body></html>`, {
    runScripts: "outside-only",
    url: "https://example.test/bant/"
  });

  const requests = [];
  dom.window.eval(jquerySource);
  if (configureWindow) configureWindow(dom.window);
  dom.window.jQuery.ajax = () => {
    const doneCallbacks = [];
    const failCallbacks = [];
    const alwaysCallbacks = [];
    const request = {
      aborted: false,
      done(callback) {
        doneCallbacks.push(callback);
        return request;
      },
      fail(callback) {
        failCallbacks.push(callback);
        return request;
      },
      always(callback) {
        alwaysCallbacks.push(callback);
        return request;
      },
      abort() {
        request.aborted = true;
        failCallbacks.forEach((callback) => callback({}, "abort", "abort"));
        alwaysCallbacks.forEach((callback) => callback());
      },
      resolve(markup, {status = 200, textStatus = "success"} = {}) {
        const xhr = {status};
        doneCallbacks.forEach((callback) => callback(markup, textStatus, xhr));
        alwaysCallbacks.forEach((callback) => callback(xhr, textStatus));
      }
    };

    requests.push(request);
    return request;
  };

  dom.window.eval(updaterSource);
  await delay(5);
  return {dom, requests};
}

test("a checked delete control pauses live updates until it is cleared", async () => {
  const {dom, requests} = await setup({deleteChecked: true});
  const toggle = dom.window.document.getElementById("update_thread");
  const checkbox = dom.window.document.getElementById("delete_1");

  await delay(25);
  assert.equal(requests.length, 0);
  assert.equal(toggle.getAttribute("aria-pressed"), "false");
  assert.equal(dom.window.auto_reload_enabled, false);

  checkbox.checked = false;
  dom.window.jQuery(checkbox).trigger("change");
  await delay(25);

  assert.equal(requests.length, 1);
  assert.equal(toggle.getAttribute("aria-pressed"), "true");
  assert.equal(dom.window.auto_reload_enabled, true);
  dom.window.close();
});

test("checking a delete control aborts an in-flight update", async () => {
  const {dom, requests} = await setup();
  const toggle = dom.window.document.getElementById("update_thread");
  const checkbox = dom.window.document.getElementById("delete_1");

  await delay(25);
  assert.equal(requests.length, 1);

  checkbox.checked = true;
  dom.window.jQuery(checkbox).trigger("change");

  assert.equal(requests[0].aborted, true);
  assert.equal(toggle.getAttribute("aria-pressed"), "false");
  assert.equal(dom.window.auto_reload_enabled, false);
  dom.window.close();
});

test("index features prepare a replacement before the updater commits it", async () => {
  const calls = [];
  const {dom, requests} = await setup({
    configureWindow(window) {
      window.EirinchanPostFilter = {
        prepareReplacement(current, replacement) {
          calls.push({
            currentConnected: current.isConnected,
            replacementInLiveDocument: window.document.contains(replacement)
          });
          replacement.dataset.filtersPrepared = "true";
        }
      };
    }
  });

  await delay(25);
  assert.equal(requests.length, 1);

  requests[0].resolve(`<!doctype html><html><body>
    <div id="board-refresh-target" data-fragment-md5="next">
      <div id="board-threads">
        <div class="thread" id="thread_100" data-board="bant" data-thread-id="100">
          <div class="post op" id="op_100"></div>
        </div>
      </div>
    </div>
  </body></html>`);

  const replacement = dom.window.document.getElementById("board-refresh-target");
  assert.deepEqual(calls, [{currentConnected: true, replacementInLiveDocument: false}]);
  assert.equal(replacement.dataset.filtersPrepared, "true");
  dom.window.close();
});
