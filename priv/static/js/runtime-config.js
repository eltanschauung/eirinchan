(function () {
  function escapeCookieName(name) {
    return String(name).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  function metaContent(name) {
    var node = document.querySelector('meta[name="' + name + '"]');
    return node ? node.getAttribute('content') || '' : '';
  }

  function parseJsonMeta(name, fallback) {
    var value = metaContent(name);
    if (!value) return fallback;

    try {
      return JSON.parse(value);
    } catch (_error) {
      return fallback;
    }
  }

  function parseBoolean(value, fallback) {
    if (value === 'true') return true;
    if (value === 'false') return false;
    return fallback;
  }

  function parseInteger(value, fallback) {
    var parsed = parseInt(value, 10);
    return isNaN(parsed) ? fallback : parsed;
  }

  function readCookie(name, fallback) {
    var match = document.cookie.match(new RegExp('(?:^|; )' + escapeCookieName(name) + '=([^;]*)'));
    return match ? decodeURIComponent(match[1]) : fallback;
  }

  function writeCookie(name, value, options) {
    var cookie = String(name) + '=' + encodeURIComponent(value == null ? '' : String(value));
    var settings = options || {};
    var path = settings.path || '/';

    cookie += '; path=' + path;

    if (typeof settings.maxAge === 'number') {
      cookie += '; max-age=' + settings.maxAge;
    }

    if (settings.sameSite) {
      cookie += '; samesite=' + settings.sameSite;
    }

    if (settings.secure) {
      cookie += '; secure';
    }

    document.cookie = cookie;
  }

  function removeCookie(name, options) {
    var settings = options || {};
    writeCookie(name, '', {
      path: settings.path || '/',
      maxAge: 0,
      sameSite: settings.sameSite || 'lax',
      secure: !!settings.secure
    });
  }

  function syncTimezoneCookies() {
    try {
      var timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      var offset = -new Date().getTimezoneOffset();
      var currentTimezone = metaContent('eirinchan:browser-timezone');
      var currentOffset = parseInteger(metaContent('eirinchan:browser-timezone-offset'), 0);

      if (timezone && timezone !== currentTimezone) {
        writeCookie('timezone', timezone, { path: '/', maxAge: 31536000, sameSite: 'lax' });
      }

      if (!isNaN(offset) && offset !== currentOffset) {
        writeCookie('timezone_offset', offset, { path: '/', maxAge: 31536000, sameSite: 'lax' });
      }
    } catch (_error) {
    }
  }

  window.EirinchanRuntime = window.EirinchanRuntime || {};
  window.EirinchanRuntime.metaContent = metaContent;
  window.EirinchanRuntime.parseJsonMeta = parseJsonMeta;
  window.EirinchanRuntime.parseBoolean = parseBoolean;
  window.EirinchanRuntime.parseInteger = parseInteger;
  window.EirinchanRuntime.readCookie = readCookie;
  window.EirinchanRuntime.writeCookie = writeCookie;
  window.EirinchanRuntime.removeCookie = removeCookie;
  window.EirinchanRuntime.syncTimezoneCookies = syncTimezoneCookies;

  if (typeof window.active_page === 'undefined') {
    window.active_page = metaContent('eirinchan:active-page') || '';
  }

  if (typeof window.board_name === 'undefined') {
    window.board_name = metaContent('eirinchan:board-name') || null;
  }

  if (typeof window.thread_id === 'undefined') {
    window.thread_id = metaContent('eirinchan:thread-id') || null;
  }

  if (typeof window.configRoot === 'undefined') {
    window.configRoot = metaContent('eirinchan:config-root') || '/';
  }

  if (typeof window.inMod === 'undefined') {
    window.inMod = false;
  }

  if (typeof window.modRoot === 'undefined') {
    window.modRoot = window.configRoot + (window.inMod ? 'mod.php?/' : '');
  }

  if (typeof window.resourceVersion === 'undefined') {
    window.resourceVersion = metaContent('eirinchan:resource-version') || '';
  }

  if (typeof window.selectedstyle === 'undefined') {
    window.selectedstyle = metaContent('eirinchan:selected-style') || 'Yotsuba';
  }

  if (typeof window.styles === 'undefined' || !window.styles) {
    window.styles = parseJsonMeta('eirinchan:styles', {});
  }

  if (typeof window.stylesheets_board === 'undefined') {
    window.stylesheets_board = parseBoolean(metaContent('eirinchan:stylesheets-board'), true);
  }

  if (typeof window.genpassword_chars === 'undefined') {
    window.genpassword_chars = metaContent('eirinchan:genpassword-chars') || '';
  }

  if (typeof window.post_success_cookie_name === 'undefined') {
    window.post_success_cookie_name =
      metaContent('eirinchan:post-success-cookie-name') || 'eirinchan_posted';
  }

  if (typeof window.watcher_count === 'undefined') {
    window.watcher_count = parseInteger(metaContent('eirinchan:watcher-count'), 0);
  }

  if (typeof window.watcher_unread_count === 'undefined') {
    window.watcher_unread_count = parseInteger(metaContent('eirinchan:watcher-unread-count'), 0);
  }

  if (typeof window.watcher_you_count === 'undefined') {
    window.watcher_you_count = parseInteger(metaContent('eirinchan:watcher-you-count'), 0);
  }

  syncTimezoneCookies();
})();
