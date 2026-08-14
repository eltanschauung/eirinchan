(function (window, document) {
  "use strict";

  if (window.EirinchanPostActions && window.EirinchanPostActions.bound) return;

  var runtime = window.EirinchanRuntime || {};
  var postActions = window.EirinchanPostActions || {};

  function actionFor(submitter) {
    if (!submitter) return null;

    var action = submitter.dataset && submitter.dataset.postAction;
    if (action === "delete" || action === "report") return action;

    var name = submitter.getAttribute("name");
    return name === "delete" || name === "report" ? name : null;
  }

  function publicActionForm(form) {
    if (!form || !form.matches("form[name='postcontrols'], form.post-actions")) return false;

    try {
      var action = new URL(form.action, window.location.href);
      return (
        action.origin === window.location.origin &&
        (action.pathname === "/post.php" || /\/post$/.test(action.pathname))
      );
    } catch (_error) {
      return false;
    }
  }

  function selectedPostId(form, payload, action) {
    var preferred = payload.get(action === "report" ? "report_post_id" : "delete_post_id");
    if (preferred) return String(preferred);

    var alternate = payload.get(action === "report" ? "delete_post_id" : "report_post_id");
    if (alternate) return String(alternate);

    var selected = form.querySelector(
      "[data-post-select]:checked, input.delete:checked, input[name^='delete_']:checked"
    );

    if (selected) {
      if (selected.value && selected.value !== "on") return String(selected.value);
      var selectedMatch = (selected.name || "").match(/^delete_(\d+)$/);
      if (selectedMatch) return selectedMatch[1];
    }

    var quickTarget = form.querySelector("input[name^='delete_']");
    var quickMatch = quickTarget && (quickTarget.name || "").match(/^delete_(\d+)$/);
    return quickMatch ? quickMatch[1] : null;
  }

  function actionPayload(form, submitter, action) {
    var payload = new window.FormData(form);
    var postId = selectedPostId(form, payload, action);

    if (!postId) return null;

    payload.set("json_response", "1");

    if (action === "delete") {
      payload.delete("report_post_id");
      payload.delete("report");
      payload.set("delete_post_id", postId);
    } else {
      payload.delete("delete_post_id");
      payload.delete("delete");
      payload.set("report_post_id", postId);
    }

    payload.set(action, submitter.value || (action === "delete" ? "Delete" : "Report"));
    return payload;
  }

  function showFailure(action, message) {
    var fallback = action === "report" ? "Report failed. Please try again." : "Delete failed. Please try again.";
    var text = message || fallback;

    if (typeof runtime.showAlert === "function") runtime.showAlert(text);
    else if (typeof window.showAlert === "function") window.showAlert(text);
    else window.alert(text);
  }

  function responseBody(response) {
    return response.text().then(function (text) {
      if (!text) return null;

      try {
        return JSON.parse(text);
      } catch (_error) {
        return null;
      }
    });
  }

  function defaultNavigate(path) {
    try {
      var target = new URL(path || window.location.href, window.location.href);
      if (target.origin === window.location.origin) {
        window.location.assign(target.href);
        return;
      }
    } catch (_error) {
      // Reload the current page when the server does not provide a safe redirect.
    }

    window.location.reload();
  }

  postActions.navigate = postActions.navigate || defaultNavigate;
  postActions.bound = true;
  window.EirinchanPostActions = postActions;

  document.addEventListener(
    "click",
    function (event) {
      var submitter = event.target.closest("button, input[type='submit']");
      var form = submitter && submitter.form;

      if (publicActionForm(form) && actionFor(submitter)) {
        form.__eirinchanPostActionSubmitter = submitter;
      }
    },
    true
  );

  document.addEventListener("submit", function (event) {
    if (event.defaultPrevented) return;

    var form = event.target;
    var submitter = event.submitter || form.__eirinchanPostActionSubmitter;
    var action = actionFor(submitter);

    delete form.__eirinchanPostActionSubmitter;

    if (!action || !publicActionForm(form) || form.dataset.postActionPending === "true") return;
    if (typeof window.fetch !== "function" || typeof window.FormData !== "function") return;

    var payload = actionPayload(form, submitter, action);
    if (!payload) return;

    event.preventDefault();
    form.dataset.postActionPending = "true";
    submitter.disabled = true;

    window
      .fetch(form.action, {
        method: (form.method || "post").toUpperCase(),
        body: payload,
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      .then(function (response) {
        return responseBody(response).then(function (body) {
          if (!response.ok || !body || body.error) {
            throw new Error(body && body.error ? body.error : "");
          }

          return body;
        });
      })
      .then(function (body) {
        postActions.navigate(body.redirect);
      })
      .catch(function (error) {
        showFailure(action, error && error.message);
      })
      .finally(function () {
        delete form.dataset.postActionPending;
        submitter.disabled = false;
      });
  });
})(window, document);
