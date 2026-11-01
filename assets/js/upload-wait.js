(function () {
  "use strict";
  var notice = document.querySelector("[data-upload-wait-message]");
  if (!notice || notice.getAttribute("data-alerted") === "true") return;
  notice.setAttribute("data-alerted", "true");
  window.alert(notice.getAttribute("data-upload-wait-message"));
}());
