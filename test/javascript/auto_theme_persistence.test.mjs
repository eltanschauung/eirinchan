import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const mainSource = await readFile(path.join(projectRoot, "priv/static/main.js"), "utf8");

async function autoThemeWindow() {
  const dom = new JSDOM(
    `<!doctype html><html><head>
      <link id="stylesheet" rel="stylesheet" href="/stylesheets/tomorrow.css">
    </head><body data-stylesheet="yotsuba.css"></body></html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/"}
  );
  const {window} = dom;

  window.EirinchanRuntime = {};
  window.board_name = "bant";
  window.selectedstyle = "Tomorrow";
  window.stylesheets_board = true;
  window.styles = {
    Yotsuba: {name: "yotsuba", uri: "/stylesheets/yotsuba.css"},
    Tomorrow: {name: "tomorrow", uri: "/stylesheets/tomorrow.css"}
  };
  window.styleThemeNames = {Yotsuba: "yotsuba", Tomorrow: "tomorrow"};
  window.__eirinchanAutoTheme = {
    href: "/stylesheets/tomorrow.css",
    label: "Tomorrow",
    name: "tomorrow"
  };

  window.eval(mainSource);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded", {bubbles: true}));
  await new Promise((resolve) => window.setTimeout(resolve, 0));
  return window;
}

test("an automatic dark default is not saved as an explicit theme", async () => {
  const window = await autoThemeWindow();

  assert.equal(window.localStorage.getItem("stylesheet"), null);
  assert.equal(window.localStorage.getItem("board_stylesheets"), null);
  assert.equal(window.document.cookie.includes("theme="), false);
  assert.equal(window.document.cookie.includes("board_themes="), false);
});

test("a later explicit style selection is still persisted", async () => {
  const window = await autoThemeWindow();

  window.changeStyle("Yotsuba");

  assert.equal(window.localStorage.getItem("stylesheet"), "yotsuba");
  assert.equal(window.localStorage.getItem("board_stylesheets"), '{"bant":"yotsuba"}');
  assert.match(window.document.cookie, /(?:^|; )theme=yotsuba(?:;|$)/);
  assert.match(window.document.cookie, /(?:^|; )board_themes=/);
});

test("a non-board page does not persist its server fallback", async () => {
  const window = await autoThemeWindow();

  delete window.__eirinchanAutoTheme;
  delete window.board_name;
  window.localStorage.clear();
  window.document.cookie = "theme=; Max-Age=0; path=/";
  window.document.cookie = "board_themes=; Max-Age=0; path=/";
  window.selectedstyle = "Yotsuba";
  window.document.body.dataset.stylesheet = "yotsuba.css";
  window.ready();

  assert.equal(window.localStorage.getItem("stylesheet"), null);
  assert.equal(window.localStorage.getItem("board_stylesheets"), null);
  assert.equal(window.document.cookie.includes("theme="), false);
  assert.equal(window.document.cookie.includes("board_themes="), false);
});
