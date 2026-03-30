(function () {
  function readJSON(storage, key) {
    try {
      return JSON.parse(storage.getItem(key) || "{}");
    } catch (_error) {
      return {};
    }
  }

  function writeJSON(storage, key, value) {
    try {
      storage.setItem(key, JSON.stringify(value));
    } catch (_error) {
      // Ignore storage failures in degraded browser modes.
    }
  }

  function rememberKeys(form) {
    const boardUri = form.dataset.boardUri || "global";
    const draftKey = form.dataset.draftKey || "new";

    return {
      identity: "eirinchan:remember:" + boardUri,
      draft: "eirinchan:draft:" + boardUri + ":" + draftKey
    };
  }

  function restoreFormState(form) {
    if (!form.dataset.rememberStuff) return;

    const keys = rememberKeys(form);
    const identity = readJSON(window.localStorage, keys.identity);
    const draft = readJSON(window.sessionStorage, keys.draft);

    Array.prototype.forEach.call(form.elements, function (field) {
      if (!field.name || field.type === "file" || field.type === "hidden") return;

      const value =
        Object.prototype.hasOwnProperty.call(draft, field.name)
          ? draft[field.name]
          : identity[field.name];

      if (typeof value === "undefined") return;

      if (field.type === "checkbox") {
        field.checked = Boolean(value);
      } else {
        field.value = value;
      }
    });
  }

  function persistFormState(form) {
    if (!form.dataset.rememberStuff) return;

    const keys = rememberKeys(form);
    const identity = {};
    const draft = {};

    Array.prototype.forEach.call(form.elements, function (field) {
      if (!field.name || field.type === "file" || field.type === "hidden") return;

      const value = field.type === "checkbox" ? field.checked : field.value;

      if (["name", "email", "password", "user_flag", "tag", "no_country"].indexOf(field.name) >= 0) {
        identity[field.name] = value;
      } else if (
        ["subject", "body", "spoiler", "capcode", "raw", "captcha", "g-recaptcha-response", "h-captcha-response", "antispam_answer"].indexOf(field.name) >= 0
      ) {
        draft[field.name] = value;
      }
    });

    writeJSON(window.localStorage, keys.identity, identity);
    writeJSON(window.sessionStorage, keys.draft, draft);
  }

  function clearPostedDrafts() {
    const match = document.cookie.match(/(?:^|; )eirinchan_posted=([^;]+)/);
    if (!match) return;

    const value = decodeURIComponent(match[1]);
    const parts = value.split(":");
    if (parts.length === 2) {
      window.sessionStorage.removeItem("eirinchan:draft:" + parts[0] + ":" + parts[1]);
    }

    document.cookie = "eirinchan_posted=; Max-Age=0; path=/";
  }

  function activateCaptcha(form) {
    if (form.dataset.captchaLoaded === "1") return;

    form.dataset.captchaLoaded = "1";

    Array.prototype.forEach.call(form.querySelectorAll("[data-captcha-lazy]"), function (node) {
      node.hidden = false;

      if (node.matches("input, select, textarea")) {
        node.disabled = false;
      }

      Array.prototype.forEach.call(
        node.querySelectorAll("input, select, textarea"),
        function (field) {
          field.disabled = false;
        }
      );
    });
  }

  function initializeCaptcha(form) {
    const lazyNodes = form.querySelectorAll("[data-captcha-lazy]");
    if (!lazyNodes.length) return;

    Array.prototype.forEach.call(lazyNodes, function (node) {
      node.hidden = true;

      if (node.matches("input, select, textarea")) {
        node.disabled = true;
      }

      Array.prototype.forEach.call(
        node.querySelectorAll("input, select, textarea"),
        function (field) {
          field.disabled = true;
        }
      );
    });

    form.addEventListener("focusin", function () {
      activateCaptcha(form);
    });

    form.addEventListener("submit", function () {
      activateCaptcha(form);
    });
  }

  function appendQuote(textarea, quote) {
    if (!textarea || !quote) return;

    const prefix = textarea.value && !textarea.value.endsWith("\n") ? "\n" : "";
    const insertion = prefix + ">>" + quote + "\n";

    const start = textarea.selectionStart || textarea.value.length;
    const end = textarea.selectionEnd || textarea.value.length;
    const before = textarea.value.slice(0, start);
    const after = textarea.value.slice(end);

    textarea.value = before + insertion + after;
    const cursor = before.length + insertion.length;
    textarea.selectionStart = cursor;
    textarea.selectionEnd = cursor;
    textarea.focus();
  }

  function targetTextarea(link) {
    const quickReplyThread = link.dataset.quickReplyThread;

    if (quickReplyThread) {
      const form = document.querySelector(
        '[data-quick-reply-form="' + quickReplyThread + '"]'
      );

      if (form) {
        const panel = form.closest("[data-quick-reply-panel]");
        if (panel) panel.hidden = false;
        return form.querySelector("[data-post-body]");
      }
    }

    const threadForm = document.querySelector("[data-thread-reply-form]");
    if (threadForm) {
      return threadForm.querySelector("[data-post-body]");
    }

    const newThreadForm = document.querySelector("#new-thread-form");
    if (newThreadForm) {
      return newThreadForm.querySelector("[data-post-body]");
    }

    return null;
  }

  function focusQuoteTarget(id) {
    const target =
      document.getElementById("reply_" + id) ||
      document.getElementById("op_" + id) ||
      document.getElementById("thread_" + id) ||
      document.getElementById(String(id));

    if (!target) return false;

    target.classList.add("highlighted");
    window.setTimeout(function () {
      target.classList.remove("highlighted");
    }, 1500);

    target.scrollIntoView({ block: "nearest" });
    return false;
  }

  function initializePostControls(form) {
    if (!form) return;

    const selectors = form.querySelectorAll("[data-post-select]");
    if (!selectors.length) return;

    Array.prototype.forEach.call(selectors, function (field) {
      field.addEventListener("change", function () {
        if (!field.checked) return;

        Array.prototype.forEach.call(selectors, function (other) {
          if (other !== field) other.checked = false;
        });
      });
    });

    form.addEventListener("submit", function (event) {
      const submitter = event.submitter;
      if (!submitter || !submitter.dataset.postAction) return;

      const selected = Array.prototype.find.call(selectors, function (field) {
        return field.checked;
      });

      if (!selected) {
        event.preventDefault();
        return;
      }

      const deleteField = form.querySelector('input[name="delete_post_id"]');
      const reportField = form.querySelector('input[name="report_post_id"]');

      if (deleteField) deleteField.value = "";
      if (reportField) reportField.value = "";

      if (submitter.dataset.postAction === "delete" && deleteField) {
        deleteField.value = selected.value;
      }

      if (submitter.dataset.postAction === "report" && reportField) {
        reportField.value = selected.value;
      }
    });
  }

  Array.prototype.forEach.call(
    document.querySelectorAll("form[data-remember-stuff]"),
    function (form) {
      restoreFormState(form);
      initializeCaptcha(form);

      form.addEventListener("input", function () {
        persistFormState(form);
      });

      form.addEventListener("change", function () {
        persistFormState(form);
      });
    }
  );

  clearPostedDrafts();
  initializePostControls(document.querySelector("#thread-post-controls"));

  document.addEventListener("click", function (event) {
    const link = event.target.closest("[data-quote-to]");
    if (!link) return;
    if ((link.dataset.citeMode || "inline") === "navigate") return;

    const textarea = targetTextarea(link);
    if (!textarea) return;

    event.preventDefault();
    appendQuote(textarea, link.dataset.quoteTo);
  });

  window.dopost = window.dopost || function () {
    return true;
  };

  window.doPost = window.doPost || window.dopost;
  window.ready = window.ready || function () {};
  window.rememberStuff = window.rememberStuff || function () {};
  window.init_file_selector = window.init_file_selector || function () {};

  window.highlightReply =
    window.highlightReply ||
    function (id) {
      return focusQuoteTarget(id);
    };

  window.citeReply =
    window.citeReply ||
    function (id) {
      const textarea = targetTextarea({ dataset: { quoteTo: String(id) } });
      if (!textarea) return false;
      appendQuote(textarea, String(id));
      return false;
    };
})();
