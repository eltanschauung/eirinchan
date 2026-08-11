(function (window, document) {
  "use strict";

  function translate(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function fallbackReadCookie(name, fallback) {
    var escapedName = String(name).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    var match = document.cookie.match(new RegExp("(?:^|; )" + escapedName + "=([^;]*)"));
    return match ? decodeURIComponent(match[1]) : fallback;
  }

  function fallbackWriteCookie(name, value, options) {
    var maxAge =
      parseInt(
        (options && options.maxAge) ||
          (document.querySelector('meta[name="eirinchan:preference-cookie-max-age"]') || {}).content,
        10
      ) || 31_536_000;
    var cookie =
      name + "=" + encodeURIComponent(value) + "; path=/; max-age=" + maxAge + "; samesite=lax";
    if (window.location.protocol === "https:") cookie += "; secure";
    document.cookie = cookie;
  }

  function initialize() {
    if (!window.Options || !window.Options.get_tab("general")) return;

    var runtime = window.EirinchanRuntime || {};
    var readCookie = runtime.readCookie || fallbackReadCookie;
    var writeCookie = runtime.writeCookie || fallbackWriteCookie;

    if (!document.getElementById("show-yous")) {
      window.Options.extend_tab(
        "general",
        '<label id="show-yous"><input type="checkbox">' + translate("Show (You)s") + "</label>"
      );
    }

    var checkbox = document.querySelector("#show-yous > input");
    if (!checkbox) return;

    checkbox.checked = readCookie("show_yous", "true") !== "false";
    checkbox.addEventListener("change", function () {
      writeCookie("show_yous", checkbox.checked ? "true" : "false", {
        path: "/",
        maxAge: runtime.preferenceCookieMaxAge || 31_536_000,
        sameSite: "lax"
      });
      window.location.reload();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, {once: true});
  } else {
    initialize();
  }
})(window, document);
