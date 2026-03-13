if (active_page === 'thread' || active_page === 'index' || active_page === 'catalog' || active_page === 'ukko') {
document.addEventListener('DOMContentLoaded', function() {
        if (!(window.Options && Options.get_tab('general'))) {
                return;
        }

        var readCookie = function(name) {
                var match = document.cookie.match(new RegExp('(?:^|; )' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '=([^;]*)'));
                return match ? decodeURIComponent(match[1]) : null;
        };

        Options.extend_tab('general', '<label id="add-nav-arrows"><input type="checkbox">' + _('Display navigation arrows') + '</label>');

        var enabled = readCookie('navarrows');
        enabled = enabled !== 'false';
        $('#add-nav-arrows>input').prop('checked', enabled);

        $('#add-nav-arrows>input').on('click', function() {
                var value = $('#add-nav-arrows>input').is(':checked') ? 'true' : 'false';
                document.cookie = 'navarrows=' + value + '; path=/; max-age=31536000; samesite=lax';
                location.reload();
        });
})};
