import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const highlightingSource = await readFile(
  path.join(projectRoot, "assets/js/poster-id-highlighting.js"),
  "utf8"
);

function post(id, posterId, kind = "reply") {
  return `
    <div class="post ${kind}" id="${kind === "op" ? "op" : "reply"}_${id}">
      <p class="intro">
        <input class="delete" type="checkbox" id="delete_${id}">
        <label for="delete_${id}">
          Anonymous
          <span
            id="badge_${id}"
            class="poster_id standard_poster_id"
            data-poster-id="${posterId}"
            role="button"
            tabindex="0"
            aria-pressed="false"
          >${posterId}</span>
        </label>
      </p>
    </div>
  `;
}

async function setup(activePage = "index") {
  const dom = new JSDOM(
    `<!doctype html><html><body class="active-${activePage}">
      <div class="thread" id="thread_100" data-board="bant" data-thread-id="100">
        ${post(100, "same-id", "op")}
        ${post(101, "same-id")}
        ${post(102, "other-id")}
      </div>
      <div class="thread" id="thread_200" data-board="bant" data-thread-id="200">
        ${post(200, "same-id", "op")}
      </div>
    </body></html>`,
    {
      runScripts: "outside-only",
      url:
        activePage === "thread"
          ? "https://example.test/bant/res/100.html"
          : "https://example.test/bant/"
    }
  );

  const {window} = dom;
  window.active_page = activePage;
  window.board_name = "bant";
  window.eval(jquerySource);
  window.eval(highlightingSource);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded", {bubbles: true}));
  await new Promise((resolve) => window.setTimeout(resolve, 0));
  return window;
}

test("thread-page badges show how many posts clicking the ID would highlight", async () => {
  const window = await setup("thread");

  assert.equal(window.document.getElementById("badge_100").title, "Posts by this ID: 2");
  assert.equal(window.document.getElementById("badge_101").title, "Posts by this ID: 2");
  assert.equal(window.document.getElementById("badge_102").title, "Posts by this ID: 1");
  assert.equal(window.document.getElementById("badge_200").title, "Posts by this ID: 1");
  window.close();
});

test("index-page badges do not receive the thread-only post count title", async () => {
  const window = await setup("index");

  assert.equal(window.document.getElementById("badge_100").hasAttribute("title"), false);
  assert.equal(window.document.getElementById("badge_102").hasAttribute("title"), false);
  window.close();
});

function assertHighlighted(window, ids) {
  const expected = new Set(ids.map(String));

  window.document.querySelectorAll(".post").forEach((postElement) => {
    const id = postElement.id.replace(/^(?:op|reply)_/, "");
    const selected = expected.has(id);
    assert.equal(postElement.classList.contains("poster-id-highlighted"), selected);
    assert.equal(postElement.classList.contains("highlighted"), selected);
  });
}

test("clicking a poster ID highlights exact matches only within its thread", async () => {
  const window = await setup();
  const badge = window.document.getElementById("badge_100");

  badge.click();

  assertHighlighted(window, [100, 101]);
  assert.equal(window.document.getElementById("delete_100").checked, false);
  assert.equal(window.document.getElementById("delete_101").checked, false);
  assert.equal(window.document.getElementById("badge_100").getAttribute("aria-pressed"), "true");
  assert.equal(window.document.getElementById("badge_101").getAttribute("aria-pressed"), "true");
  assert.equal(window.document.getElementById("badge_200").getAttribute("aria-pressed"), "false");

  badge.click();
  assertHighlighted(window, []);
  window.close();
});

test("keyboard activation toggles and replaces a thread's selected ID", async () => {
  const window = await setup();
  const sameBadge = window.document.getElementById("badge_101");
  const otherBadge = window.document.getElementById("badge_102");

  sameBadge.dispatchEvent(
    new window.KeyboardEvent("keydown", {key: "Enter", bubbles: true, cancelable: true})
  );
  assertHighlighted(window, [100, 101]);

  otherBadge.dispatchEvent(
    new window.KeyboardEvent("keydown", {key: " ", bubbles: true, cancelable: true})
  );
  assertHighlighted(window, [102]);
  assert.equal(sameBadge.getAttribute("aria-pressed"), "false");
  assert.equal(otherBadge.getAttribute("aria-pressed"), "true");
  assert.equal(window.document.getElementById("delete_102").checked, false);
  window.close();
});

test("new replies inherit the active poster-ID highlight", async () => {
  const window = await setup("thread");
  const thread = window.document.getElementById("thread_100");

  window.document.getElementById("badge_100").click();
  thread.insertAdjacentHTML("beforeend", post(103, "same-id"));
  const reply = window.document.getElementById("reply_103");
  window.jQuery(window.document).trigger("new_post", reply);

  assert.equal(reply.classList.contains("poster-id-highlighted"), true);
  assert.equal(reply.classList.contains("highlighted"), true);
  assert.equal(window.document.getElementById("badge_103").getAttribute("aria-pressed"), "true");
  assert.equal(window.document.getElementById("badge_100").title, "Posts by this ID: 3");
  assert.equal(window.document.getElementById("badge_101").title, "Posts by this ID: 3");
  assert.equal(window.document.getElementById("badge_103").title, "Posts by this ID: 3");
  window.close();
});

test("thread replacement reapplies selection by board and thread ID", async () => {
  const window = await setup();
  const current = window.document.getElementById("thread_100");

  window.document.getElementById("badge_100").click();
  current.insertAdjacentHTML(
    "afterend",
    `<div class="thread" id="replacement" data-board="bant" data-thread-id="100">
      ${post(110, "same-id", "op")}
      ${post(111, "other-id")}
    </div>`
  );
  const replacement = window.document.getElementById("replacement");
  current.remove();
  window.jQuery(window.document).trigger("fragment_init", replacement);

  assert.equal(window.document.getElementById("op_110").classList.contains("highlighted"), true);
  assert.equal(window.document.getElementById("reply_111").classList.contains("highlighted"), false);
  window.close();
});
