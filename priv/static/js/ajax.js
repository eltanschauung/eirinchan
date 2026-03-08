/*
 * ajax.js
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/ajax.js
 *
 * Released under the MIT license
 * Copyright (c) 2013 Michael Save <savetheinternet@tinyboard.org>
 * Copyright (c) 2013-2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/ajax.js';
 *
 */

$(window).ready(function() {
	var settings = new script_settings('ajax');
	var do_not_ajax = false;

	// Enable submit button if disabled (cache problem)
	$('input[type="submit"]').removeAttr('disabled');
	
	var setup_form = function($form) {
		$form.submit(function() {
			if (do_not_ajax)
				return true;
			var form = this;
			var $submit = $(form).find('input[type="submit"]');
			var submit_txt = $(this).find('input[type="submit"]').val();
			var is_reply_form = $(form).find('input[name="thread"]').length > 0;
			if (window.FormData === undefined)
				return true;

			var resetSubmit = function() {
				$submit.val(submit_txt);
				$submit.removeAttr('disabled');
			};

			var clearReplyFields = function() {
				$(form).find('input[name="subject"],input[name="file_url"],\
					textarea[name="body"],input[type="file"]').val('').change();
			};

			var formData = new FormData(this);
			formData.append('json_response', '1');
			formData.append('post', submit_txt);

			$(document).trigger("ajax_before_post", formData);

			var updateProgress = function(e) {
				var percentage;
				if (e.position === undefined) { // Firefox
					percentage = Math.round(e.loaded * 100 / e.total);
				}
				else { // Chrome?
					percentage = Math.round(e.position * 100 / e.total);
				}
				$(form).find('input[type="submit"]').val(_('Posting... (#%)').replace('#', percentage));
			};

			$.ajax({
				url: this.action,
				type: 'POST',
				xhr: function() {
					var xhr = $.ajaxSettings.xhr();
					if(xhr.upload) {
						xhr.upload.addEventListener('progress', updateProgress, false);
					}
					return xhr;
				},
				success: function(post_response) {
					if (post_response.error) {
						if (post_response.banned) {
							// You are banned. Must post the form normally so the user can see the ban message.
							do_not_ajax = true;
							$(form).find('input[type="submit"]').each(function() {
								var $replacement = $('<input type="hidden">');
								$replacement.attr('name', $(this).attr('name'));
								$replacement.val(submit_txt);
								$(this)
									.after($replacement)
									.replaceWith($('<input type="button">').val(submit_txt));
							});
							$(form).submit();
						} else {
							alert(post_response.error);
							resetSubmit();
						}
					} else if (post_response.redirect && post_response.id) {
						if (is_reply_form) {
							$submit.val(_('Posted...'));
							$.ajax({
								url: window.location.pathname + window.location.search,
								type: 'GET',
								dataType: 'html',
								success: function(data) {
									var $reply = $(data).find('div.post#reply_' + post_response.id).first();
									var $current_reply = $('div.post#reply_' + post_response.id).first();
									var inserted = false;

									if ($reply.length && !$current_reply.length) {
										var $lastPost = $('div.thread > div.post.reply:last');
										var $newReply = $reply.clone();
										var $clear = $('<br class="clear">');

										if ($lastPost.length) {
											var $after = $lastPost.nextAll('br.clear:first');
											if ($after.length) {
												$after.after($newReply, $clear);
											} else {
												$lastPost.after($newReply, $clear);
											}
										} else {
											var $op = $('div.thread > div.post.op, div.thread > div.op').first();
											var $afterOp = $op.nextAll('br.clear:first');
											if ($afterOp.length) {
												$afterOp.after($newReply, $clear);
											} else {
												$op.after($newReply, $clear);
											}
										}

										$(document).trigger('new_post', $newReply[0]);
										inserted = true;
									}

									var $target = $('div.post#reply_' + post_response.id).first();
									if ($target.length) {
										highlightReply(post_response.id);
										window.location.hash = 'q' + post_response.id;
										$(window).scrollTop($target.offset().top);
										setTimeout(function() { $(window).trigger("scroll"); }, 100);
										clearReplyFields();
										resetSubmit();
										$(document).trigger("ajax_after_post", post_response);
									} else {
										resetSubmit();
										document.location = window.location.pathname + window.location.search + '#q' + post_response.id;
									}
								},
								error: function() {
									resetSubmit();
									document.location = window.location.pathname + window.location.search + '#q' + post_response.id;
								},
								cache: false
							});
						} else {
							$(document).trigger("ajax_after_post", post_response);
							document.location = post_response.redirect;
						}
					} else {
						alert(_('An unknown error occured when posting!'));
						resetSubmit();
					}
				},
				error: function(xhr, status, er) {
					console.log(xhr);
					alert(_('The server took too long to submit your post. Your post was probably still submitted. If it wasn\'t, we might be experiencing issues right now -- please try your post again later. Error information: ') + "<div><textarea>" + JSON.stringify(xhr) + "</textarea></div>");
					resetSubmit();
				},
				data: formData,
				cache: false,
				contentType: false,
				processData: false
			}, 'json');
			
			$submit.val(_('Posting...'));
			$submit.attr('disabled', true);
			
			return false;
		});
	};
	setup_form($('form[name="post"]'));
	$(window).on('quick-reply', function() {
		$('form#quick-reply').off('submit');
		setup_form($('form#quick-reply'));
	});
});
