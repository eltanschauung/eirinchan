(function (window, document) {
  "use strict";

  if (!window.allow_user_custom_code || !window.Options || !window.jQuery) return;

  var $ = window.jQuery;
  var runtime = window.EirinchanRuntime || {};
  var maxCustomCodeBytes = 256 * 1024;
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

  function normalize(value) {
    return String(value || "")
      .replace(/^\uFEFF/, "")
      .replace(/\u0000/g, "")
      .slice(0, maxCustomCodeBytes);
  }

  function execute(value) {
    var code = normalize(value);
    if (!code.trim()) return;

    var blob = new window.Blob(
      [code, "\n//# sourceURL=eirinchan-user.js\n"],
      {type: "text/javascript"}
    );
    var objectUrl = window.URL.createObjectURL(blob);
    var script = document.createElement("script");
    script.className = "user-js";
    script.src = objectUrl;

    function releaseObjectUrl() {
      window.URL.revokeObjectURL(objectUrl);
    }

    script.addEventListener("load", releaseObjectUrl, {once: true});
    script.addEventListener("error", releaseObjectUrl, {once: true});
    document.head.appendChild(script);
  }

  button.on("click", function () {
    write(normalize(textarea.val()));
    window.location.reload();
  });

  var existing = normalize(read());
  textarea.val(existing || "/* " + translate("Enter your own JavaScript code here. It is stored only in this browser.") + " */");

  if (existing) {
    if (/immediate\s*\(\s*\)/.test(existing)) execute(existing);
    else if (runtime.onReady) runtime.onReady(function () { execute(existing); });
    else $(function () { execute(existing); });
  }

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
