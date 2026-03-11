(function () {
  function identity(value) {
    return value;
  }

  function onReady(callback) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', callback, { once: true });
    } else {
      callback();
    }
  }

  function appendStyleChooser() {
    if (document.querySelector('div.styles')) return;

    var styles = window.styles || {};
    var styleNames = Object.keys(styles);
    if (styleNames.length === 0) return;

    var selected = window.selectedstyle || localStorage.getItem('stylesheet') || styleNames[0];
    var container = document.createElement('div');
    container.className = 'styles';

    styleNames.forEach(function (styleName) {
      var link = document.createElement('a');
      link.href = 'javascript:void(0);';
      link.textContent = '[' + styleName + ']';
      if (styleName === selected) link.className = 'selected';
      link.onclick = function () {
        if (typeof window.changeStyle === 'function') {
          window.changeStyle(styleName, link);
        }
      };
      container.appendChild(link);
    });

    document.body.appendChild(container);
  }

  function cookieThemeName() {
    var match = document.cookie.match('(?:^|; )theme=([^;]*)');
    return match ? decodeURIComponent(match[1]) : null;
  }

  function basename(path) {
    return (path || '').split('/').pop();
  }

  function findStyleNameByThemeName(themeName) {
    var styles = window.styles || {};
    var styleNames = Object.keys(styles);

    for (var i = 0; i < styleNames.length; i++) {
      var styleName = styleNames[i];
      var style = styles[styleName];
      var configuredThemeName = style && (style.name || window.styleThemeNames[styleName]);

      if (configuredThemeName === themeName) {
        return styleName;
      }
    }

    return null;
  }

  function restoreSavedStyle() {
    var cookieTheme = cookieThemeName();
    var storedLabel = null;

    try {
      storedLabel = localStorage.getItem('stylesheet');
    } catch (_error) {
    }

    var selected =
      (window.styles && window.styles[cookieTheme] ? cookieTheme : null) ||
      findStyleNameByThemeName(cookieTheme) ||
      (window.styles && window.styles[storedLabel] ? storedLabel : null);

    if (selected) {
      window.changeStyle(selected);
    }
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function removeAlertHandler() {
    var handler = document.getElementById('alert_handler');

    if (handler && handler.parentNode) {
      handler.parentNode.removeChild(handler);
    }
  }

  function showAlert(message) {
    removeAlertHandler();

    if (window.jQuery) {
      var $ = window.jQuery;
      var close = function () {
        handler.fadeOut(400, function () {
          handler.remove();
        });
        return false;
      };

      var handler = $("<div id='alert_handler'></div>").hide().appendTo('body');
      $("<div id='alert_background'></div>").appendTo(handler);
      var dialog = $("<div id='alert_div'></div>").appendTo(handler);
      $("<a id='alert_close' href='javascript:void(0)'><i class='fa fa-times'></i></a>").appendTo(dialog);
      $("<div id='alert_message'></div>")
        .html(typeof message === 'string' ? message : escapeHtml(message))
        .appendTo(dialog);
      $("<button class='button alert_button'>OK</button>").appendTo(dialog);

      handler.find('#alert_background, #alert_close, .alert_button').on('click', close);
      handler.fadeIn(400);
      handler.find('.alert_button').trigger('focus');
      return handler[0];
    }

    var handler = document.createElement('div');
    handler.id = 'alert_handler';
    handler.style.visibility = 'visible';

    var background = document.createElement('div');
    background.id = 'alert_background';
    background.addEventListener('click', removeAlertHandler);
    handler.appendChild(background);

    var dialog = document.createElement('div');
    dialog.id = 'alert_div';

    var close = document.createElement('a');
    close.id = 'alert_close';
    close.href = 'javascript:void(0)';
    close.innerHTML = '<i class="fa fa-times"></i>';
    close.addEventListener('click', removeAlertHandler);
    dialog.appendChild(close);

    var content = document.createElement('div');
    content.id = 'alert_message';
    content.innerHTML = typeof message === 'string' ? message : escapeHtml(message);
    dialog.appendChild(content);

    var button = document.createElement('button');
    button.className = 'button alert_button';
    button.type = 'button';
    button.textContent = 'OK';
    button.addEventListener('click', removeAlertHandler);
    dialog.appendChild(button);

    handler.appendChild(dialog);
    document.body.appendChild(handler);

    button.focus();
    return handler;
  }

  function generatePassword() {
    var pass = "";
    var chars =
      window.genpassword_chars ||
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+";

    for (var i = 0; i < 8; i++) {
      var rnd = Math.floor(Math.random() * chars.length);
      pass += chars.substring(rnd, rnd + 1);
    }

    return pass;
  }

  function currentPostForm() {
    return document.forms.post || document.querySelector('form[name="post"]');
  }

  function anySelectedFile(form) {
    return Array.prototype.some.call(form.querySelectorAll('input[type="file"]'), function (field) {
      return (field.files && field.files.length > 0) || Boolean(field.value);
    });
  }

  function postBodyValue(form) {
    var bodyField = form && form.elements ? form.elements["body"] : null;
    return bodyField ? bodyField.value : "";
  }

  function savePostDraft(form) {
    if (!form || !form.elements) return;

    var saved = {};

    try {
      saved = JSON.parse(window.sessionStorage.body || "{}");
    } catch (_error) {
      saved = {};
    }

    saved[document.location] = postBodyValue(form);
    window.sessionStorage.body = JSON.stringify(saved);
  }

  function hasPostPayload(form) {
    if (!form || !form.elements) return false;

    var body = postBodyValue(form);
    var fileUrl = form.elements["file_url"] ? form.elements["file_url"].value : "";
    var embed = form.elements["embed"] ? form.elements["embed"].value : "";

    return body !== "" || anySelectedFile(form) || fileUrl !== "" || embed !== "";
  }

  function persistIdentityFields(form) {
    if (!form || !form.elements) return;

    if (form.elements["name"]) {
      localStorage.name = form.elements["name"].value.replace(/( |^)## .+$/, "");
    }

    if (form.elements["password"]) {
      localStorage.password = form.elements["password"].value;
    }

    if (form.elements["email"]) {
      if (form.elements["email"].value !== "sage") {
        localStorage.email = form.elements["email"].value;
      } else {
        localStorage.removeItem("email");
      }
    }
  }

  function bindIdentityPersistence(form) {
    if (!form || form.dataset.identityPersistenceBound === "true") return;

    ["name", "password", "email"].forEach(function (fieldName) {
      var field = form.elements[fieldName];
      if (!field) return;

      var persist = function () {
        persistIdentityFields(form);
      };

      field.addEventListener("input", persist);
      field.addEventListener("change", persist);
      field.addEventListener("blur", persist);
    });

    form.dataset.identityPersistenceBound = "true";
  }

  function doPost(form) {
    savePostDraft(form);
    return hasPostPayload(form);
  }

  function citeReply(id, withLink) {
    var textarea = document.getElementById('body');

    if (!textarea) return false;

    if (document.selection) {
      textarea.focus();
      var selection = document.selection.createRange();
      selection.text = '>>' + id + '\n';
    } else if (textarea.selectionStart || textarea.selectionStart === 0) {
      var start = textarea.selectionStart;
      var end = textarea.selectionEnd;

      textarea.value =
        textarea.value.substring(0, start) +
        '>>' + id + '\n' +
        textarea.value.substring(end, textarea.value.length);

      textarea.selectionStart += ('>>' + id).length + 1;
      textarea.selectionEnd = textarea.selectionStart;
    } else {
      textarea.value += '>>' + id + '\n';
    }

    if (typeof window.jQuery !== 'undefined') {
      var selectedText = document.getSelection().toString();

      if (selectedText) {
        var body = window.jQuery('#reply_' + id + ', #op_' + id).find('div.body');
        var index = body.text().indexOf(selectedText.replace('\n', ''));

        if (index > -1) {
          textarea.value += '>' + selectedText + '\n';
        }
      }

      window.jQuery(window).trigger('cite', [id, withLink]);
      window.jQuery(textarea).change();
    }

    textarea.focus();
    return false;
  }

  function clearSuccessfulPostsCookie(saved) {
    var cookieName = window.post_success_cookie_name || "eirinchan_posted";
    var cookieValue = window.getCookie(cookieName);

    if (!cookieValue) return saved;

    try {
      var successful = JSON.parse(cookieValue);

      Object.keys(successful).forEach(function(url) {
        saved[url] = null;
      });
    } catch (_error) {
    }

    document.cookie = cookieName + "=;expires=0;path=/;";
    return saved;
  }

  function restoreBodyDraft(form) {
    if (!form || !form.elements || !form.elements["body"]) return;

    var saved = {};

    try {
      saved = JSON.parse(window.sessionStorage.body || "{}");
    } catch (_error) {
      saved = {};
    }

    saved = clearSuccessfulPostsCookie(saved);
    window.sessionStorage.body = JSON.stringify(saved);

    if (saved[document.location]) {
      form.elements["body"].value = saved[document.location];
    }

    if (localStorage.body) {
      form.elements["body"].value = localStorage.body;
      localStorage.body = "";
    }
  }

  function seedPostControlsPassword() {
    var controls = document.forms.postcontrols || document.querySelector('form[name="postcontrols"]');
    if (!controls || !controls.password) return;

    controls.password.value = localStorage.password || "";
  }

  function rememberStuff() {
    var form = currentPostForm();
    if (!form) return;

    if (form.password) {
      if (!localStorage.password) {
        localStorage.password = generatePassword();
      }

      form.password.value = localStorage.password;
    }

    if (localStorage.name && form.elements["name"]) {
      form.elements["name"].value = localStorage.name;
    }

    if (localStorage.email && form.elements["email"]) {
      form.elements["email"].value = localStorage.email;
    }

    bindIdentityPersistence(form);
    persistIdentityFields(form);

    if (window.location.hash.indexOf("q") === 1) {
      window.citeReply(window.location.hash.substring(2), true);
    }

    restoreBodyDraft(form);
    seedPostControlsPassword();
  }

  window._ = window._ || identity;
  window.fmt = window.fmt || function (string, args) {
    return string.replace(/\{([0-9]+)\}/g, function (_, index) {
      return args[index];
    });
  };
  window.datelocale = window.datelocale || {
    days: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
    shortDays: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
    months: [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ],
    shortMonths: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
    AM: 'AM',
    PM: 'PM',
    am: 'am',
    pm: 'pm'
  };
  window.post_date = window.post_date || '%m/%d/%y (%a) %H:%M:%S';
  window.tb_settings = window.tb_settings || {};
  window.script_settings =
    window.script_settings ||
    function (scriptName) {
      this.script_name = scriptName;
      this.get = function (varName, defaultValue) {
        if (
          typeof window.tb_settings === 'undefined' ||
          typeof window.tb_settings[this.script_name] === 'undefined' ||
          typeof window.tb_settings[this.script_name][varName] === 'undefined'
        ) {
          return defaultValue;
        }

        return window.tb_settings[this.script_name][varName];
      };
    };
  window.onReady = window.onReady || onReady;
  window.resourceVersion = window.resourceVersion || '';
  window.selectedstyle = window.selectedstyle || 'Yotsuba';
  window.styles = window.styles || {};
  window.styleThemeNames = window.styleThemeNames || {};

  window.changeStyle =
    window.changeStyle ||
    function (styleName, link) {
      var style = window.styles[styleName];
      var stylePath = style && (style.uri || style);
      if (!stylePath) return;

      var node = document.getElementById('stylesheet');
      if (!node) {
        node = document.createElement('link');
        node.rel = 'stylesheet';
        node.type = 'text/css';
        node.id = 'stylesheet';
        document.head.appendChild(node);
      }

      node.href = stylePath + (window.resourceVersion ? '?v=' + window.resourceVersion : '');
      window.selectedstyle = styleName;
      document.body.setAttribute('data-stylesheet', basename(stylePath));
      try {
        localStorage.setItem('stylesheet', styleName);
      } catch (_error) {
      }

      if (styleName) {
        document.cookie =
          'theme=' + encodeURIComponent(styleName) + '; path=/; max-age=' + 60 * 60 * 24 * 365;
      }

      document.querySelectorAll('div.styles a').forEach(function (styleLink) {
        var matchesCurrentStyle =
          styleLink === link || styleLink.textContent === '[' + styleName + ']';
        styleLink.className = matchesCurrentStyle ? 'selected' : '';
      });

      var chooser = document.querySelector('#style-select select');
      if (chooser) {
        Array.prototype.forEach.call(chooser.options, function (option) {
          option.selected = option.text === styleName;
        });
      }
    };

  window.initStyleChooser = window.initStyleChooser || appendStyleChooser;
  window.showAlert = window.showAlert || showAlert;
  window.generatePassword = window.generatePassword || generatePassword;
  window.getCookie =
    window.getCookie ||
    function (cookieName) {
      var match = document.cookie.match('(?:^|; )' + cookieName + '=([^;]*)');
      return match ? decodeURIComponent(match[1]) : null;
    };
  window.get_cookie = window.get_cookie || window.getCookie;
  window.do_boardlist = window.do_boardlist || function () {};
  window.dopost = window.dopost || doPost;
  window.doPost = window.doPost || window.dopost;
  window.citeReply = window.citeReply || citeReply;
  window.rememberStuff = window.rememberStuff || rememberStuff;
  window.ready =
    window.ready ||
    function () {
      document.body.classList.add('desktop-style');
      window.initStyleChooser();
      restoreSavedStyle();
      seedPostControlsPassword();
    };

  window.alert = function (message) {
    showAlert(message);
  };
})();
