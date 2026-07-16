(function (window, document) {
  "use strict";

  if (!window.allow_user_custom_code || !window.Options || !window.jQuery) return;

  var $ = window.jQuery;
  var runtime = window.EirinchanRuntime || {};
  var maxCustomCodeBytes = 256 * 1024;
  var tab = window.Options.add_tab("user-css", "css3", translate("User CSS"));
  var textarea = $(document.createElement("textarea"))
    .css({fontSize: 12, position: "absolute", top: 35, bottom: 35, width: "calc(100% - 20px)", margin: 0, padding: 4, border: "1px solid black", left: 5, right: 5})
    .appendTo(tab.content);
  var button = $(document.createElement("button"))
    .attr("type", "button")
    .text(translate("Update custom CSS"))
    .css({position: "absolute", height: 25, bottom: 5, width: "calc(100% - 10px)", left: 5, right: 5})
    .appendTo(tab.content);

  function translate(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function read() {
    return runtime.readStorage ? runtime.readStorage("local", "user_css", "") : window.localStorage.getItem("user_css") || "";
  }

  function write(value) {
    if (runtime.writeStorage) runtime.writeStorage("local", "user_css", value);
    else window.localStorage.setItem("user_css", value);
  }

  function normalize(value) {
    return String(value || "")
      .replace(/^\uFEFF/, "")
      .replace(/\u0000/g, "")
      .slice(0, maxCustomCodeBytes);
  }

  function apply(value) {
    document.querySelectorAll("style.user-css").forEach(function (style) { style.remove(); });
    if (!value) return;
    var style = document.createElement("style");
    style.className = "user-css";
    style.textContent = value;
    document.head.appendChild(style);
  }

  button.on("click", function () {
    var value = normalize(textarea.val());
    write(value);
    textarea.val(value);
    apply(value);
  });

  var existing = normalize(read());
  textarea.val(existing || "/* " + translate("Enter your own CSS rules here.") + " */");
  apply(existing);
})(window, document);
