import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const appSource = await readFile(path.join(projectRoot, "assets/js/app.js"), "utf8");

function threadControlsWindow(fetchImplementation) {
  const dom = new JSDOM(
    `<!doctype html><html><body>
      <a id="thread-return" href="/bant/2.html">[Return]</a>
      <form id="thread-post-controls" action="/post.php" method="post">
        <input type="hidden" name="_csrf_token" value="csrf-token">
        <input type="hidden" name="board" value="bant">
        <input type="hidden" name="delete_post_id" value="">
        <input type="hidden" name="report_post_id" value="">
        <input type="checkbox" data-post-select name="delete_390418" value="390418" checked>
        <input type="submit" name="delete" value="Delete" data-post-action="delete">
      </form>
    </body></html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/res/390417.html"}
  );

  dom.window.fetch = fetchImplementation;
  dom.window.eval(appSource);
  return dom.window;
}

function submitDelete(window) {
  const form = window.document.querySelector("#thread-post-controls");
  const button = form.querySelector('[data-post-action="delete"]');
  const event = new window.SubmitEvent("submit", {
    bubbles: true,
    cancelable: true,
    submitter: button
  });

  form.dispatchEvent(event);
  return {button, event};
}

function flushPromises(window) {
  return new Promise((resolve) => window.setTimeout(resolve, 0));
}

test("a successful thread-page delete invokes the current Return link", async () => {
  let request;
  const window = threadControlsWindow(async (url, options) => {
    request = {url, options};
    return {
      ok: true,
      json: async () => ({deleted_post_id: 390418, thread_deleted: false})
    };
  });
  let returnClicks = 0;

  window.document.querySelector("#thread-return").addEventListener("click", (event) => {
    event.preventDefault();
    returnClicks += 1;
  });

  const {button, event} = submitDelete(window);
  assert.equal(event.defaultPrevented, true);
  assert.equal(button.disabled, true);

  await flushPromises(window);

  assert.equal(request.url, "https://example.test/post.php");
  assert.equal(request.options.method, "POST");
  assert.equal(request.options.credentials, "same-origin");
  assert.equal(request.options.body.get("delete_post_id"), "390418");
  assert.equal(request.options.body.get("report_post_id"), null);
  assert.equal(request.options.body.get("json_response"), "1");
  assert.equal(returnClicks, 1);
  assert.equal(button.disabled, false);
});

test("a rejected delete stays on the thread and displays the server error", async () => {
  const window = threadControlsWindow(async () => ({
    ok: false,
    json: async () => ({error: "Incorrect password."})
  }));
  let returnClicks = 0;
  let alertMessage = null;

  window.document.querySelector("#thread-return").addEventListener("click", (event) => {
    event.preventDefault();
    returnClicks += 1;
  });
  window.showAlert = (message) => {
    alertMessage = message;
  };

  const {button, event} = submitDelete(window);
  assert.equal(event.defaultPrevented, true);

  await flushPromises(window);

  assert.equal(returnClicks, 0);
  assert.equal(alertMessage, "Incorrect password.");
  assert.equal(button.disabled, false);
});
