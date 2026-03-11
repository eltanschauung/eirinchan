if (
    (active_page === 'thread' || active_page === 'index' || active_page === 'ukko') &&
    window.location.href !== 'https://bantculture.com/bant/res/574.html'
) {
    $(document).ready(function() {
        if (window.Options && Options.get_tab('general')) {
            Options.extend_tab('general', '<label id="remove-spoilers"><input type="checkbox">' + _('Unspoiler & blur spoilers') + '</label>');

            $('#remove-spoilers>input').on('click', function() {
                if ($('#remove-spoilers>input').is(':checked')) {
                    localStorage.unspoiler = 'true';
                } else {
                    localStorage.unspoiler = 'false';
                }
                // Refresh
                location.reload();
            });

            if (typeof localStorage.unspoiler === 'undefined') localStorage.unspoiler = 'true';
            if (localStorage.unspoiler === 'true') $('#remove-spoilers>input').prop('checked', true);
        }

        if (localStorage.unspoiler == 'false' || !(window.URL.createObjectURL && window.File))
            return;

        'use strict';

        // Select all images with the given structure and "spoiler_skillet.png" in src
        var images = $('a[href]:not([href*="mp4"]):not([href*="webm"]) > img[src*="spoiler_skillet.png"]');

        // Loop through each image and update the src and style attributes
        images.each(function() {
            var parentAnchor = $(this).closest('a[href]');
            if (parentAnchor.length) {
                var href = parentAnchor.attr('href');

                $(this).attr('src', href);
                $(this).addClass('spoiler-image');
            }
        });
    });
}
