(function (window, document) {
  "use strict";

  if (!window.allow_user_custom_code || !window.Options || !window.jQuery) return;

  var $ = window.jQuery;
  var runtime = window.EirinchanRuntime || {};
  var tab = window.Options.add_tab("user-js", "code", translate("User JS"));
  var textarea = $(document.createElement("textarea"))
    .css({fontSize: 12, position: "absolute", top: 35, bottom: 35, width: "calc(100% - 20px)", margin: 0, padding: 4, border: "1px solid black", left: 5, right: 5})
    .appendTo(tab.content);
  var button = $(document.createElement("button"))
    .attr("type", "button")
    .text(translate("Update custom JavaScript"))
    .css({position: "absolute", height: 25, bottom: 5, width: "calc(100% - 10px)", left: 5, right: 5})
    .appendTo(tab.content);

  function translate(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function read() {
    return runtime.readStorage ? runtime.readStorage("local", "user_js", "") : window.localStorage.getItem("user_js") || "";
  }

  function write(value) {
    if (runtime.writeStorage) runtime.writeStorage("local", "user_js", value);
    else window.localStorage.setItem("user_js", value);
  }

  button.on("click", function () {
    write(textarea.val());
    window.console.warn("Stored user JavaScript is not evaluated. The Content Security Policy intentionally blocks inline code.");
  });

  var existing = read();
  textarea.val(existing || "/* " + translate("Store notes or same-origin loader calls here. Inline code is not evaluated.") + " */");

  window.load_js = function (value) {
    var url = runtime.sameOriginUrl ? runtime.sameOriginUrl(String(value || "")) : null;
    if (!url) throw new Error("Only same-origin JavaScript URLs are allowed.");
    var script = document.createElement("script");
    script.src = url.href;
    script.defer = true;
    document.head.appendChild(script);
    return script;
  };
  window.immediate = window.immediate || function () {};
})(window, document);
