/*
 * expand.js
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/expand.js
 *
 * Released under the MIT license
 * Copyright (c) 2012-2013 Michael Save <savetheinternet@tinyboard.org>
 * Copyright (c) 2013 Czterooki <czterooki1337@gmail.com>
 * Copyright (c) 2013-2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/expand.js';
 *
 */

window.EirinchanInitExpand = function(root) {
	var $root = root ? $(root) : $(document);
	var $omitted = $root.is('span.omitted') ? $root : $root.find('span.omitted');
	$omitted = $omitted.filter(function() {
		return $(this).closest('[id^="thread_"]').length > 0 && !$(this).hasClass('hide-expanded');
	});

	if($omitted.length == 0)
		return;

	var do_expand = function() {
		if ($(this).find('a').length) {
			return;
		}

		$(this)
			.html($(this).text().replace(_("Click reply to view."), '<a href="javascript:void(0)">'+_("Click to expand")+'</a>.'))
			.find('a').click(window.expand_fun = function() {
				var thread = $(this).parents('[id^="thread_"]');
				var id = thread.attr('id').replace(/^thread_/, '');
				$.ajax({
					url: thread.find('p.intro a.post_no:first').attr('href'),
					context: document.body,
					success: function(data) {
						var last_expanded = false;
						$(data).find('div.post.reply').each(function() {
							thread.find('div.hidden').remove();
							var post_in_doc = thread.find('#' + $(this).attr('id'));
							if(post_in_doc.length == 0) {
								if(last_expanded) {
									$(this).addClass('expanded').insertAfter(last_expanded).before('<br class="expanded">');
								} else {
									$(this).addClass('expanded').insertAfter(thread.find('div.post:first')).after('<br class="expanded">');
								}
								last_expanded = $(this);
								$(document).trigger('new_post', this);
							} else {
								last_expanded = post_in_doc;
							}
						});
						

						thread.find("span.omitted").css('display', 'none');

						var insertionPoint = thread.children('span.omitted').last();
						if (!insertionPoint.length) {
							insertionPoint = thread.find('.op div.body').last();
						}

						$('<span class="omitted hide-expanded"><a href="javascript:void(0)">' + _('Hide expanded replies') + '</a>.</span>')
							.insertAfter(insertionPoint)
							.click(function() {
								thread.find('.expanded').remove();
								thread.find(".omitted:not(.hide-expanded)").css('display', '');
								thread.find(".hide-expanded").remove();
							});
					}
				});
			});
	}

	$omitted.each(do_expand);
};

$(document).ready(function(){
	window.EirinchanInitExpand(document);

	$(document).on("new_post", function(e, post) {
		if (!$(post).hasClass("reply")) {
			window.EirinchanInitExpand(post);
		}
	});
});
