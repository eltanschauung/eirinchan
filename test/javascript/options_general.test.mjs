import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const generalSource = await readFile(path.join(projectRoot, "assets/js/options/general.js"), "utf8");

async function generalOptionsWindow(runtime = {}) {
  const dom = new JSDOM("<!doctype html><html><body></body></html>", {
    runScripts: "outside-only",
    url: "https://example.test/bant/"
  });
  const {window} = dom;
  const content = window.document.createElement("div");

  window.document.body.append(content);
  window._ = (value) => value;
  window.confirm = () => true;
  window.EirinchanRuntime = {
    requestJson() {
      return {
        catch() {
          return this;
        },
        finally() {
          return this;
        }
      };
    },
    ...runtime
  };
  window.Options = {
    add_tab() {
      return {content};
    }
  };
  window.eval(jquerySource);
  window.eval(generalSource);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded", {bubbles: true}));
  await new Promise((resolve) => window.setTimeout(resolve, 0));
  return window;
}

test("erasing options storage removes all theme cookies and browser storage", async () => {
  const removed = [];
  const window = await generalOptionsWindow({
    removeCookie(name, options) {
      removed.push([name, options]);
    }
  });

  window.localStorage.setItem("selected", "tomorrow");
  window.sessionStorage.setItem("temporary", "value");
  window.document.getElementById("options-storage-erase").click();

  assert.equal(window.localStorage.length, 0);
  assert.equal(window.sessionStorage.length, 0);
  assert.deepEqual(
    removed.map(([name, options]) => [name, options.path]),
    [
      ["theme", "/"],
      ["board_themes", "/"],
      ["eirinchan_color_scheme", "/"]
    ]
  );
});

test("erasing options storage expires theme cookies without the runtime helper", async () => {
  const window = await generalOptionsWindow();

  window.document.cookie = "theme=tomorrow; path=/";
  window.document.cookie = "board_themes=%7B%7D; path=/";
  window.document.cookie = "eirinchan_color_scheme=dark; path=/";
  window.document.getElementById("options-storage-erase").click();

  assert.equal(window.document.cookie, "");
});
