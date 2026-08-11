(function (window, document) {
  "use strict";

  var runtime = window.EirinchanRuntime || {};
  var persistentFields = ["name", "email", "user_flag", "tag", "no_country"];
  var draftFields = [
    "password",
    "subject",
    "body",
    "spoiler",
    "capcode",
    "raw",
    "captcha",
    "g-recaptcha-response",
    "h-captcha-response",
    "antispam_answer"
  ];

  function readJson(kind, key) {
    if (runtime.readJsonStorage) return runtime.readJsonStorage(kind, key, {});

    try {
      var target = kind === "session" ? window.sessionStorage : window.localStorage;
      return JSON.parse(target.getItem(key) || "{}");
    } catch (_error) {
      return {};
    }
  }

  function writeJson(kind, key, value) {
    if (runtime.writeJsonStorage) return runtime.writeJsonStorage(kind, key, value);

    try {
      var target = kind === "session" ? window.sessionStorage : window.localStorage;
      target.setItem(key, JSON.stringify(value));
      return true;
    } catch (_error) {
      return false;
    }
  }

  function removeSessionValue(key) {
    if (runtime.removeStorage) return runtime.removeStorage("session", key);

    try {
      window.sessionStorage.removeItem(key);
      return true;
    } catch (_error) {
      return false;
    }
  }

  function storageKeys(form) {
    var board = form.dataset.boardUri || "global";
    var draftKey = form.dataset.draftKey || "new";

    return {
      identity: "eirinchan:remember:" + board,
      draft: "eirinchan:draft:" + board + ":" + draftKey
    };
  }

  function applyPersistedForm(form) {
    if (!form.dataset.rememberStuff) return;

    var keys = storageKeys(form);
    var identity = readJson("local", keys.identity);
    var draft = readJson("session", keys.draft);

    Array.prototype.forEach.call(form.elements, function (field) {
      if (!field.name || field.type === "file" || field.type === "hidden") return;

      var value = Object.prototype.hasOwnProperty.call(draft, field.name)
        ? draft[field.name]
        : identity[field.name];

      if (value === undefined) return;
      if (field.type === "checkbox") field.checked = Boolean(value);
      else field.value = value;
    });

    if (
      window.EirinchanFrontend &&
      typeof window.EirinchanFrontend.applyPersistedUserFlag === "function"
    ) {
      window.EirinchanFrontend.applyPersistedUserFlag(form);
    }
  }

  function persistForm(form) {
    if (!form.dataset.rememberStuff) return;

    var keys = storageKeys(form);
    var identity = {};
    var draft = {};

    Array.prototype.forEach.call(form.elements, function (field) {
      if (!field.name || field.type === "file" || field.type === "hidden") return;
      var value = field.type === "checkbox" ? field.checked : field.value;

      if (persistentFields.indexOf(field.name) !== -1) identity[field.name] = value;
      if (draftFields.indexOf(field.name) !== -1) draft[field.name] = value;
    });

    writeJson("local", keys.identity, identity);
    writeJson("session", keys.draft, draft);
  }

  function revealCaptcha(form) {
    if (form.dataset.captchaLoaded === "1") return;
    form.dataset.captchaLoaded = "1";

    Array.prototype.forEach.call(form.querySelectorAll("[data-captcha-lazy]"), function (node) {
      node.hidden = false;
      if (node.matches("input, select, textarea")) node.disabled = false;

      Array.prototype.forEach.call(node.querySelectorAll("input, select, textarea"), function (field) {
        field.disabled = false;
      });
    });
  }

  function prepareLazyCaptcha(form) {
    var nodes = form.querySelectorAll("[data-captcha-lazy]");
    if (!nodes.length) return;

    Array.prototype.forEach.call(nodes, function (node) {
      node.hidden = true;
      if (node.matches("input, select, textarea")) node.disabled = true;

      Array.prototype.forEach.call(node.querySelectorAll("input, select, textarea"), function (field) {
        field.disabled = true;
      });
    });

    form.addEventListener("focusin", function () {
      revealCaptcha(form);
    });
    form.addEventListener("submit", function () {
      revealCaptcha(form);
    });
  }

  function insertQuote(textarea, postId) {
    if (!textarea || !postId) return;

    var prefix = textarea.value && !textarea.value.endsWith("\n") ? "\n" : "";
    var quote = prefix + ">>" + postId + "\n";
    var start = textarea.selectionStart == null ? textarea.value.length : textarea.selectionStart;
    var finish = textarea.selectionEnd == null ? textarea.value.length : textarea.selectionEnd;

    textarea.value = textarea.value.slice(0, start) + quote + textarea.value.slice(finish);
    textarea.selectionStart = start + quote.length;
    textarea.selectionEnd = textarea.selectionStart;
    textarea.focus();
    textarea.dispatchEvent(new Event("input", {bubbles: true}));
  }

  function targetTextarea(link) {
    var quickReplyThread = link.dataset.quickReplyThread;

    if (quickReplyThread) {
      var quickForm = document.querySelector('[data-quick-reply-form="' + quickReplyThread + '"]');
      if (quickForm) {
        var panel = quickForm.closest("[data-quick-reply-panel]");
        if (panel) panel.hidden = false;
        return quickForm.querySelector("[data-post-body]");
      }
    }

    var threadForm = document.querySelector("[data-thread-reply-form]");
    if (threadForm) return threadForm.querySelector("[data-post-body]");

    var newThreadForm = document.querySelector("#new-thread-form");
    return newThreadForm ? newThreadForm.querySelector("[data-post-body]") : null;
  }

  function clearPostedDraft() {
    var cookieName = window.post_success_cookie_name || "eirinchan_posted";

    if (runtime.consumePostSuccessCookies) {
      runtime.consumePostSuccessCookies(cookieName);
      return;
    }

    var value = runtime.readCookie
      ? runtime.readCookie(cookieName, null)
      : (document.cookie.match(/(?:^|; )eirinchan_posted=([^;]+)/) || [])[1];

    if (!value) return;

    try {
      var payload = JSON.parse(decodeURIComponent(value));
      if (payload && typeof payload.draft === "string") {
        removeSessionValue(payload.draft);
      }
    } catch (_error) {
      // A malformed success cookie should not break page initialization.
    }

    if (runtime.removeCookie) runtime.removeCookie(cookieName, {path: "/"});
    else {
      var expired = cookieName + "=; Max-Age=0; path=/; samesite=lax";
      if (window.location.protocol === "https:") expired += "; secure";
      document.cookie = expired;
    }
  }

  function bindThreadPostControls(form) {
    if (!form) return;
    var selectors = form.querySelectorAll("[data-post-select]");
    if (!selectors.length) return;

    function showDeleteError(message) {
      var text = message || "Delete failed. Please try again.";
      if (typeof window.showAlert === "function") window.showAlert(text);
      else window.alert(text);
    }

    function deleteAndReturn(submitter, selected, deleteField, reportField) {
      var returnLink = document.querySelector("#thread-return") ||
        document.querySelector("#thread-return-top");

      if (!returnLink || typeof window.fetch !== "function" || typeof window.FormData !== "function") {
        return false;
      }

      var payload = new window.FormData(form);
      payload.set("delete_post_id", selected.value);
      payload.delete("report_post_id");
      payload.delete("report");
      payload.set("json_response", "1");
      if (submitter.name) payload.set(submitter.name, submitter.value || "Delete");

      submitter.disabled = true;

      window.fetch(form.action, {
        method: (form.method || "post").toUpperCase(),
        body: payload,
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      }).then(function (response) {
        return response.json().then(function (body) {
          return {response: response, body: body};
        });
      }).then(function (result) {
        if (!result.response.ok || !result.body || result.body.error) {
          throw new Error(result.body && result.body.error);
        }

        returnLink.click();
      }).catch(function (error) {
        showDeleteError(error && error.message);
      }).then(function () {
        submitter.disabled = false;
        if (deleteField) deleteField.value = "";
        if (reportField) reportField.value = "";
      });

      return true;
    }

    Array.prototype.forEach.call(selectors, function (selector) {
      selector.addEventListener("change", function () {
        if (!selector.checked) return;
        Array.prototype.forEach.call(selectors, function (other) {
          if (other !== selector) other.checked = false;
        });
      });
    });

    form.addEventListener("submit", function (event) {
      var submitter = event.submitter;
      if (!submitter || !submitter.dataset.postAction) return;

      var selected = Array.prototype.find.call(selectors, function (selector) {
        return selector.checked;
      });

      if (!selected) {
        event.preventDefault();
        return;
      }

      var deleteField = form.querySelector('input[name="delete_post_id"]');
      var reportField = form.querySelector('input[name="report_post_id"]');
      if (deleteField) deleteField.value = "";
      if (reportField) reportField.value = "";
      if (submitter.dataset.postAction === "delete" && deleteField) deleteField.value = selected.value;
      if (submitter.dataset.postAction === "report" && reportField) reportField.value = selected.value;

      if (
        submitter.dataset.postAction === "delete" &&
        deleteAndReturn(submitter, selected, deleteField, reportField)
      ) {
        event.preventDefault();
      }
    });
  }

  function highlight(postId) {
    var node =
      document.getElementById("reply_" + postId) ||
      document.getElementById("op_" + postId) ||
      document.getElementById("thread_" + postId) ||
      document.getElementById(String(postId));

    if (!node) return false;
    node.classList.add("highlighted");
    window.setTimeout(function () {
      node.classList.remove("highlighted");
    }, 1500);
    node.scrollIntoView({block: "nearest"});
    return false;
  }

  Array.prototype.forEach.call(document.querySelectorAll("form[data-remember-stuff]"), function (form) {
    applyPersistedForm(form);
    prepareLazyCaptcha(form);
    form.addEventListener("input", function () {
      persistForm(form);
    });
    form.addEventListener("change", function () {
      persistForm(form);
    });
  });

  clearPostedDraft();
  bindThreadPostControls(document.querySelector("#thread-post-controls"));

  document.addEventListener("click", function (event) {
    var link = event.target.closest("[data-quote-to]");
    if (!link || (link.dataset.citeMode || "inline") === "navigate") return;
    var textarea = targetTextarea(link);
    if (!textarea) return;
    event.preventDefault();
    insertQuote(textarea, link.dataset.quoteTo);
  });

  window.dopost = window.dopost || function () { return true; };
  window.doPost = window.doPost || window.dopost;
  window.ready = window.ready || function () {};
  window.rememberStuff = window.rememberStuff || function () {};
  window.init_file_selector = window.init_file_selector || function () {};
  window.highlightReply = window.highlightReply || highlight;
  window.citeReply =
    window.citeReply ||
    function (postId) {
      var textarea = targetTextarea({dataset: {quoteTo: String(postId)}});
      if (!textarea) return false;
      insertQuote(textarea, String(postId));
      return false;
    };
})(window, document);
