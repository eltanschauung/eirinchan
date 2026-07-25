import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const optionsSource = await readFile(path.join(projectRoot, "assets/js/options.js"), "utf8");
const postFilterSource = await readFile(path.join(projectRoot, "assets/js/post-filter.js"), "utf8");

function optionsShell() {
  return `
    <a id="options-link" href="#">[Options]</a>
    <div id="options_handler" style="display:none">
      <div id="options_background"></div>
      <div id="options_div">
        <button id="options_close" type="button">Close</button>
        <div id="options_tablist">
          <div id="options-tab-icon-general" class="options_tab_icon"><div>General</div></div>
          <div id="options-exit-tab" class="options_tab_icon"><div>Exit</div></div>
        </div>
        <div id="options-tab-general" class="options_tab" style="display:none">
          <h2>General</h2>
        </div>
      </div>
    </div>
  `;
}

function post({id, name = "Anonymous", subject = "", comment = "", flags = []}) {
  const flagMarkup = flags
    .map(
      ({code, label}) =>
        `<img class="flag" data-flag-code="${code}" alt="${label}" title="${label}">`
    )
    .join("");

  return `
    <div class="post ${id === 100 ? "op" : "reply"}" id="${id === 100 ? "op" : "reply"}_${id}">
      <p class="intro">
        <span class="subject">${subject}</span>
        <span class="name">${name}</span>
        ${flagMarkup}
        <a class="post_no" id="post_no_${id}">No.</a><a class="post_no">${id}</a>
      </p>
      <div class="body">${comment}</div>
      <div class="files">media</div>
    </div>
  `;
}

async function filterWindow({storedState, posts} = {}) {
  const dom = new JSDOM(
    `<!doctype html><html><head></head><body class="active-index">
      ${optionsShell()}
      <table><tr><th>Name</th></tr></table>
      <div class="thread" id="thread_100" data-board="bant">
        ${
          posts ||
          post({
            id: 100,
            flags: [
              {code: "first", label: "First"},
              {code: "zero", label: "Zero (Megaman X)"}
            ],
            comment: "opening post"
          })
        }
      </div>
    </body></html>`,
    {runScripts: "outside-only", url: "https://example.test/bant/"}
  );

  const {window} = dom;
  window._ = (value) => value;
  window.active_page = "index";
  window.board_name = "bant";
  if (storedState !== undefined) window.localStorage.setItem("postFilter", storedState);
  window.eval(jquerySource);
  window.jQuery.fx.off = true;
  window.eval(optionsSource);
  window.eval(postFilterSource);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded", {bubbles: true}));
  await new Promise((resolve) => window.setTimeout(resolve, 0));
  return window;
}

function addFilter(window, {type, value, regex = false}) {
  const control = window.document.getElementById("filter-control");
  control.querySelector("select").value = type;
  control.querySelector('input[type="text"]').value = value;
  control.querySelector('input[type="checkbox"]').checked = regex;
  control.querySelector("#set-filter").click();
}

test("incomplete stored state is repaired before filter controls are bound", async () => {
  const window = await filterWindow({storedState: "{}"});

  assert.ok(window.document.getElementById("options-tab-icon-filter"));
  addFilter(window, {type: "name", value: "Anonymous"});

  const stored = JSON.parse(window.localStorage.getItem("postFilter"));
  assert.deepEqual(stored.generalFilter, [
    {type: "name", value: "Anonymous", regex: false}
  ]);
  assert.equal(window.document.getElementById("op_100").classList.contains("post-filter-hidden"), true);
  window.close();
});

test("flag filters match every rendered flag by code or label", async () => {
  const window = await filterWindow();

  addFilter(window, {type: "flag", value: "zero"});
  assert.equal(window.document.getElementById("op_100").classList.contains("post-filter-hidden"), true);

  window.EirinchanPostFilter.clearAll();
  addFilter(window, {type: "flag", value: "Zero (Megaman X)"});
  assert.equal(window.document.getElementById("op_100").classList.contains("post-filter-hidden"), true);
  window.close();
});

test("invalid explicit regexes are rejected without disabling later filters", async () => {
  const window = await filterWindow();

  addFilter(window, {type: "com", value: "[", regex: true});

  assert.deepEqual(
    JSON.parse(window.localStorage.getItem("postFilter")).generalFilter,
    []
  );
  assert.match(window.document.getElementById("filter-status").textContent, /regular expression/i);

  addFilter(window, {type: "com", value: "opening", regex: false});
  assert.equal(window.document.getElementById("op_100").classList.contains("post-filter-hidden"), true);
  window.close();
});

test("literal punctuation is never interpreted as a regular expression", async () => {
  const window = await filterWindow({
    posts: post({
      id: 100,
      subject: "Release [candidate] (ready)",
      comment: "A+B is not AAB"
    })
  });

  addFilter(window, {type: "sub", value: "[candidate] (ready)"});
  assert.equal(window.document.getElementById("op_100").classList.contains("post-filter-hidden"), true);

  window.EirinchanPostFilter.clearAll();
  addFilter(window, {type: "com", value: "A+B"});
  assert.equal(window.document.getElementById("op_100").classList.contains("post-filter-hidden"), true);
  window.close();
});

test("filters are reapplied after updater fragments replace rendered posts", async () => {
  const window = await filterWindow();
  addFilter(window, {type: "flag", value: "zero"});

  const thread = window.document.getElementById("thread_100");
  thread.innerHTML = post({
    id: 100,
    flags: [{code: "zero", label: "Zero (Megaman X)"}],
    comment: "refreshed opening post"
  });

  const refreshed = window.document.getElementById("op_100");
  assert.equal(refreshed.classList.contains("post-filter-hidden"), false);

  window.jQuery(window.document).trigger("fragment_init", [thread]);
  window.jQuery(window.document).trigger("new_post", [refreshed]);
  await new Promise((resolve) => window.setTimeout(resolve, 0));

  assert.equal(refreshed.classList.contains("post-filter-hidden"), true);
  window.close();
});
