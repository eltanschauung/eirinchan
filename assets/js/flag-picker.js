(function (window, document) {
  "use strict";

  function init() {
    var page = document.querySelector("[data-flag-page]");
    if (!page || page.dataset.flagPickerInitialized === "true") return;
    var field = page.querySelector('[name="user_flag"]');
    var preview = page.querySelector("[data-flag-preview]");
    if (!field || !preview) return;
    var output = preview.querySelector("[data-flag-preview-flags]");
    var error = preview.querySelector("[data-flag-preview-error]");
    var options;
    try { options = JSON.parse(preview.getAttribute("data-flag-preview-options")); }
    catch (_error) { return; }
    if (!output || !options || !options.flags) return;

    // One controller owns field mutations and rendering. The preference client
    // remains the authority for persistence; no preview request is sent.
    page.dataset.flagPageInitialized = "true";
    page.dataset.flagPickerInitialized = "true";

    function normalized(value) {
      if (typeof value !== "string" || value.length > 300) return null;
      var tokens = (options.multiple ? value.split(",") : [value]).map(function (token) { return token.trim().toLowerCase(); })
        .filter(function (token) { return token !== ""; });
      if ((!options.multiple && tokens.length > 1) || tokens.some(function (token) {
        return !Object.prototype.hasOwnProperty.call(options.flags, token);
      })) return null;
      return tokens;
    }

    function render() {
      var tokens = normalized(field.value);
      output.replaceChildren();
      if (error) error.hidden = tokens !== null;
      if (tokens === null) return;
      var flags = options.base.concat(field.value.trim() === "" ? options.fallback : tokens.flatMap(function (token) {
        return options.flags[token];
      }));
      flags.forEach(function (flag) {
        var image = document.createElement("img");
        image.className = "flag";
        image.src = flag.src;
        image.alt = flag.alt;
        image.title = flag.alt;
        image.width = 16;
        image.height = 11;
        image.loading = "eager";
        image.decoding = "async";
        if (options.style) image.setAttribute("style", options.style);
        output.appendChild(document.createTextNode(" "));
        output.appendChild(image);
      });
    }

    function setField(value) {
      field.value = value;
      // Programmatic gallery/Clear changes must take the same path as typing,
      // including the preference client's capture-phase validation/persistence.
      field.dispatchEvent(new window.Event("input", {bubbles: true}));
    }

    var preference = window.EirinchanUserFlagPreference;
    var saved = preference ? preference.get() : null;
    if (saved === null) {
      try { saved = window.localStorage.getItem("flag_"); } catch (_error) {}
    }
    if (normalized(saved) !== null) field.value = saved;
    field.addEventListener("input", render);
    field.addEventListener("change", render);
    page.addEventListener("click", function (event) {
      var image = event.target.closest(".image-canvas img[data-flag-value]");
      if (image) {
        var code = image.getAttribute("data-flag-value");
        var next = options.multiple && field.value.trim() ? field.value + "," + code : code;
        if (next.length <= 300) setField(next);
        else if (error) error.hidden = false;
      } else if (event.target.closest("#clearButton")) {
        setField("country");
      } else if (event.target.closest("#applyButton") && normalized(field.value) !== null) {
        if (preference) preference.set(field.value);
        else {
          try { window.localStorage.setItem("flag_", field.value); } catch (_error) {}
        }
      }
    });
    render();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, {once: true});
  } else init();
})(window, document);
