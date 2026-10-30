(function (window, document) {
  "use strict";
  function notify() {
    var message = document.querySelector("[data-feedback-submitted]");
    if (!message || message.dataset.notified === "true") return;
    message.dataset.notified = "true";
    window.alert("Feedback submitted!");
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", notify, {once: true});
  else notify();
})(window, document);
