import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const source = await readFile(path.join(projectRoot, "priv/static/js/show-own-posts.js"), "utf8");

function setup(html = "") {
  const dom = new JSDOM(`<!doctype html><html><body>${html}</body></html>`, {
    runScripts: "outside-only",
    url: "https://example.test/bant/"
  });

  dom.window._ = (value) => value;
  dom.window.eval(jquerySource);
  dom.window.jQuery.ajax = () => ({done: () => ({})});
  dom.window.eval(source);
  return dom;
}

test("ownership markers survive an auto-updater fragment replacement", () => {
  const dom = setup(`
    <div id="current">
      <div class="thread" data-board="bant">
        <div class="post reply you" id="reply_123">
          <span class="name">Anon <span class="own_post">(You)</span></span>
        </div>
      </div>
    </div>
  `);
  const replacement = dom.window.document.createElement("div");
  replacement.innerHTML = `
    <div class="thread" data-board="bant">
      <div class="post reply" id="reply_123"><span class="name">Anon</span></div>
    </div>
  `;

  dom.window.EirinchanShowOwnPosts.prepareReplacement(
    dom.window.document.getElementById("current"),
    replacement
  );

  assert.equal(replacement.querySelector("#reply_123").classList.contains("you"), true);
  assert.equal(replacement.querySelector("#reply_123 .own_post").textContent, "(You)");
});

test("post success stores ownership using the submitted form board", () => {
  const dom = setup();
  const form = dom.window.document.createElement("form");
  form.innerHTML = '<input type="hidden" name="board" value="bant">';

  dom.window.jQuery(dom.window.document).trigger("ajax_after_post", [{id: 456}, form]);

  assert.deepEqual(JSON.parse(dom.window.localStorage.own_posts), {bant: ["456"]});
});
