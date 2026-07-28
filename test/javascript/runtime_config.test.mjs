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
  return {document, runtime: window.EirinchanRuntime};
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
});

test("inline image concurrency comes from runtime metadata and defaults to ten", () => {
  assert.equal(runtimeContext().runtime.inlineExpandMax, 10);
  assert.equal(
    runtimeContext({"eirinchan:inline-expand-max": "17"}).runtime.inlineExpandMax,
    17
  );
  assert.equal(runtimeContext({"eirinchan:inline-expand-max": "0"}).runtime.inlineExpandMax, 0);
});
