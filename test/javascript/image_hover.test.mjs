import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const imageHoverSource = await readFile(
  path.join(projectRoot, "assets/js/image-hover.js"),
  "utf8"
);

async function imageHoverWindow() {
  const dom = new JSDOM(
    `<!doctype html><html><body>
      <div class="files">
        <div>
          <p class="fileinfo"><a href="/bant/src/image.png">image.png</a></p>
          <a href="/bant/src/image.png" data-inline-expandable="true">
            <img id="image-thumbnail" class="post-image" src="/bant/thumb/image.png">
          </a>
        </div>
        <div>
          <p class="fileinfo"><a href="/bant/src/audio.mp3">audio.mp3</a></p>
          <a href="/bant/src/audio.mp3" class="file">
            <img id="audio-thumbnail" class="post-image" src="/static/mp3.png">
          </a>
        </div>
      </div>
    </body></html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/res/1.html"}
  );

  const {window} = dom;
  window.active_page = "thread";
  window.eval(jquerySource);
  window.eval(imageHoverSource);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded", {bubbles: true}));
  await new Promise((resolve) => window.setTimeout(resolve, 0));
  return window;
}

test("image hover binds only to inline-expandable thumbnails", async () => {
  const window = await imageHoverWindow();
  const imageThumbnail = window.document.getElementById("image-thumbnail");
  const audioThumbnail = window.document.getElementById("audio-thumbnail");

  assert.equal(imageThumbnail.dataset.imageHoverBound, "true");
  assert.equal(audioThumbnail.dataset.imageHoverBound, undefined);

  audioThumbnail.dispatchEvent(new window.MouseEvent("mousemove", {bubbles: true}));
  assert.equal(window.document.getElementById("chx_hoverImage"), null);

  imageThumbnail.dispatchEvent(new window.MouseEvent("mousemove", {bubbles: true}));
  assert.equal(
    window.document.getElementById("chx_hoverImage").getAttribute("src"),
    "/bant/src/image.png"
  );

  window.close();
});
