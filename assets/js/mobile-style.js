(function (window, document, navigator) {
  "use strict";

  var root = document.documentElement;
  var mobilePattern = /iPhone|iPod|iPad|Android|Opera Mini|BlackBerry|PlayBook|Windows Phone|Tablet PC|Windows CE|IEMobile/i;
  var mobile = root.classList.contains("mobile-style");

  if (!mobile && !root.classList.contains("desktop-style")) {
    mobile = mobilePattern.test(navigator.userAgent || "");
    root.classList.add(mobile ? "mobile-style" : "desktop-style");
  }

  window.device_type = mobile ? "mobile" : "desktop";
})(window, document, navigator);
