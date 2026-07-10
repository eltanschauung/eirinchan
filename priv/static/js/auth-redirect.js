(function () {
  "use strict";

  var redirectUrl = document.body && document.body.dataset.redirectUrl;

  if (redirectUrl) {
    window.setTimeout(function () {
      window.location.assign(redirectUrl);
    }, 3000);
  }
})();
