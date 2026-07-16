(function (window, document) {
  "use strict";

  var supportedPages = ["thread", "index", "catalog", "ukko"];
  if (supportedPages.indexOf(window.active_page) === -1) return;

  function fallbackReadCookie(name, fallback) {
    var escapedName = String(name).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    var match = document.cookie.match(new RegExp("(?:^|; )" + escapedName + "=([^;]*)"));
    return match ? decodeURIComponent(match[1]) : fallback;
  }

  function fallbackWriteCookie(name, value) {
    document.cookie =
      name + "=" + encodeURIComponent(value) + "; path=/; max-age=31536000; samesite=lax";
  }

  function setArrowVisibility(enabled) {
    document.querySelectorAll(".navarrow").forEach(function (arrow) {
      arrow.style.display = enabled ? "" : "none";
    });
  }

  function initialize() {
    var runtime = window.EirinchanRuntime || {};
    var readCookie = runtime.readCookie || fallbackReadCookie;
    var writeCookie = runtime.writeCookie || fallbackWriteCookie;
    var enabled = readCookie("navarrows", null) !== "false";

    setArrowVisibility(enabled);

    if (!window.Options || !window.Options.get_tab("general")) return;

    window.Options.extend_tab(
      "general",
      '<label id="add-nav-arrows"><input type="checkbox">' +
        (typeof window._ === "function" ? window._("Display navigation arrows") : "Display navigation arrows") +
        "</label>"
    );

    var checkbox = document.querySelector("#add-nav-arrows > input");
    if (!checkbox) return;

    checkbox.checked = enabled;
    checkbox.addEventListener("change", function () {
      enabled = checkbox.checked;
      writeCookie("navarrows", enabled ? "true" : "false", {
        path: "/",
        maxAge: 31_536_000,
        sameSite: "lax"
      });
      setArrowVisibility(enabled);

      if (enabled && !document.querySelector(".navarrow")) window.location.reload();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, {once: true});
  } else {
    initialize();
  }
})(window, document);
