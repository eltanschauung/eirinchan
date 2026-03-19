if (active_page === 'thread' || active_page === 'index' || active_page === 'catalog' || active_page === 'ukko') {
document.addEventListener('DOMContentLoaded', function() {
        if (!(window.Options && Options.get_tab('general'))) {
                return;
        }

        var runtime = window.EirinchanRuntime || {};
        var readCookie = runtime.readCookie || function(name, fallback) {
                var match = document.cookie.match(new RegExp('(?:^|; )' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '=([^;]*)'));
                return match ? decodeURIComponent(match[1]) : fallback;
        };
        var writeCookie = runtime.writeCookie || function(name, value) {
                document.cookie = name + '=' + encodeURIComponent(value) + '; path=/; max-age=31536000; samesite=lax';
        };

        Options.extend_tab('general', '<label id="add-nav-arrows"><input type="checkbox">' + _('Display navigation arrows') + '</label>');

        var enabled = readCookie('navarrows', null);
        enabled = enabled !== 'false';
        $('#add-nav-arrows>input').prop('checked', enabled);

        $('#add-nav-arrows>input').on('click', function() {
                var value = $('#add-nav-arrows>input').is(':checked') ? 'true' : 'false';
                writeCookie('navarrows', value, { path: '/', maxAge: 31536000, sameSite: 'lax' });
                location.reload();
        });
})};
