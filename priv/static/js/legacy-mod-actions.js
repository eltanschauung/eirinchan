!(function () {
  var RELOAD_DELAY_MS = 6000;
  var reloadTimer = null;
  var runtime = window.EirinchanRuntime || {};

  function showFailure(message) {
    if (typeof runtime.showAlert === "function") {
      runtime.showAlert(message);
    } else {
      window.alert(message);
    }
  }

  function scheduleReload() {
    if (reloadTimer) {
      window.clearTimeout(reloadTimer);
    }

    reloadTimer = window.setTimeout(function () {
      window.location.reload();
    }, RELOAD_DELAY_MS);
  }

  function resolveActionLink(target) {
    if (!target || !target.closest) {
      return null;
    }

    var link = target.closest("a[data-secure-href][data-confirm-message]");

    if (!link) {
      return null;
    }

    var secureHref = link.getAttribute("data-secure-href") || "";

    if (!secureHref || secureHref.indexOf("/mod.php?/") !== 0) {
      return null;
    }

    return link;
  }

  document.addEventListener(
    "click",
    function (event) {
      var link = resolveActionLink(event.target);

      if (!link) {
        return;
      }

      var confirmMessage = link.getAttribute("data-confirm-message") || "";
      var secureHref = link.getAttribute("data-secure-href") || "";

      event.preventDefault();
      event.stopPropagation();

      if (!confirmMessage || !window.confirm(confirmMessage)) {
        return;
      }

      if (link.dataset.legacyModActionPending === "true") {
        return;
      }

      link.dataset.legacyModActionPending = "true";

      window
        .fetch(secureHref, {
          method: "GET",
          credentials: "same-origin",
          headers: {
            "X-Requested-With": "XMLHttpRequest"
          }
        })
        .then(function (response) {
          if (response.ok) {
            scheduleReload();
            return null;
          }

          return response.text().then(function (text) {
            throw new Error((text || "").trim() || "Request failed.");
          });
        })
        .catch(function (error) {
          showFailure(error && error.message ? error.message : "Request failed.");
        })
        .finally(function () {
          delete link.dataset.legacyModActionPending;
        });
    },
    true
  );
})();
