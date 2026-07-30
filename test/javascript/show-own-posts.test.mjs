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
        <div class="post reply" id="reply_123">
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

test("ownership markers survive a changed-reply replacement", () => {
  const dom = setup(`
    <div class="thread" data-board="bant">
      <div class="post reply" id="reply_789">
        <span class="name">Anon <span class="own_post">(You)</span></span>
      </div>
    </div>
  `);
  const current = dom.window.document.getElementById("reply_789");
  const replacement = dom.window.document.createElement("div");
  replacement.className = "post reply";
  replacement.id = "reply_789";
  replacement.innerHTML = '<span class="name">Anon</span>';

  dom.window.EirinchanShowOwnPosts.prepareReplacement(current, replacement);

  assert.equal(replacement.classList.contains("you"), true);
  assert.equal(replacement.querySelector(".own_post").textContent, "(You)");
});

test("quote markers survive a changed-reply replacement", () => {
  const dom = setup(`
    <div class="thread" data-board="bant">
      <div class="post reply" id="reply_3">
        <span class="mentioned">
          <a data-highlight-reply="456">&gt;&gt;456</a>
          <span class="quote-annotations" data-quote-annotations>
            <small data-quote-annotation="you">(You)</small>
          </span>
        </span>
      </div>
    </div>
  `);
  dom.window.localStorage.own_posts = JSON.stringify({bant: ["456"]});
  const current = dom.window.document.getElementById("reply_3");
  const replacement = dom.window.document.createElement("div");
  replacement.className = "post reply";
  replacement.id = "reply_3";
  replacement.innerHTML = `
    <span class="mentioned">
      <a data-highlight-reply="456">&gt;&gt;456</a>
    </span>
  `;

  dom.window.EirinchanShowOwnPosts.prepareReplacement(current, replacement);

  assert.equal(
    replacement.querySelector('[data-quote-annotation="you"]').textContent,
    "(You)"
  );
});

test("server and client ownership reconciliation produces one canonically ordered marker", () => {
  const dom = setup(`
    <div class="thread" data-board="bant">
      <div class="post reply" id="reply_789">
        <div class="body">
          <a data-highlight-reply="456">&gt;&gt;456</a>
          <span class="quote-annotations" data-quote-annotations>
            <small data-quote-annotation="you">(You)</small>
            <small data-quote-annotation="cross-thread">(Cross-Thread)</small>
          </span>
        </div>
      </div>
    </div>
  `);
  dom.window.localStorage.own_posts = JSON.stringify({bant: ["456"]});
  const post = dom.window.document.getElementById("reply_789");

  dom.window.jQuery(dom.window.document).trigger("new_post", [post]);
  dom.window.jQuery(dom.window.document).trigger("fragment_init", [post]);

  const group = post.querySelector("[data-quote-annotations]");
  assert.equal(group.querySelectorAll('[data-quote-annotation="you"]').length, 1);
  assert.equal(group.textContent.replace(/\s+/g, " ").trim(), "(You) (Cross-Thread)");
});

test("legacy positional quote markers are migrated without duplication", () => {
  const dom = setup(`
    <div class="thread" data-board="bant">
      <div class="post reply" id="reply_790">
        <div class="body">
          <a data-highlight-reply="456">&gt;&gt;456</a>
          <small>(Cross-Thread)</small>
          <small>(You)</small>
        </div>
      </div>
    </div>
  `);
  dom.window.localStorage.own_posts = JSON.stringify({bant: ["456"]});
  const post = dom.window.document.getElementById("reply_790");

  dom.window.jQuery(dom.window.document).trigger("new_post", [post]);

  const group = post.querySelector("[data-quote-annotations]");
  assert.equal(group.querySelectorAll('[data-quote-annotation="you"]').length, 1);
  assert.equal(group.textContent.replace(/\s+/g, " ").trim(), "(You) (Cross-Thread)");
});
