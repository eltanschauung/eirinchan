/*
 * download-original.js
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/download-original.js
 *
 * Makes image filenames clickable, allowing users to download and save files as their original filename.
 * Only works in newer browsers. http://caniuse.com/#feat=download
 *
 * Released under the MIT license
 * Copyright (c) 2012-2013 Michael Save <savetheinternet@tinyboard.org>
 * Copyright (c) 2013-2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/download-original.js';
 *
 */

$(document).ready(function(){

        if (window.Options && Options.get_tab('general')) {
                Options.extend_tab('general', '<label id="add-filename-downloads"><input type="checkbox">' + _('Add filename downloads') + '</label>');

                $('#add-filename-downloads>input').on('click', function() {
                        if ($('#add-filename-downloads>input').is(':checked')) {
                                localStorage.downloadoriginal = 'true';
                        } else {
                                localStorage.downloadoriginal = 'false';
                        }
                        //Refresh
                        location.reload();
                });

                if (typeof localStorage.downloadoriginal === 'undefined') localStorage.downloadoriginal = 'false';
                if (localStorage.downloadoriginal === 'true') $('#add-filename-downloads>input').prop('checked', true);
        }

	if (localStorage.downloadoriginal == 'false' || !(window.URL.createObjectURL && window.File))
        	return;

	var do_original_filename = function() {
		var filename, truncated;
		if ($(this).attr('title')) {
			filename = $(this).attr('title');
			truncated = true;
		} else {
			filename = $(this).text();
		}
		
		$(this).replaceWith(
			$('<a></a>')
				.attr('download', filename)
				.append($(this).contents())
				.attr('href', $(this).parent().parent().find('a').attr('href'))
				.attr('title', _('Save as original filename') + (truncated ? ' (' + filename + ')' : ''))
			);
	};

	$('.postfilename').each(do_original_filename);

        $(document).on('new_post', function(e, post) {
		$(post).find('.postfilename').each(do_original_filename);
	});
});
