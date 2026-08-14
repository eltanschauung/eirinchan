import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const source = await readFile(path.join(projectRoot, "assets/js/post-actions.js"), "utf8");

function actionWindow(markup, fetchImplementation) {
  const dom = new JSDOM(`<!doctype html><html><body>${markup}</body></html>`, {
    runScripts: "outside-only",
    url: "https://example.test/bant/res/390417.html"
  });
  const alerts = [];
  const runtimeAlerts = [];
  const redirects = [];

  dom.window.EirinchanRuntime = {
    showAlert(message) {
      runtimeAlerts.push(message);
    }
  };
  dom.window.alert = (message) => {
    alerts.push(message);
  };
  dom.window.EirinchanPostActions = {
    navigate(redirect) {
      redirects.push(redirect);
    }
  };
  dom.window.fetch = fetchImplementation;
  dom.window.eval(source);

  return {alerts, redirects, runtimeAlerts, window: dom.window};
}

function submit(window, selector) {
  const button = window.document.querySelector(selector);
  const form = button.form;
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

test("incorrect quick-action passwords use the rejection popup without navigating", async () => {
  let request;
  const {alerts, redirects, runtimeAlerts, window} = actionWindow(
    `<form class="post-actions" action="/post.php" method="post">
      <input type="hidden" name="_csrf_token" value="csrf-token">
      <input type="hidden" name="board" value="bant">
      <input type="hidden" name="delete_390418">
      <input type="password" name="password" value="wrong">
      <input type="submit" name="delete" value="Delete">
    </form>`,
    async (url, options) => {
      request = {url, options};
      return new Response(JSON.stringify({error: "Incorrect password."}), {
        status: 403,
        headers: {"content-type": "application/json"}
      });
    }
  );

  const {button, event} = submit(window, 'input[name="delete"]');
  assert.equal(event.defaultPrevented, true);
  assert.equal(button.disabled, true);

  await flushPromises(window);

  assert.equal(request.url, "https://example.test/post.php");
  assert.equal(request.options.body.get("delete_post_id"), "390418");
  assert.equal(request.options.body.get("json_response"), "1");
  assert.equal(request.options.headers.Accept, undefined);
  assert.deepEqual(alerts, ["Incorrect password."]);
  assert.deepEqual(runtimeAlerts, []);
  assert.deepEqual(redirects, []);
  assert.equal(button.disabled, false);
});

test("board report rejections use the same popup pipeline", async () => {
  const {alerts, redirects, window} = actionWindow(
    `<form name="postcontrols" action="/post.php" method="post">
      <input type="hidden" name="_csrf_token" value="csrf-token">
      <input type="hidden" name="board" value="bant">
      <input type="hidden" name="delete_post_id" value="">
      <input type="hidden" name="report_post_id" value="">
      <input class="delete" type="checkbox" name="delete_390418" checked>
      <input type="text" name="reason" value="spam">
      <input type="submit" name="report" value="Report">
    </form>`,
    async (_url, options) => {
      assert.equal(options.body.get("report_post_id"), "390418");
      assert.equal(options.body.get("delete_post_id"), null);
      return new Response(JSON.stringify({error: "Report rejected."}), {
        status: 422,
        headers: {"content-type": "application/json"}
      });
    }
  );

  const {event} = submit(window, 'input[name="report"]');
  assert.equal(event.defaultPrevented, true);

  await flushPromises(window);

  assert.deepEqual(alerts, ["Report rejected."]);
  assert.deepEqual(redirects, []);
});

test("successful post actions follow the server redirect", async () => {
  const {alerts, redirects, window} = actionWindow(
    `<form class="post-actions" action="/post.php" method="post">
      <input type="hidden" name="board" value="bant">
      <input type="hidden" name="delete_390418">
      <input type="password" name="password" value="correct">
      <input type="submit" name="delete" value="Delete">
    </form>`,
    async () =>
      new Response(JSON.stringify({redirect: "/bant/res/390417.html"}), {
        status: 200,
        headers: {"content-type": "application/json"}
      })
  );

  submit(window, 'input[name="delete"]');
  await flushPromises(window);

  assert.deepEqual(alerts, []);
  assert.deepEqual(redirects, ["/bant/res/390417.html"]);
});
