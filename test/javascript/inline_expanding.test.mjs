import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(
  path.join(projectRoot, "priv/static/js/jquery.min.js"),
  "utf8"
);
const inlineExpandingSource = await readFile(
  path.join(projectRoot, "assets/js/inline-expanding.js"),
  "utf8"
);

async function inlineExpandingWindow(maxImages) {
  const links = [1, 2, 3]
    .map(
      (id) =>
        `<a id="image-${id}" href="/src/${id}.png" data-inline-expandable="true">` +
        `<img class="post-image" src="/thumb/${id}.png"></a>`
    )
    .join("");

  const dom = new JSDOM(
    `<!doctype html><html><body><div id="thread_1"><div class="post">${links}</div></div></body></html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/res/1.html"}
  );
  const {window} = dom;

  window.EirinchanRuntime = {inlineExpandMax: maxImages};
  Object.defineProperty(window.HTMLImageElement.prototype, "naturalWidth", {
    configurable: true,
    get() {
      return 100;
    }
  });

  window.eval(jquerySource);
  window.eval(inlineExpandingSource);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded", {bubbles: true}));
  await new Promise((resolve) => window.setTimeout(resolve, 0));
  return window;
}

function click(window, id) {
  window.document.getElementById(id).dispatchEvent(
    new window.MouseEvent("click", {
      bubbles: true,
      cancelable: true,
      button: 0
    })
  );
}

test("server concurrency queues full image downloads without adding an option", async () => {
  const window = await inlineExpandingWindow(2);

  click(window, "image-1");
  click(window, "image-2");
  click(window, "image-3");

  assert.ok(window.document.querySelector("#image-1 .full-image").hasAttribute("src"));
  assert.ok(window.document.querySelector("#image-2 .full-image").hasAttribute("src"));
  assert.equal(window.document.querySelector("#image-3 .full-image").hasAttribute("src"), false);
  assert.equal(window.document.getElementById("inline-expand-max"), null);

  window.document
    .querySelector("#image-1 .full-image")
    .dispatchEvent(new window.Event("load"));
  await new Promise((resolve) => window.setTimeout(resolve, 0));

  assert.ok(window.document.querySelector("#image-3 .full-image").hasAttribute("src"));
});

test("zero disables the concurrency cap", async () => {
  const window = await inlineExpandingWindow(0);

  click(window, "image-1");
  click(window, "image-2");
  click(window, "image-3");

  assert.equal(window.document.querySelectorAll(".full-image[src]").length, 3);
});
