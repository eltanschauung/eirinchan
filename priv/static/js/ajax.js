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

	var extractAjaxErrorMessage = function(xhr) {
		if (xhr && xhr.responseJSON && xhr.responseJSON.error) {
			return xhr.responseJSON.error;
		}

		if (xhr && typeof xhr.responseText === 'string' && xhr.responseText.length) {
			try {
				var parsed = JSON.parse(xhr.responseText);
				if (parsed && parsed.error) {
					return parsed.error;
				}
			} catch (_error) {
			}
		}

		return null;
	};

	// Enable submit button if disabled (cache problem)
	$('input[type="submit"]').removeAttr('disabled');
	
	var setup_form = function($form) {
		$form.submit(function() {
			if (do_not_ajax)
				return true;
			var form = this;
			var $wrappedForm = $(form);
			var $submit = $(form).find('input[type="submit"]');
			var submit_txt = $(this).find('input[type="submit"]').val();
			var is_reply_form = $(form).find('input[name="thread_id"], input[name="thread"]').length > 0;
			if (window.FormData === undefined)
				return true;
			if ($wrappedForm.data('ajax-posting')) {
				return false;
			}

			var resetSubmit = function() {
				$wrappedForm.removeData('ajax-posting');
				$submit.val(submit_txt);
				$submit.removeAttr('disabled');
			};

			var triggerAjaxAfterPost = function(post_response) {
				try {
					if (window.EirinchanFrontend && typeof window.EirinchanFrontend.afterPostSuccess === 'function') {
						window.EirinchanFrontend.afterPostSuccess(post_response);
					} else {
						$(document).trigger('ajax_after_post', post_response);
					}
				} catch (e) {
					console.error(e);
				}
			};

			var completeReplyArrival = function(postId, onReady, attempts) {
				var remaining = typeof attempts === 'number' ? attempts : 20;
				var $reply = $('div.post#reply_' + postId).first();

				if ($reply.length) {
					window.requestAnimationFrame(function() {
						window.requestAnimationFrame(function() {
							onReady($reply);
						});
					});
					return;
				}

				if (remaining <= 0) {
					onReady($reply);
					return;
				}

				setTimeout(function() {
					completeReplyArrival(postId, onReady, remaining - 1);
				}, 25);
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

			$wrappedForm.data('ajax-posting', true);

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
							var $insertedReply = $();
							var $currentReply = $('div.post#reply_' + post_response.id).first();

							if (post_response.html && !$currentReply.length) {
								var $newReply = $(post_response.html);
								var $lastPost = $('div.thread > div.post.reply:last');

								if ($lastPost.length) {
									var $after = $lastPost.nextAll('br.clear:first');
									if ($after.length) {
										$after.after($newReply);
									} else {
										$lastPost.after($newReply);
									}
								} else {
									var $op = $('div.thread > div.post.op, div.thread > div.op').first();
									var $afterOp = $op.nextAll('br.clear:first');
									if ($afterOp.length) {
										$afterOp.after($newReply);
									} else {
										$op.after($newReply);
									}
								}

								$insertedReply = $('div.post#reply_' + post_response.id).first();
							}

							completeReplyArrival(post_response.id, function($target) {
								if ($target.length) {
									var anchor = document.getElementById(String(post_response.id)) || $target[0];

									clearReplyFields();
									resetSubmit();
									triggerAjaxAfterPost(post_response)

									setTimeout(function() {
										try {
											if (window.EirinchanFrontend && typeof window.EirinchanFrontend.initPost === 'function') {
												window.EirinchanFrontend.initPost($target[0]);
											} else {
												$(document).trigger('new_post', $target[0]);
											}
										} catch (e) {
											console.error(e);
										}
									}, 0);

									try {
										if (history && history.replaceState) {
											history.replaceState(null, document.title, window.location.pathname + window.location.search + '#' + post_response.id);
										} else {
											window.location.hash = post_response.id;
										}
									} catch (_e) {
										window.location.hash = post_response.id;
									}

									if (anchor.scrollIntoView) {
										anchor.scrollIntoView({block: "start"});
									} else {
										$(window).scrollTop($target.offset().top);
									}

									try {
										highlightReply(post_response.id);
									} catch (e) {
										console.error(e);
									}

									setTimeout(function() { $(window).trigger("scroll"); }, 50);
								} else {
									resetSubmit();
									document.location = window.location.pathname + window.location.search + '#' + post_response.id;
								}
							});
						} else {
							triggerAjaxAfterPost(post_response)
							document.location = post_response.redirect;
						}
					} else {
						alert(_('An unknown error occured when posting!'));
						resetSubmit();
					}
				},
				error: function(xhr, status, er) {
					console.log(xhr);
					var extracted = extractAjaxErrorMessage(xhr);
					if (extracted) {
						alert(extracted);
					} else {
						alert(_('The server took too long to submit your post. Your post was probably still submitted. If it wasn\'t, we might be experiencing issues right now -- please try your post again later.'));
					}
					resetSubmit();
				},
				data: formData,
				cache: false,
				contentType: false,
				processData: false,
				complete: function() {
					if ($submit.val() !== _('Posted...')) {
						$wrappedForm.removeData('ajax-posting');
					}
				}
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
