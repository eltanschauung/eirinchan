/*
 * show-op
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/show-op.js
 *
 * Adds "(OP)" to >>X links when the OP is quoted.
 *
 * Released under the MIT license
 * Copyright (c) 2012 Michael Save <savetheinternet@tinyboard.org>
 * Copyright (c) 2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/show-op.js';
 *
 */

$(document).ready(function(){
	var hasOpMarker = function(link) {
		return $(link).nextAll('small').filter(function() {
			return $(this).text() === '(OP)';
		}).length > 0;
	};

	var showOPLinks = function() {
		var OP;

		if ($('div.banner').length == 0) {
			OP = parseInt($(this).parent().find('div.post.op a.post_no:eq(1)').text(), 10);
		} else {
			OP = parseInt($('div.post.op a.post_no:eq(1)').text(), 10);
		}

		$(this).find('div.body a:not([rel="nofollow"])').each(function() {
			var postID;

			if(postID = $(this).text().match(/^>>(\d+)$/))
				postID = postID[1];
			else
				return;

			if (postID == OP && !hasOpMarker(this)) {
				$(this).after(' <small>(OP)</small>');
			}
		});
	};

	// Initial page render now emits (OP) server-side.
	// Keep a compatibility pass only for dynamically injected legacy fragments.
	$(document).on('new_post', function(e, post) {
		if ($(post).is('div.post.reply')) {
			$(post).each(showOPLinks);
		}
		else {
			$(post).find('div.post.reply').each(showOPLinks);
		}
	});
});

