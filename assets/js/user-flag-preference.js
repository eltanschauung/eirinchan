(function (window, document) {
  "use strict";

  var storageKey = "flag_";
  var cookieName = metaContent("eirinchan:user-flag-cookie-name") || "eirinchan_user_flag";
  var maximumLength = 300;
  var allowedValues = parseAllowedValues();
  var multipleFlags = metaContent("eirinchan:user-flag-mode") === "multi";
  var currentValue = initialValue();

  function metaContent(name) {
    var node = document.querySelector('meta[name="' + name + '"]');
    return node ? node.getAttribute("content") : null;
  }

  function normalize(value) {
    if (typeof value !== "string" || value.length > maximumLength) return null;

    var trimmed = value.trim();
    if (!trimmed) return "";

    var flags = trimmed
      .split(",")
      .map(function (flag) { return flag.trim().toLowerCase(); })
      .filter(function (flag) { return flag !== ""; });

    if (!multipleFlags && flags.length > 1) return null;
    if (allowedValues && flags.some(function (flag) { return !allowedValues[flag]; })) return null;
    return flags.join(",");
  }

  function parseAllowedValues() {
    var serialized = metaContent("eirinchan:user-flag-allowed-values");
    if (!serialized) return null;

    try {
      return JSON.parse(serialized).reduce(function (values, flag) {
        values[String(flag).trim().toLowerCase()] = true;
        return values;
      }, {});
    } catch (_error) {
      return null;
    }
  }

  function readStorage(key) {
    try {
      return window.localStorage.getItem(key);
    } catch (_error) {
      return null;
    }
  }

  function writeStorage(key, value) {
    try {
      window.localStorage.setItem(key, value);
      return true;
    } catch (_error) {
      return false;
    }
  }

  function removeStorage(key) {
    try {
      window.localStorage.removeItem(key);
    } catch (_error) {}
  }

  function readCookie(name) {
    var escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    var match = document.cookie.match(new RegExp("(?:^|; )" + escaped + "=([^;]*)"));
    if (!match) return null;

    try {
      return decodeURIComponent(match[1]);
    } catch (_error) {
      return null;
    }
  }

  function cookieMaxAge() {
    var parsed = parseInt(metaContent("eirinchan:preference-cookie-max-age"), 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 31536000;
  }

  function writeCookie(value) {
    var cookie = cookieName + "=" + encodeURIComponent(value) +
      "; path=/; max-age=" + cookieMaxAge() + "; samesite=lax";
    if (window.location.protocol === "https:") cookie += "; secure";
    document.cookie = cookie;
  }

  function removeCookie() {
    var cookie = cookieName + "=; path=/; max-age=0; samesite=lax";
    if (window.location.protocol === "https:") cookie += "; secure";
    document.cookie = cookie;
  }

  function legacyStorageKey() {
    var board = metaContent("eirinchan:board-name");
    return board ? "flag_" + board : null;
  }

  function initialValue() {
    var rawStored = readStorage(storageKey);
    var stored = normalize(rawStored);
    var legacyKey = legacyStorageKey();

    if (rawStored !== null && stored === null) removeStorage(storageKey);

    if (stored === null && legacyKey) {
      var rawLegacy = readStorage(legacyKey);
      stored = normalize(rawLegacy);
      if (rawLegacy !== null) removeStorage(legacyKey);
    }

    if (stored === null) {
      var rawCookie = readCookie(cookieName);
      stored = normalize(rawCookie);
      if (rawCookie !== null && stored === null) removeCookie();
    }
    if (stored !== null) persist(stored);
    return stored;
  }

  function persist(value) {
    writeStorage(storageKey, value);
    writeCookie(value);
  }

  function setCurrent(value) {
    var normalized = normalize(value);
    if (normalized === null) return null;
    currentValue = normalized;
    persist(normalized);
    return normalized;
  }

  function flagField(form) {
    if (!form || !form.elements) return null;
    return form.elements.user_flag || null;
  }

  function hydrate(form) {
    var field = flagField(form);
    if (!field) return null;

    if (currentValue === null) currentValue = setCurrent(field.value);

    if (currentValue !== null && field.dataset.userFlagDirty !== "true") {
      field.value = currentValue;
      field.dataset.userFlagHydratedValue = currentValue;
    }

    field.dataset.userFlagHydrated = "true";
    return field.value;
  }

  function finalize(form) {
    var field = flagField(form);
    if (!field) return null;

    var normalizedField = normalize(field.value);
    var hydratedValue = field.dataset.userFlagHydratedValue;
    var changedAfterHydration =
      field.dataset.userFlagHydrated === "true" &&
      normalizedField !== null &&
      normalizedField !== hydratedValue;

    if (field.dataset.userFlagDirty === "true" || changedAfterHydration) {
      setCurrent(field.value);
      return field.value;
    }

    if (currentValue !== null) {
      field.value = currentValue;
      field.dataset.userFlagHydratedValue = currentValue;
      field.dataset.userFlagHydrated = "true";
      return currentValue;
    }

    return hydrate(form);
  }

  function hydrateWithin(root) {
    if (!root) return;

    if (root.matches && root.matches("form[data-post-form]")) hydrate(root);
    if (!root.querySelectorAll) return;

    Array.prototype.forEach.call(root.querySelectorAll("form[data-post-form]"), hydrate);
  }

  function clear() {
    currentValue = null;
    removeStorage(storageKey);
    removeCookie();
  }

  document.addEventListener("input", function (event) {
    var field = event.target;
    if (!field || field.name !== "user_flag") return;
    field.dataset.userFlagDirty = "true";
    setCurrent(field.value);
  }, true);

  document.addEventListener("change", function (event) {
    var field = event.target;
    if (!field || field.name !== "user_flag") return;
    field.dataset.userFlagDirty = "true";
    setCurrent(field.value);
  }, true);

  document.addEventListener("submit", function (event) {
    if (event.target && event.target.matches("form[data-post-form]")) finalize(event.target);
  }, true);

  document.addEventListener("click", function (event) {
    var button = event.target && event.target.closest
      ? event.target.closest("#applyButton, #clearButton")
      : null;
    if (!button) return;

    var page = button.closest("[data-flag-page]");
    var field = page && page.querySelector('[name="user_flag"]');
    if (field) setCurrent(field.value);
  });

  window.addEventListener("storage", function (event) {
    var legacyKey = legacyStorageKey();
    if (event.key !== storageKey && event.key !== legacyKey && event.key !== null) return;

    var replacement = normalize(readStorage(storageKey));
    if (replacement === null && legacyKey) replacement = normalize(readStorage(legacyKey));
    if (replacement === null) replacement = normalize(readCookie(cookieName));
    currentValue = replacement;
    if (currentValue !== null) {
      persist(currentValue);
      hydrateWithin(document);
    }
  });

  if (window.MutationObserver && document.documentElement) {
    new window.MutationObserver(function (records) {
      records.forEach(function (record) {
        Array.prototype.forEach.call(record.addedNodes || [], hydrateWithin);
      });
    }).observe(document.documentElement, {childList: true, subtree: true});
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () { hydrateWithin(document); }, {once: true});
  } else {
    hydrateWithin(document);
  }

  window.addEventListener("pageshow", function () { hydrateWithin(document); });

  window.EirinchanUserFlagPreference = {
    clear: clear,
    finalize: finalize,
    get: function () { return currentValue; },
    hydrate: hydrate,
    set: setCurrent
  };

  window.EirinchanFrontend = window.EirinchanFrontend || {};
  window.EirinchanFrontend.applyPersistedUserFlag = hydrate;
})(window, document);
