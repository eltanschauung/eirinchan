import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {JSDOM} from "jsdom";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const picker = await readFile(path.join(root, "assets/js/flag-picker.js"), "utf8");
const preference = await readFile(path.join(root, "assets/js/user-flag-preference.js"), "utf8");
const legacy = await readFile(path.join(root, "priv/static/main.js"), "utf8");
const flag = (code, alt) => ({src: `/flags/compiled/${code}.png`, alt});

function setup(t, {stored, cookie, value = "country", multiple = true, base = [], withLegacy = false} = {}) {
  const dom = new JSDOM(`<!doctype html><html><head></head><body>
    <div data-flag-page data-flag-page-initialized="true">
      <div class="image-canvas"><img data-flag-value="meiling" alt="meiling"><img data-flag-value="tenshi" alt="tenshi"></div>
      <input name="user_flag" id="user_flag" maxlength="300">
      <button id="applyButton" type="button">Apply</button><button id="clearButton" type="button">Clear</button>
      <div data-flag-preview><p class="intro"><span class="name">Anonymous</span><span data-flag-preview-flags></span></p>
        <p data-flag-preview-error hidden>Enter valid flag names to preview.</p></div>
    </div></body></html>`, {url: "https://example.test/flags", runScripts: "outside-only"});
  t.after(() => dom.window.close());
  const w = dom.window, d = w.document;
  const options = {flags: {country: [flag("ca", "Canada")], us: [flag("us", "United States")],
    meiling: [flag("meiling", "Meiling")], tenshi: [flag("tenshi", "Tenshi")]},
    fallback: [flag("us", "United States")], base, multiple, style: "width:20px;height:14px;"};
  for (const [name, content] of Object.entries({"user-flag-mode": multiple ? "multi" : "single",
    "user-flag-allowed-values": JSON.stringify(Object.keys(options.flags))})) {
    const meta = d.createElement("meta"); meta.name = "eirinchan:" + name; meta.content = content; d.head.appendChild(meta);
  }
  d.querySelector("[data-flag-preview]").dataset.flagPreviewOptions = JSON.stringify(options);
  const field = d.getElementById("user_flag"); field.value = value;
  if (stored !== undefined) w.localStorage.setItem("flag_", stored);
  if (cookie !== undefined) d.cookie = `eirinchan_user_flag=${encodeURIComponent(cookie)}; path=/`;
  w.eval(preference);
  if (withLegacy) w.eval(legacy);
  w.eval(picker);
  d.dispatchEvent(new w.Event("DOMContentLoaded"));
  const type = value => { field.value = value; field.dispatchEvent(new w.Event("input", {bubbles: true})); };
  const click = selector => d.querySelector(selector).click();
  const images = () => [...d.querySelectorAll("[data-flag-preview-flags] img")];
  return {w, d, field, type, click, images, options};
}

test("gallery clicks assemble ordered post-style flags and persist through the preference authority", t => {
  const h = setup(t);
  h.click('[data-flag-value="meiling"]'); h.click('[data-flag-value="tenshi"]');
  assert.equal(h.field.value, "country,meiling,tenshi");
  assert.deepEqual(h.images().map(image => image.alt), ["Canada", "Meiling", "Tenshi"]);
  assert.equal(h.w.EirinchanUserFlagPreference.get(), h.field.value);
  assert.equal(h.w.localStorage.getItem("flag_"), h.field.value);
  assert.match(h.d.cookie, /eirinchan_user_flag=country%2Cmeiling%2Ctenshi/);
  assert.equal(h.d.querySelector("[data-flag-preview] .name").textContent, "Anonymous");
  for (const image of h.images()) {
    assert.equal(image.className, "flag"); assert.equal(image.width, 16); assert.equal(image.height, 11);
    assert.equal(image.getAttribute("style"), h.options.style);
    assert.equal(image.title, image.alt);
  }
});

test("typing normalizes names, preserves duplicate order, and empty input previews the privacy fallback", t => {
  const h = setup(t);
  h.type(" TenShi, MEILING , tenshi ");
  assert.deepEqual(h.images().map(image => image.alt), ["Tenshi", "Meiling", "Tenshi"]);
  h.type(""); assert.deepEqual(h.images().map(image => image.alt), ["United States"]);
  h.click('[data-flag-value="meiling"]');
  assert.equal(h.field.value, "meiling", "clicking from empty does not implicitly reveal the visitor country");
  assert.deepEqual(h.images().map(image => image.alt), ["Meiling"]);
  h.type(", ,"); assert.equal(h.images().length, 0, "separator-only input follows posting semantics");
});

test("saved empty preferences are not silently turned into country flags", t => {
  const h = setup(t, {stored: ""});
  assert.equal(h.field.value, "");
  assert.deepEqual(h.images().map(image => image.alt), ["United States"]);
});

test("cookie-only preferences hydrate the picker and Clear keeps its existing country reset behavior", t => {
  const h = setup(t, {cookie: "meiling,tenshi"});
  assert.equal(h.field.value, "meiling,tenshi");
  assert.deepEqual(h.images().map(image => image.alt), ["Meiling", "Tenshi"]);
  h.click("#clearButton");
  assert.equal(h.field.value, "country");
  assert.equal(h.w.EirinchanUserFlagPreference.get(), "country");
  assert.deepEqual(h.images().map(image => image.alt), ["Canada"]);
});

test("unknown or overlong input cannot inject markup or replace the last valid preference", t => {
  const h = setup(t, {stored: "meiling"});
  h.type('<img src=x onerror="alert(1)">');
  assert.equal(h.images().length, 0); assert.equal(h.d.querySelector("[onerror]"), null);
  assert.equal(h.d.querySelector("[data-flag-preview-error]").hidden, false);
  assert.equal(h.w.EirinchanUserFlagPreference.get(), "meiling");
  h.type("x".repeat(301)); assert.equal(h.images().length, 0);
  h.type("tenshi"); assert.equal(h.d.querySelector("[data-flag-preview-error]").hidden, true);
});

test("single flag mode replaces a choice and rejects comma syntax", t => {
  const h = setup(t, {multiple: false});
  h.click('[data-flag-value="meiling"]'); h.click('[data-flag-value="tenshi"]');
  assert.equal(h.field.value, "tenshi"); assert.deepEqual(h.images().map(image => image.alt), ["Tenshi"]);
  h.type("meiling,"); assert.equal(h.images().length, 0);
});

test("automatic country flags remain before selected flags", t => {
  const h = setup(t, {base: [flag("ca", "Canada")], value: "meiling"});
  assert.deepEqual(h.images().map(image => image.alt), ["Canada", "Meiling"]);
  h.type(""); assert.deepEqual(h.images().map(image => image.alt), ["Canada", "United States"]);
});

test("the actual legacy main initializer cannot overwrite or double-bind the dedicated picker", t => {
  const h = setup(t, {stored: "", withLegacy: true});
  assert.equal(h.field.value, "");
  h.click('[data-flag-value="meiling"]');
  assert.equal(h.field.value, "meiling");
  assert.deepEqual(h.images().map(image => image.alt), ["Meiling"]);
  h.w.eval(picker);
  h.click('[data-flag-value="tenshi"]');
  assert.equal(h.field.value, "meiling,tenshi");
});
