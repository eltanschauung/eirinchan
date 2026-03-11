if (active_page === 'thread' || active_page === 'index' || active_page === 'catalog' || active_page === 'ukko') {
  document.addEventListener('DOMContentLoaded', function () {
    if (!(window.Options && Options.get_tab('general'))) return;

    Options.extend_tab(
      'general',
      '<label id="show-yous"><input type="checkbox">' + _('Show (You)s') + '</label>'
    );

    var enabled = document.cookie.indexOf('show_yous=false') === -1;
    $('#show-yous>input').prop('checked', enabled);

    $('#show-yous>input').on('click', function () {
      var value = $('#show-yous>input').is(':checked') ? 'true' : 'false';
      document.cookie = 'show_yous=' + value + '; path=/; max-age=31536000; samesite=lax';
      location.reload();
    });
  });
}
