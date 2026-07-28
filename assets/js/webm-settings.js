(function (window, document) {
  "use strict";

  var defaults = {
    videoexpand: true,
    videohover: false,
    videovolume: 0.4
  };

  function translate(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function readSetting(name) {
    try {
      var stored = window.localStorage.getItem(name);
      return stored === null ? defaults[name] : JSON.parse(stored);
    } catch (_error) {
      return defaults[name];
    }
  }

  function writeSetting(name, value) {
    try {
      window.localStorage.setItem(name, JSON.stringify(value));
    } catch (_error) {}
  }

  // expand-video.js consumes these long-standing public helpers.
  window.setting = readSetting;
  window.changeSetting = writeSetting;

  function addCheckbox(container, name, label) {
    var wrapper = document.createElement("label");
    var input = document.createElement("input");
    input.type = "checkbox";
    input.name = name;
    input.checked = !!readSetting(name);
    input.addEventListener("change", function () {
      writeSetting(name, input.checked);
    });
    wrapper.append(input, document.createTextNode(label));
    container.append(wrapper, document.createElement("br"));
  }

  function initialize() {
    if (!window.Options || typeof window.Options.add_tab !== "function") return;

    var tab = window.Options.add_tab("webm", "video-camera", translate("WebM"));
    if (document.getElementById("webm-settings-menu")) return;

    var settings = document.createElement("div");
    settings.id = "webm-settings-menu";
    window.settingsMenu = settings;
    addCheckbox(settings, "videoexpand", translate("Expand videos inline"));
    addCheckbox(settings, "videohover", translate("Play videos on hover"));

    var volumeLabel = document.createElement("label");
    var volume = document.createElement("input");
    volume.type = "range";
    volume.name = "videovolume";
    volume.min = "0";
    volume.max = "1";
    volume.step = "0.01";
    volume.style.cssText = "width:4em;height:1ex;vertical-align:middle";
    volume.value = String(readSetting("videovolume"));
    volume.addEventListener("change", function () {
      writeSetting("videovolume", volume.value);
    });
    volumeLabel.append(volume, document.createTextNode(translate("Default volume")));
    settings.append(volumeLabel, document.createElement("br"));
    tab.content.append(settings);
  }

  initialize();
})(window, document);
