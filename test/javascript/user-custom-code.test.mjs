import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const userJsSource = await readFile(path.join(projectRoot, "assets/js/options/user-js.js"), "utf8");
const userCssSource = await readFile(path.join(projectRoot, "assets/js/options/user-css.js"), "utf8");

function customCodeWindow() {
  const dom = new JSDOM("<!doctype html><html><head></head><body></body></html>", {
    runScripts: "outside-only",
    url: "https://example.test/bant/index.html"
  });
  const {window} = dom;

  window._ = (value) => value;
  window.allow_user_custom_code = true;
  window.eval(jquerySource);
  window.Options = {
    add_tab() {
      const content = window.document.createElement("div");
      window.document.body.appendChild(content);
      return {content};
    }
  };
  window.EirinchanRuntime = {
    onReady(callback) {
      callback();
    },
    readStorage(_scope, key, fallback) {
      return window.localStorage.getItem(key) || fallback;
    },
    writeStorage(_scope, key, value) {
      window.localStorage.setItem(key, value);
    },
    sameOriginUrl(value) {
      const url = new URL(value, window.location.href);
      return url.origin === window.location.origin ? url : null;
    }
  };

  return window;
}

test("stored user JavaScript runs from a CSP-compatible blob URL", () => {
  const window = customCodeWindow();
  let blobParts;
  let createdBlob;

  window.Blob = class RecordingBlob {
    constructor(parts, options) {
      blobParts = parts;
      this.type = options.type;
      createdBlob = this;
    }
  };
  window.URL.createObjectURL = (blob) => {
    assert.equal(blob, createdBlob);
    return "blob:https://example.test/user-code";
  };
  window.URL.revokeObjectURL = () => {};
  window.localStorage.setItem("user_js", "\uFEFFwindow.customRan = true;\u0000");

  window.eval(userJsSource);

  const script = window.document.querySelector("script.user-js");
  assert.ok(script);
  assert.equal(script.src, "blob:https://example.test/user-code");
  assert.equal(createdBlob.type, "text/javascript");
  assert.equal(blobParts.join("").includes("\u0000"), false);
  assert.match(blobParts.join(""), /window\.customRan = true/);
});

test("stored user CSS is sanitized and applied as text", () => {
  const window = customCodeWindow();
  window.localStorage.setItem("user_css", "\uFEFFbody { color: red; }\u0000");

  window.eval(userCssSource);

  const style = window.document.querySelector("style.user-css");
  assert.ok(style);
  assert.equal(style.textContent, "body { color: red; }");
});

test("the administrative kill switch prevents custom-code controls and execution", () => {
  const window = customCodeWindow();
  window.allow_user_custom_code = false;
  window.localStorage.setItem("user_js", "window.customRan = true;");
  window.localStorage.setItem("user_css", "body { color: red; }");

  window.eval(userJsSource);
  window.eval(userCssSource);

  assert.equal(window.document.querySelector("script.user-js"), null);
  assert.equal(window.document.querySelector("style.user-css"), null);
  assert.equal(window.document.body.children.length, 0);
});
