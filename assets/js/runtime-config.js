(function (window, document) {
  "use strict";

  var runtime = (window.EirinchanRuntime = window.EirinchanRuntime || {});
  var cookieNamePattern = /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/;

  function onReady(callback) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback, {once: true});
    } else {
      callback();
    }
  }

  function metaContent(name) {
    var metas = document.getElementsByTagName("meta");

    for (var index = 0; index < metas.length; index += 1) {
      if (metas[index].getAttribute("name") === name) {
        return metas[index].getAttribute("content") || "";
      }
    }

    return "";
  }

  function parseJsonMeta(name, fallback) {
    var value = metaContent(name);
    if (!value) return fallback;

    try {
      return JSON.parse(value);
    } catch (_error) {
      return fallback;
    }
  }

  function parseBoolean(value, fallback) {
    if (value === "true") return true;
    if (value === "false") return false;
    return fallback;
  }

  function parseInteger(value, fallback) {
    var parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function escapeRegularExpression(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  function readCookie(name, fallback) {
    if (!cookieNamePattern.test(String(name))) return fallback;
    var match = document.cookie.match(
      new RegExp("(?:^|; )" + escapeRegularExpression(name) + "=([^;]*)")
    );

    if (!match) return fallback;

    try {
      return decodeURIComponent(match[1]);
    } catch (_error) {
      return fallback;
    }
  }

  function writeCookie(name, value, options) {
    if (!cookieNamePattern.test(String(name))) return false;

    var settings = options || {};
    var cookie = String(name) + "=" + encodeURIComponent(value == null ? "" : String(value));
    var path = typeof settings.path === "string" && settings.path ? settings.path : "/";
    var sameSite = settings.sameSite || "lax";
    var secure =
      typeof settings.secure === "boolean"
        ? settings.secure
        : window.location.protocol === "https:";

    cookie += "; path=" + path;

    if (typeof settings.maxAge === "number" && Number.isFinite(settings.maxAge)) {
      cookie += "; max-age=" + Math.trunc(settings.maxAge);
    }

    if (settings.expires instanceof Date && !Number.isNaN(settings.expires.getTime())) {
      cookie += "; expires=" + settings.expires.toUTCString();
    }

    cookie += "; samesite=" + String(sameSite).toLowerCase();
    if (secure) cookie += "; secure";
    document.cookie = cookie;
    return true;
  }

  function removeCookie(name, options) {
    var settings = options || {};
    return writeCookie(name, "", {
      path: settings.path || "/",
      maxAge: 0,
      sameSite: settings.sameSite || "lax",
      secure: settings.secure
    });
  }

  function storage(kind) {
    try {
      var candidate = kind === "session" ? window.sessionStorage : window.localStorage;
      var probe = "__eirinchan_storage_probe__";
      candidate.setItem(probe, probe);
      candidate.removeItem(probe);
      return candidate;
    } catch (_error) {
      return null;
    }
  }

  function readStorage(kind, key, fallback) {
    var target = storage(kind);
    if (!target) return fallback;

    try {
      var value = target.getItem(key);
      return value === null ? fallback : value;
    } catch (_error) {
      return fallback;
    }
  }

  function writeStorage(kind, key, value) {
    var target = storage(kind);
    if (!target) return false;

    try {
      target.setItem(key, String(value));
      return true;
    } catch (_error) {
      return false;
    }
  }

  function removeStorage(kind, key) {
    var target = storage(kind);
    if (!target) return false;

    try {
      target.removeItem(key);
      return true;
    } catch (_error) {
      return false;
    }
  }

  function readJsonStorage(kind, key, fallback) {
    var value = readStorage(kind, key, null);
    if (value === null) return fallback;

    try {
      return JSON.parse(value);
    } catch (_error) {
      return fallback;
    }
  }

  function writeJsonStorage(kind, key, value) {
    try {
      return writeStorage(kind, key, JSON.stringify(value));
    } catch (_error) {
      return false;
    }
  }

  function csrfToken(trigger) {
    var form = trigger && trigger.closest ? trigger.closest("form") : null;
    var field =
      (form && form.querySelector('input[name="_csrf_token"]')) ||
      document.querySelector('input[name="_csrf_token"]');

    if (field && field.value) return field.value;
    return metaContent("csrf-token") || null;
  }

  function sameOriginUrl(value, prefix) {
    if (typeof value !== "string" || !value.trim()) return null;

    try {
      var url = new URL(value, window.location.href);
      if (url.origin !== window.location.origin) return null;
      if (prefix && !pathMatchesPrefix(url.pathname, prefix)) return null;
      return url;
    } catch (_error) {
      return null;
    }
  }

  function pathMatchesPrefix(pathname, prefix) {
    var normalizedPrefix = String(prefix || "");
    if (!normalizedPrefix || normalizedPrefix === "/") return true;
    if (normalizedPrefix.endsWith("/")) return pathname.indexOf(normalizedPrefix) === 0;
    return pathname === normalizedPrefix || pathname.indexOf(normalizedPrefix + "/") === 0;
  }

  function sameOriginPath(value, prefix) {
    var url = sameOriginUrl(value, prefix);
    return url ? url.pathname + url.search + url.hash : null;
  }

  function requestJson(value, options) {
    var settings = options || {};
    var url = sameOriginUrl(value, settings.pathPrefix);

    if (!url || typeof window.fetch !== "function") {
      return Promise.reject(new Error("invalid same-origin request URL"));
    }

    var method = String(settings.method || "GET").toUpperCase();
    var headers = new Headers(settings.headers || {});
    headers.set("Accept", "application/json");
    headers.set("X-Requested-With", "XMLHttpRequest");

    if (!["GET", "HEAD", "OPTIONS"].includes(method)) {
      var token = settings.csrfToken || csrfToken(settings.trigger || document.body);
      if (!token) return Promise.reject(new Error("missing CSRF token"));
      headers.set("X-CSRF-Token", token);
    }

    if (settings.json !== undefined) {
      headers.set("Content-Type", "application/json");
    }

    return window
      .fetch(url.href, {
        method: method,
        credentials: "same-origin",
        cache: settings.cache || "no-store",
        headers: headers,
        signal: settings.signal,
        body: settings.json === undefined ? settings.body : JSON.stringify(settings.json)
      })
      .then(function (response) {
        if (!response.ok) {
          var error = new Error("request failed with status " + response.status);
          error.response = response;
          throw error;
        }

        return response.status === 204 ? null : response.json();
      });
  }

  function randomString(characters, length) {
    var alphabet = String(characters || "");
    var requestedLength = Math.max(0, parseInteger(length, 0));

    if (!alphabet || requestedLength === 0) return "";

    var cryptoObject = window.crypto || window.msCrypto;
    if (!cryptoObject || typeof cryptoObject.getRandomValues !== "function") {
      throw new Error("secure random number generation is unavailable");
    }

    if (alphabet.length > 0x100000000) {
      throw new Error("password alphabet is too large");
    }

    var output = "";
    var range = 0x100000000;
    var limit = range - (range % alphabet.length);

    while (output.length < requestedLength) {
      var values = new Uint32Array(Math.max(16, (requestedLength - output.length) * 2));
      cryptoObject.getRandomValues(values);

      for (var index = 0; index < values.length && output.length < requestedLength; index += 1) {
        if (values[index] >= limit) continue;
        output += alphabet.charAt(values[index] % alphabet.length);
      }
    }

    return output;
  }

  function removeAlert() {
    var existing = document.getElementById("alert_handler");
    if (existing) existing.remove();
  }

  function showAlert(message) {
    removeAlert();

    var handler = document.createElement("div");
    handler.id = "alert_handler";
    handler.style.display = "block";
    handler.style.visibility = "visible";

    var background = document.createElement("div");
    background.id = "alert_background";

    var dialog = document.createElement("div");
    dialog.id = "alert_div";
    dialog.setAttribute("role", "alertdialog");
    dialog.setAttribute("aria-modal", "true");

    var close = document.createElement("a");
    close.id = "alert_close";
    close.href = "#";
    close.setAttribute("aria-label", "Close");
    var closeIcon = document.createElement("i");
    closeIcon.className = "fa fa-times";
    close.appendChild(closeIcon);

    var messageElement = document.createElement("div");
    messageElement.id = "alert_message";
    messageElement.textContent = message == null ? "" : String(message);

    var okay = document.createElement("button");
    okay.type = "button";
    okay.className = "button alert_button";
    okay.textContent = "OK";

    background.addEventListener("click", removeAlert);
    close.addEventListener("click", function (event) {
      event.preventDefault();
      removeAlert();
    });
    okay.addEventListener("click", removeAlert);

    dialog.append(close, messageElement, okay);
    handler.append(background, dialog);
    document.body.appendChild(handler);
    okay.focus();
    return handler;
  }

  function generatePassword() {
    var characters =
      window.genpassword_chars ||
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+";

    try {
      return randomString(characters, 8);
    } catch (_error) {
      return "";
    }
  }

  function syncTimezoneCookies() {
    try {
      var timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      var offset = -new Date().getTimezoneOffset();
      var serverTimezone = metaContent("eirinchan:browser-timezone");
      var serverOffset = parseInteger(metaContent("eirinchan:browser-timezone-offset"), 0);

      if (timezone && timezone !== serverTimezone) {
        writeCookie("timezone", timezone, {path: "/", maxAge: runtime.preferenceCookieMaxAge});
      }

      if (Number.isFinite(offset) && offset !== serverOffset) {
        writeCookie("timezone_offset", offset, {path: "/", maxAge: runtime.preferenceCookieMaxAge});
      }
    } catch (_error) {
      // Timezone detection is an optional enhancement.
    }
  }

  runtime.onReady = onReady;
  runtime.metaContent = metaContent;
  runtime.parseJsonMeta = parseJsonMeta;
  runtime.parseBoolean = parseBoolean;
  runtime.parseInteger = parseInteger;
  runtime.readCookie = readCookie;
  runtime.writeCookie = writeCookie;
  runtime.removeCookie = removeCookie;
  runtime.storage = storage;
  runtime.readStorage = readStorage;
  runtime.writeStorage = writeStorage;
  runtime.removeStorage = removeStorage;
  runtime.readJsonStorage = readJsonStorage;
  runtime.writeJsonStorage = writeJsonStorage;
  runtime.csrfToken = csrfToken;
  runtime.sameOriginUrl = sameOriginUrl;
  runtime.sameOriginPath = sameOriginPath;
  runtime.requestJson = requestJson;
  runtime.randomString = randomString;
  runtime.showAlert = showAlert;
  runtime.generatePassword = generatePassword;
  runtime.syncTimezoneCookies = syncTimezoneCookies;
  runtime.preferenceCookieMaxAge = Math.max(
    1,
    parseInteger(metaContent("eirinchan:preference-cookie-max-age"), 31_536_000)
  );

  if (window.active_page === undefined) window.active_page = metaContent("eirinchan:active-page") || "";
  if (window.board_name === undefined) window.board_name = metaContent("eirinchan:board-name") || null;
  if (window.thread_id === undefined) window.thread_id = metaContent("eirinchan:thread-id") || null;
  if (window.configRoot === undefined) window.configRoot = metaContent("eirinchan:config-root") || "/";
  if (window.inMod === undefined) window.inMod = false;
  if (window.modRoot === undefined) window.modRoot = window.configRoot + (window.inMod ? "mod.php?/" : "");
  if (window.resourceVersion === undefined) window.resourceVersion = metaContent("eirinchan:resource-version") || "";
  if (window.selectedstyle === undefined) window.selectedstyle = metaContent("eirinchan:selected-style") || "Yotsuba";
  if (!window.styles) window.styles = parseJsonMeta("eirinchan:styles", {});
  if (window.stylesheets_board === undefined) {
    window.stylesheets_board = parseBoolean(metaContent("eirinchan:stylesheets-board"), true);
  }
  if (window.genpassword_chars === undefined) window.genpassword_chars = metaContent("eirinchan:genpassword-chars") || "";
  if (window.post_success_cookie_name === undefined) {
    window.post_success_cookie_name = metaContent("eirinchan:post-success-cookie-name") || "eirinchan_posted";
  }
  if (window.watcher_count === undefined) window.watcher_count = parseInteger(metaContent("eirinchan:watcher-count"), 0);
  if (window.watcher_unread_count === undefined) {
    window.watcher_unread_count = parseInteger(metaContent("eirinchan:watcher-unread-count"), 0);
  }
  if (window.watcher_you_count === undefined) {
    window.watcher_you_count = parseInteger(metaContent("eirinchan:watcher-you-count"), 0);
  }
  if (window.allow_user_custom_code === undefined) {
    window.allow_user_custom_code = parseBoolean(
      metaContent("eirinchan:allow-user-custom-code"),
      true
    );
  }

  window.onReady = window.onReady || onReady;
  window.showAlert = window.showAlert || showAlert;
  window.generatePassword = window.generatePassword || generatePassword;

  syncTimezoneCookies();
})(window, document);
