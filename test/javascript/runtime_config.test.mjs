import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import vm from "node:vm";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const source = await readFile(path.join(projectRoot, "assets/js/runtime-config.js"), "utf8");

function runtimeContext(meta = {}) {
  const document = {
    cookie: "",
    readyState: "complete",
    body: {},
    getElementsByTagName(tagName) {
      if (tagName !== "meta") return [];

      return Object.entries(meta).map(([name, content]) => ({
        getAttribute(attribute) {
          if (attribute === "name") return name;
          if (attribute === "content") return String(content);
          return null;
        }
      }));
    },
    querySelector() {
      return null;
    },
    addEventListener() {}
  };
  const window = {
    document,
    location: {
      href: "https://example.test/bant/res/1.html",
      origin: "https://example.test",
      protocol: "https:"
    },
    crypto: {
      getRandomValues(values) {
        values.fill(299);
        return values;
      }
    }
  };

  const context = vm.createContext({
    console,
    Date,
    document,
    Headers,
    Intl,
    Promise,
    URL,
    Uint32Array,
    window
  });
  vm.runInContext(source, context, {filename: "runtime-config.js"});
  return {document, runtime: window.EirinchanRuntime, window};
}

function memoryStorage(initial = {}) {
  const entries = new Map(Object.entries(initial));

  return {
    getItem(key) { return entries.has(key) ? entries.get(key) : null; },
    setItem(key, value) { entries.set(key, String(value)); },
    removeItem(key) { entries.delete(key); }
  };
}

test("same-origin URL restrictions enforce path boundaries", () => {
  const {runtime} = runtimeContext();

  assert.equal(runtime.sameOriginPath("/watcher/12?fresh=1", "/watcher"), "/watcher/12?fresh=1");
  assert.equal(runtime.sameOriginPath("/watcher-impersonator", "/watcher"), null);
  assert.equal(runtime.sameOriginPath("https://attacker.test/watcher", "/watcher"), null);
});

test("secure random strings support alphabets larger than one byte", () => {
  const {runtime} = runtimeContext();
  const alphabet = Array.from({length: 300}, (_, index) => String.fromCharCode(0x1000 + index)).join("");

  assert.equal(runtime.randomString(alphabet, 2), alphabet[299] + alphabet[299]);
});

test("malformed cookies fail closed", () => {
  const {document, runtime} = runtimeContext();
  document.cookie = "broken=%E0%A4%A";

  assert.equal(runtime.readCookie("broken", "fallback"), "fallback");
  assert.equal(runtime.writeCookie("bad cookie", "value"), false);

  assert.equal(runtime.writeCookie("valid", "value", {maxAge: 60}), true);
  assert.match(document.cookie, /^valid=value; path=\/; max-age=60; samesite=lax; secure$/);
});

test("concurrent post-success cookies clear every draft format", () => {
  const {document, runtime, window} = runtimeContext();
  const sessionStorage = memoryStorage({
    "eirinchan:draft:bant:new": JSON.stringify({body: "new thread"}),
    "eirinchan:draft:tech:42": JSON.stringify({body: "reply"}),
    body: JSON.stringify({
      "https://example.test/bant/index.html": "legacy new thread",
      "https://example.test/tech/res/42.html": "legacy reply",
      "https://example.test/keep": "keep"
    })
  });

  window.sessionStorage = sessionStorage;

  const first = encodeURIComponent(JSON.stringify({
    draft: "eirinchan:draft:bant:new",
    url: "https://example.test/bant/index.html"
  }));
  const second = encodeURIComponent(JSON.stringify({
    draft: "eirinchan:draft:tech:42",
    url: "https://example.test/tech/res/42.html"
  }));

  document.cookie = "eirinchan_posted_aaaaaaaaaaaaaaaa=" + first +
    "; eirinchan_posted_bbbbbbbbbbbbbbbb=" + second;

  assert.equal(runtime.consumePostSuccessCookies("eirinchan_posted"), 2);
  assert.equal(sessionStorage.getItem("eirinchan:draft:bant:new"), null);
  assert.equal(sessionStorage.getItem("eirinchan:draft:tech:42"), null);
  assert.deepEqual(JSON.parse(sessionStorage.getItem("body")), {
    "https://example.test/keep": "keep"
  });
});

test("inline image concurrency comes from runtime metadata and defaults to ten", () => {
  assert.equal(runtimeContext().runtime.inlineExpandMax, 10);
  assert.equal(
    runtimeContext({"eirinchan:inline-expand-max": "17"}).runtime.inlineExpandMax,
    17
  );
  assert.equal(runtimeContext({"eirinchan:inline-expand-max": "0"}).runtime.inlineExpandMax, 0);
});
