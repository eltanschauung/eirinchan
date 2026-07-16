import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const blotterSource = await readFile(path.join(projectRoot, "assets/js/blotter.js"), "utf8");

test("the first toggle opens a panel hidden by site CSS", () => {
  const dom = new JSDOM(
    `<!doctype html><html><head><style>.news-blotter { display: none; }</style></head><body>
      <div id="blotterContainer">
        <div class="news-button" aria-expanded="false">View News</div>
        <div class="news-blotter">News</div>
      </div>
    </body></html>`,
    {runScripts: "outside-only", url: "https://example.test/"}
  );

  dom.window.eval(blotterSource);
  dom.window.toggleNews();

  const panel = dom.window.document.querySelector(".news-blotter");
  const button = dom.window.document.querySelector(".news-button");
  assert.equal(panel.hidden, false);
  assert.equal(panel.style.display, "block");
  assert.equal(button.getAttribute("aria-expanded"), "true");
});
