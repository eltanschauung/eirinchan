import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquery = await readFile(path.join(root, "priv/static/js/jquery.min.js"), "utf8");
const ajax = await readFile(path.join(root, "assets/js/ajax.js"), "utf8");
const classic = await readFile(path.join(root, "assets/js/feedback-submitted.js"), "utf8");

for (const reply of [false, true]) test(`feedback success in a ${reply ? "reply" : "new-topic"} form alerts without post side effects`, async t => {
  const dom = new JSDOM(`<!doctype html><meta name="csrf-token" content="synthetic-token"><form data-post-form>
    <input name="board" value="test">${reply ? '<input name="thread" value="100">' : ''}
    <input name="name" value="Alice"><input name="email" value="alice@example.invalid"><input name="subject" value="Kept subject">
    <textarea name="body">/feedback Useful feedback</textarea><input type="submit" value="Post"></form>
    <div id="thread-refresh-target"><div class="post reply" id="reply_101">Existing reply</div></div>`, {url: "https://example.test/test/", runScripts: "outside-only"});
  t.after(() => dom.window.close());
  const w = dom.window; w.eval(jquery); w._ = text => text;
  const alerts = [], requests = [], after = [], newPosts = [], inputs = [];
  w.alert = text => alerts.push(text);
  w.EirinchanFrontend = {dispatchAjaxAfterPostSuccess: data => after.push(data), dispatchNewPost: node => newPosts.push(node)};
  w.jQuery.ajax = options => { requests.push(options); return {}; };
  w.eval(ajax);
  await new Promise(resolve => w.setTimeout(resolve, 10));
  const form = w.document.querySelector("form");
  form.querySelector("textarea").addEventListener("input", () => inputs.push(true));
  w.jQuery(form).trigger("submit");
  assert.equal(requests.length, 1);
  assert.equal(requests[0].data.get("body"), "/feedback Useful feedback");
  requests[0].success({status: "ok", feedback_submitted: true});
  assert.deepEqual(alerts, ["Feedback submitted!"]);
  assert.equal(form.elements.body.value, "");
  assert.equal(form.elements.name.value, "Alice");
  assert.equal(form.elements.subject.value, "Kept subject");
  assert.equal(form.querySelector('[type="submit"]').disabled, false);
  assert.equal(w.jQuery(form).data("ajax-posting"), undefined);
  assert.equal(w.document.querySelectorAll(".post.reply").length, 1);
  assert.deepEqual(after, []); assert.deepEqual(newPosts, []); assert.deepEqual(inputs, [true]);
  assert.equal(w.location.href, "https://example.test/test/");
});

test("classic confirmation uses an external script and alerts only once", t => {
  const dom = new JSDOM('<!doctype html><section data-feedback-submitted>Feedback submitted!</section>', {url: "https://example.test/test/", runScripts: "outside-only"});
  t.after(() => dom.window.close());
  const alerts = []; dom.window.alert = text => alerts.push(text);
  dom.window.eval(classic); dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));
  dom.window.eval(classic); dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));
  assert.deepEqual(alerts, ["Feedback submitted!"]);
});
