import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const jquerySource = await readFile(path.join(projectRoot, "priv/static/js/jquery.min.js"), "utf8");
const optionsSource = await readFile(path.join(projectRoot, "assets/js/options.js"), "utf8");
const hideThreadsSource = await readFile(
  path.join(projectRoot, "priv/static/js/hide-threads.js"),
  "utf8"
);
const postMenuSource = await readFile(path.join(projectRoot, "priv/static/js/post-menu.js"), "utf8");
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

function post({
  id,
  name = "Anonymous",
  trip = "",
  uid = "",
  subject = "",
  comment = "",
  flags = []
}) {
  const flagMarkup = flags
    .map(
      ({code, label, filterLabel = label, aliases = []}) =>
        `<img class="flag" data-flag-code="${code}" data-flag-filter-label="${filterLabel}" data-flag-aliases='${JSON.stringify(aliases)}' alt="${label}" title="${label}">`
    )
    .join("");

  return `
    <div class="post ${id === 100 ? "op" : "reply"}" id="${id === 100 ? "op" : "reply"}_${id}">
      <p class="intro">
        <span class="subject">${subject}</span>
        <span class="name">${name}</span>
        ${trip ? `<span class="trip">${trip}</span>` : ""}
        ${uid ? `<span class="poster_id">${uid}</span>` : ""}
        ${flagMarkup}
        <a class="post_no" id="post_no_${id}">No.</a><a class="post_no">${id}</a>
        ${id === 100 ? '<button type="button" class="hide-thread-link js-link-button" title="Hide thread">[–]</button>' : ""}
        <button type="button" class="post-btn">▶</button>
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
        <div class="files op-media">opening media</div>
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
  window.eval(hideThreadsSource);
  window.eval(postMenuSource);
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

test("country flag filters accept both two-letter codes and English names", async () => {
  const window = await filterWindow({
    posts: post({
      id: 100,
      flags: [
        {
          code: "tr",
          label: "Türkiye",
          aliases: ["tr", "tur", "Turkey", "Türkiye", "Republic of Türkiye"]
        }
      ]
    })
  });

  addFilter(window, {type: "flag", value: "tr"});
  assert.equal(window.document.getElementById("op_100").classList.contains("post-filter-hidden"), true);

  window.EirinchanPostFilter.clearAll();
  addFilter(window, {type: "flag", value: "turkey"});
  assert.equal(window.document.getElementById("op_100").classList.contains("post-filter-hidden"), true);
  window.close();
});

test("flag filter post menu keeps its label and uses the canonical country name", async () => {
  const window = await filterWindow({
    posts: post({
      id: 100,
      flags: [
        {
          code: "tr",
          label: "Türkiye",
          filterLabel: "Turkey",
          aliases: ["tr", "tur", "Turkey", "Türkiye", "Republic of Türkiye"]
        }
      ]
    })
  });

  window.document.querySelector(".post-btn").click();

  const flagMenu = window.document.getElementById("filter-add-flag");
  const directLabel = Array.from(flagMenu.childNodes)
    .filter((node) => node.nodeType === window.Node.TEXT_NODE)
    .map((node) => node.nodeValue.trim())
    .join(" ");

  assert.equal(directLabel, "Flag");
  assert.equal(flagMenu.querySelector("ul li").textContent, "Filter Turkey");
  window.close();
});

test("adding any post-menu filter closes the menu", async () => {
  const window = await filterWindow({
    posts: post({
      id: 100,
      trip: "!example",
      uid: "example-id",
      flags: [{code: "tr", label: "Türkiye", filterLabel: "Turkey"}]
    })
  });

  for (const selector of [
    "#filter-add-name",
    "#filter-add-trip",
    "#filter-add-id",
    "#filter-add-flag ul li"
  ]) {
    window.document.querySelector(".post-btn").click();
    const menu = window.document.getElementById("post-menu-root");
    assert.equal(menu.hidden, false, `${selector} menu opens`);

    menu.querySelector(selector).click();

    assert.equal(menu.hidden, true, `${selector} closes the menu`);
    assert.equal(window.document.querySelector(".post-btn-open"), null);
    window.EirinchanPostFilter.clearAll();
  }

  window.close();
});

test("name and flag filters use the normal non-persistent thread collapse", async () => {
  const window = await filterWindow();
  const thread = window.document.getElementById("thread_100");

  addFilter(window, {type: "name", value: "Anonymous"});

  assert.equal(thread.classList.contains("thread-filter-hidden"), true);
  assert.equal(thread.classList.contains("thread-hidden"), true);
  assert.ok(thread.querySelector(":scope > .thread-hidden-marker"));
  assert.deepEqual(JSON.parse(window.localStorage.getItem("hiddenthreads")), {});

  window.EirinchanPostFilter.clearAll();
  assert.equal(thread.classList.contains("thread-hidden"), false);
  assert.equal(thread.querySelector(":scope > .thread-hidden-marker"), null);

  addFilter(window, {type: "flag", value: "zero"});
  assert.equal(thread.classList.contains("thread-hidden"), true);
  assert.ok(thread.querySelector(":scope > .thread-hidden-marker"));
  assert.deepEqual(JSON.parse(window.localStorage.getItem("hiddenthreads")), {});
  window.close();
});

test("removing a filter preserves a thread that was also manually hidden", async () => {
  const window = await filterWindow();
  const thread = window.document.getElementById("thread_100");

  window.document.querySelector(".hide-thread-link").click();
  addFilter(window, {type: "name", value: "Anonymous"});
  window.document.querySelector("#filter-list .del-btn").click();

  assert.equal(thread.classList.contains("thread-filter-hidden"), false);
  assert.equal(thread.classList.contains("thread-hidden"), true);
  assert.ok(JSON.parse(window.localStorage.getItem("hiddenthreads")).bant["100"]);
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
