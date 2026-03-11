if (active_page === 'thread' || active_page === 'index' || active_page === 'catalog' || active_page === 'ukko') {
document.addEventListener('DOMContentLoaded', function() {

    // Add "Show (You)s" option panel item
    if (window.Options && Options.get_tab('general')) {
        Options.extend_tab('general',
            '<label id="show-yous"><input type="checkbox">' + _('Show (You)s') + '</label>'
        );

        $('#show-yous>input').on('click', function() {
            if ($('#show-yous>input').is(':checked')) {
                localStorage.showyous = 'true';
            } else {
                localStorage.showyous = 'false';
            }
            location.reload();
        });

        if (typeof localStorage.showyous === 'undefined') localStorage.showyous = 'false';
        if (localStorage.showyous === 'true') $('#show-yous>input').prop('checked', true);
    }

    // Only run the (You) system if the option is enabled
    if (localStorage.showyous !== 'true') return;

    +function(){
        var update_own = function() {
            if ($(this).is('.you')) return;

            var thread = $(this).parents('[id^="thread_"]').first();
            if (!thread.length) {
                thread = $(this);
            }

            var board = thread.attr('data-board');
            var posts = JSON.parse(localStorage.own_posts || '{}');
            var id = String($(this).attr('id').split('_')[1]);
            var ownPosts = (posts[board] || []).map(String);

            if (ownPosts.indexOf(id) !== -1) {
                $(this).addClass('you');
                $(this).find('span.name').first().append(' <span class="own_post">'+_('(You)')+'</span>');
            }

            // Update references
            $(this).find('div.body:first a:not([rel="nofollow"])').each(function() {
                var postID;
                if (postID = $(this).text().match(/^>>(\d+)$/))
                    postID = postID[1];
                else
                    return;

                if (ownPosts.indexOf(String(postID)) !== -1) {
                    $(this).after(' <small>'+_('(You)')+'</small>');
                }
            });
        };

        var update_all = function() {
            $('div[id^="thread_"], div.post.reply').each(update_own);
        };

        var board = null;

        $(function() {
            board = $('input[name="board"]').first().val();
            update_all();
        });

        $(document).on('ajax_after_post', function(e, r) {
            var posts = JSON.parse(localStorage.own_posts || '{}');
            posts[board] = posts[board] || [];
            posts[board].push(String(r.id));
            localStorage.own_posts = JSON.stringify(posts);
        });

        $(document).on('new_post', function(e, post) {
            var $post = $(post);
            if ($post.is('div.post.reply')) {
                $post.each(update_own);
            } else {
                $post.each(update_own);
                $post.find('div.post.reply').each(update_own);
            }
        });
    }();
});
}
