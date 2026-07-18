(function () {
  "use strict";

  var stylesheet = document.getElementById("stylesheet");
  if (!stylesheet || !stylesheet.dataset.autoThemeDarkHref || !window.matchMedia) return;

  var dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  var prefix = dark ? "autoThemeDark" : "autoThemeLight";
  var selected = {
    href: stylesheet.dataset[prefix + "Href"],
    label: stylesheet.dataset[prefix + "Label"],
    name: stylesheet.dataset[prefix + "Name"]
  };

  if (!selected.href || !selected.label || !selected.name) return;

  stylesheet.href = selected.href;
  window.__eirinchanAutoTheme = selected;

  var selectedStyleMeta = document.querySelector('meta[name="eirinchan:selected-style"]');
  if (selectedStyleMeta) selectedStyleMeta.setAttribute("content", selected.label);

  var maxAgeMeta = document.querySelector('meta[name="eirinchan:preference-cookie-max-age"]');
  var maxAge = parseInt(maxAgeMeta && maxAgeMeta.content, 10) || 31536000;
  var cookie = "eirinchan_color_scheme=" + (dark ? "dark" : "light") +
    "; path=/; max-age=" + maxAge + "; samesite=lax";
  if (window.location.protocol === "https:") cookie += "; secure";
  document.cookie = cookie;

  function syncRenderedTheme() {
    if (document.body) {
      document.body.setAttribute(
        "data-stylesheet",
        selected.href.split("?")[0].split("/").pop()
      );
    }

    document.querySelectorAll("div.styles a[data-style-name]").forEach(function (option) {
      option.className = option.dataset.styleName === selected.label ? "selected" : "";
    });

    document.querySelectorAll("[data-style-select] option").forEach(function (option) {
      option.selected = option.value === selected.label;
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", syncRenderedTheme, {once: true});
  } else {
    syncRenderedTheme();
  }
})();
