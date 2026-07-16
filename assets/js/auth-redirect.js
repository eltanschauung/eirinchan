(function (window, document) {
  "use strict";

  var value = document.body && document.body.dataset.redirectUrl;
  if (!value) return;

  try {
    var redirect = new URL(value, window.location.href);
    if (redirect.origin !== window.location.origin) return;

    window.setTimeout(function () {
      window.location.assign(redirect.pathname + redirect.search + redirect.hash);
    }, 3000);
  } catch (_error) {
    // Invalid redirect data is ignored; the page retains its normal link.
  }
})(window, document);
