(function (window, document) {
  "use strict";

  var $ = window.jQuery;
  var Options = window.Options;
  if (!$ || !Options || typeof Options.add_tab !== "function") return;

  var runtime = window.EirinchanRuntime || {};
  var tab = Options.add_tab("general", "home", translate("General"));
  var themeCookieNames = ["theme", "board_themes", "eirinchan_color_scheme"];

  function translate(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function storageObject() {
    var result = {};

    try {
      for (var index = 0; index < window.localStorage.length; index += 1) {
        var key = window.localStorage.key(index);
        if (key !== null) result[key] = window.localStorage.getItem(key);
      }
    } catch (_error) {
      return {};
    }

    return result;
  }

  function validatedImport(serialized) {
    if (typeof serialized !== "string" || serialized.length > 1_048_576) {
      throw new Error(translate("Storage data is too large."));
    }

    var parsed = JSON.parse(serialized);
    if (!parsed || Array.isArray(parsed) || Object.getPrototypeOf(parsed) !== Object.prototype) {
      throw new Error(translate("Storage data must be a JSON object."));
    }

    var keys = Object.keys(parsed);
    if (keys.length > 1_000) throw new Error(translate("Storage data has too many entries."));

    var normalized = {};
    keys.forEach(function (key) {
      if (!key || key.length > 256 || key === "__proto__" || key === "constructor") {
        throw new Error(translate("Storage data contains an invalid key."));
      }

      var value = parsed[key];
      if (!["string", "number", "boolean"].includes(typeof value) || String(value).length > 1_048_576) {
        throw new Error(translate("Storage data contains an invalid value."));
      }
      normalized[key] = String(value);
    });

    return normalized;
  }

  function replaceStorage(values) {
    window.localStorage.clear();
    Object.keys(values).forEach(function (key) {
      window.localStorage.setItem(key, values[key]);
    });
  }

  function clearWatcher() {
    if (runtime.requestJson) {
      return runtime.requestJson("/watcher", {method: "DELETE", pathPrefix: "/watcher"}).catch(function () {});
    }

    var token = runtime.csrfToken ? runtime.csrfToken(document.body) : null;
    if (!token || !window.fetch) return Promise.resolve();

    return window
      .fetch("/watcher", {
        method: "DELETE",
        headers: {"x-csrf-token": token, "x-requested-with": "XMLHttpRequest"},
        credentials: "same-origin"
      })
      .catch(function () {});
  }

  function clearThemeCookies() {
    themeCookieNames.forEach(function (name) {
      if (typeof runtime.removeCookie === "function") {
        runtime.removeCookie(name, {path: "/"});
        return;
      }

      var cookie = name + "=; path=/; max-age=0; samesite=lax";
      if (window.location.protocol === "https:") cookie += "; secure";
      document.cookie = cookie;
    });
  }

  function createStorageControls() {
    var controls = $("#options-storage-controls");
    if (controls.length) return controls;

    controls = $(document.createElement("div")).attr("id", "options-storage-controls");
    controls.append($(document.createElement("span")).text(translate("Storage: ")));
    controls.append($(document.createElement("button")).attr({id: "options-storage-export", type: "button"}).text(translate("Export")));
    controls.append($(document.createElement("button")).attr({id: "options-storage-import", type: "button"}).text(translate("Import")));
    controls.append($(document.createElement("button")).attr({id: "options-storage-erase", type: "button"}).text(translate("Erase")));
    controls.append($(document.createElement("input")).attr({id: "options-storage-output", type: "text", hidden: true}).addClass("output"));
    controls.appendTo(tab.content);
    return controls;
  }

  $(function () {
    var preferences = $("#general-preferences");
    if (!preferences.length) preferences = $(document.createElement("div")).attr("id", "general-preferences").appendTo(tab.content);
    createStorageControls();

    $("#options-storage-export").off("click.optionsGeneral").on("click.optionsGeneral", function () {
      $("#options-storage-output").val(JSON.stringify(storageObject())).prop("hidden", false).trigger("select");
    });

    $("#options-storage-import").off("click.optionsGeneral").on("click.optionsGeneral", function () {
      var serialized = window.prompt(translate("Paste your storage data"));
      if (!serialized) return false;

      try {
        replaceStorage(validatedImport(serialized));
        window.location.reload();
      } catch (error) {
        window.alert(error.message || translate("Storage import failed."));
      }
      return false;
    });

    $("#options-storage-erase").off("click.optionsGeneral").on("click.optionsGeneral", function () {
      if (!window.confirm(translate("Are you sure you want to erase your storage? This includes hidden threads, watched threads, post preferences and drafts."))) return;

      try {
        window.localStorage.clear();
      } catch (_error) {}

      try {
        window.sessionStorage.clear();
      } catch (_error) {}

      clearThemeCookies();

      clearWatcher().finally(function () {
        window.location.reload();
      });
    });

    $("#style-select").css({display: "block", float: "none", "margin-bottom": 0}).appendTo(preferences);
    $(document).trigger("general_preferences_ready");
  });
})(window, document);
