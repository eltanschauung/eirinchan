import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const postHoverSource = await readFile(
  path.join(projectRoot, "assets/js/post-hover.js"),
  "utf8"
);

function fetchedThread({board, id}) {
  return `
    <!doctype html>
    <html>
      <body>
        <div class="thread" id="thread_${id}" data-board="${board}">
          <a id="${id}" class="post_anchor"></a>
          <div class="files">
            <div class="file">
              <img class="post-image" data-media-owner="op" src="/${board}/thumb/${id}.png">
            </div>
          </div>
          <div class="post op" id="op_${id}">
            <p class="intro">Opening post ${id}</p>
            <div class="body">Opening body</div>
          </div>
          <div class="post reply" id="reply_${Number(id) + 1}">
            <div class="files">
              <img
                class="post-image"
                data-media-owner="reply"
                src="/${board}/thumb/${Number(id) + 1}.png"
              >
            </div>
            <div class="body">Reply body</div>
          </div>
        </div>
      </body>
    </html>
  `;
}

async function hoverPreview({quote, response}) {
  const dom = new JSDOM(
    `<!doctype html>
      <html>
        <body>
          <form name="postcontrols"></form>
          <form name="post"><input name="board" value="bant"></form>
          <div class="thread" id="thread_392885" data-board="bant">
            <div class="post reply" id="reply_392885">
              <div class="body">${quote}</div>
            </div>
          </div>
        </body>
      </html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/res/392885.html"}
  );

  const {window} = dom;
  window.eval(jquerySource);
  window.onReady = (callback) => callback();
  window.__ajaxCalls = 0;
  window.jQuery.ajax = ({success}) => {
    window.__ajaxCalls += 1;
    success(response);
  };
  window.eval(postHoverSource);

  const link = window.document.getElementById("quote");
  window.jQuery(link).trigger(
    window.jQuery.Event("mouseenter", {pageX: 100, pageY: 100})
  );
  await new Promise((resolve) => window.setTimeout(resolve, 0));
  return window;
}

test("cross-board opening-post hover includes its files", async () => {
  const window = await hoverPreview({
    quote:
      '<a id="quote" href="/archive/res/6759.html#6759">&gt;&gt;&gt;/archive/6759</a>',
    response: fetchedThread({board: "archive", id: "6759"})
  });

  const preview = window.document.getElementById("post-hover-6759");
  assert.equal(window.__ajaxCalls, 1, "hover should fetch the target thread");
  assert.ok(preview, "preview should be created");
  assert.ok(
    preview.querySelector('.files .post-image[data-media-owner="op"]'),
    "preview should retain OP media"
  );

  const quote = window.document.getElementById("quote");
  window.jQuery(quote).trigger("mouseleave");
  window.jQuery(quote).trigger(
    window.jQuery.Event("mouseenter", {pageX: 100, pageY: 100})
  );

  assert.equal(window.__ajaxCalls, 1, "cached hovers should not refetch the thread");
  assert.ok(
    window.document.querySelector(
      '#post-hover-6759 .files .post-image[data-media-owner="op"]'
    )
  );
  window.close();
});

test("same-board cross-thread opening-post hover includes its files", async () => {
  const window = await hoverPreview({
    quote:
      '<a id="quote" data-highlight-reply="392331" href="/bant/res/392331.html#392331">&gt;&gt;392331</a>',
    response: fetchedThread({board: "bant", id: "392331"})
  });

  const preview = window.document.getElementById("post-hover-392331");
  assert.equal(window.__ajaxCalls, 1, "hover should fetch the target thread");
  assert.ok(preview, "preview should be created");
  assert.ok(
    preview.querySelector('.files .post-image[data-media-owner="op"]'),
    "preview should retain OP media"
  );
  window.close();
});

test("fetched reply hover keeps reply media without borrowing OP media", async () => {
  const window = await hoverPreview({
    quote:
      '<a id="quote" href="/archive/res/6759.html#6760">&gt;&gt;&gt;/archive/6760</a>',
    response: fetchedThread({board: "archive", id: "6759"})
  });

  const preview = window.document.getElementById("post-hover-6760");
  assert.ok(preview, "reply preview should be created");
  assert.ok(preview.querySelector('.post-image[data-media-owner="reply"]'));
  assert.equal(preview.querySelector('[data-media-owner="op"]'), null);
  window.close();
});

test("quote hover does not clear a poster-ID highlight", async () => {
  const window = await hoverPreview({
    quote:
      '<a id="quote" data-highlight-reply="392885" href="/bant/res/392885.html#392885">&gt;&gt;392885</a>',
    response: ""
  });

  const post = window.document.getElementById("reply_392885");
  const quote = window.document.getElementById("quote");
  post.classList.add("poster-id-highlighted", "highlighted");

  window.jQuery(quote).trigger("mouseleave");
  assert.equal(post.classList.contains("highlighted"), true);
  window.close();
});
