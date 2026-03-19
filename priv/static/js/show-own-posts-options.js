if (active_page === 'thread' || active_page === 'index' || active_page === 'catalog' || active_page === 'ukko') {
  document.addEventListener('DOMContentLoaded', function () {
    if (!(window.Options && Options.get_tab('general'))) return;
    var runtime = window.EirinchanRuntime || {};
    var readCookie = runtime.readCookie || function(name, fallback) {
      var match = document.cookie.match(new RegExp('(?:^|; )' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '=([^;]*)'));
      return match ? decodeURIComponent(match[1]) : fallback;
    };
    var writeCookie = runtime.writeCookie || function(name, value) {
      document.cookie = name + '=' + encodeURIComponent(value) + '; path=/; max-age=31536000; samesite=lax';
    };

    Options.extend_tab(
      'general',
      '<label id="show-yous"><input type="checkbox">' + _('Show (You)s') + '</label>'
    );

    var enabled = readCookie('show_yous', 'true') !== 'false';
    $('#show-yous>input').prop('checked', enabled);

    $('#show-yous>input').on('click', function () {
      var value = $('#show-yous>input').is(':checked') ? 'true' : 'false';
      writeCookie('show_yous', value, { path: '/', maxAge: 31536000, sameSite: 'lax' });
      location.reload();
    });
  });
}
