import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import {JSDOM} from "jsdom";
const jquery = await readFile(new URL("../../priv/static/js/jquery.min.js", import.meta.url), "utf8");
const ajax = await readFile(new URL("../../assets/js/ajax.js", import.meta.url), "utf8");
const classic = await readFile(new URL("../../assets/js/upload-wait.js", import.meta.url), "utf8");
const message = "You've been authenticated for under 3 hours; image uploads disabled.";

test("AJAX upload age rejection alerts exactly and preserves the draft without fake success", async t => {
  const dom = new JSDOM('<!doctype html><meta name="csrf-token" content="synthetic-token"><form data-post-form><input name="board" value="test"><textarea name="body">My draft</textarea><input type="submit" value="Post"></form>', {url: "https://example.test/test/", runScripts: "outside-only"});
  t.after(() => dom.window.close());
  const w = dom.window, alerts = [], requests = [], posted = [];
  w.eval(jquery); w._ = value => value; w.alert = value => alerts.push(value);
  w.EirinchanFrontend = {dispatchNewPost: value => posted.push(value)};
  w.jQuery.ajax = options => {requests.push(options); return {};};
  w.eval(ajax); await new Promise(resolve => w.jQuery(resolve));
  w.jQuery("form").trigger("submit");
  requests[0].error({status: 403, responseJSON: {error_code: "ipaccess_time", error: message}});
  assert.deepEqual(alerts, [message]); assert.deepEqual(posted, []);
  assert.equal(w.document.querySelector("textarea").value, "My draft");
});

test("classic upload rejection alerts once without inline script execution", t => {
  const dom = new JSDOM('<!doctype html><section data-upload-wait-message=""></section>', {runScripts: "outside-only"});
  t.after(() => dom.window.close());
  const alerts = []; dom.window.alert = value => alerts.push(value);
  dom.window.document.querySelector("section").setAttribute("data-upload-wait-message", message);
  dom.window.eval(classic); dom.window.eval(classic);
  assert.deepEqual(alerts, [message]);
});
