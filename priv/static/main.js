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
    close.textContent = '×';
    close.addEventListener('click', removeAlertHandler);
    dialog.appendChild(close);

    var content = document.createElement('div');
    content.id = 'alert_message';
    content.innerHTML = typeof message === 'string' ? message : escapeHtml(message);
    dialog.appendChild(content);

    var button = document.createElement('button');
    button.className = 'alert_button';
    button.type = 'button';
    button.textContent = 'OK';
    button.addEventListener('click', removeAlertHandler);
    dialog.appendChild(button);

    handler.appendChild(dialog);
    document.body.appendChild(handler);

    button.focus();
    return handler;
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
  window.getCookie =
    window.getCookie ||
    function (cookieName) {
      var match = document.cookie.match('(?:^|; )' + cookieName + '=([^;]*)');
      return match ? decodeURIComponent(match[1]) : null;
    };
  window.get_cookie = window.get_cookie || window.getCookie;
  window.do_boardlist = window.do_boardlist || function () {};
  window.ready =
    window.ready ||
    function () {
      document.body.classList.add('desktop-style');
      window.initStyleChooser();
      restoreSavedStyle();
    };

  window.alert = function (message) {
    showAlert(message);
  };
})();
