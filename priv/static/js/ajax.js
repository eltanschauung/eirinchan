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
	var do_not_ajax = false;
	var csrfRefreshRequest = null;

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

	var looksLikeCsrfFailure = function(xhr, extractedMessage) {
		if (!xhr || xhr.status !== 403) {
			return false;
		}

		var message = (extractedMessage || '').toLowerCase();
		if (message && (message.indexOf('csrf') !== -1 || message.indexOf('forgery') !== -1 || message.indexOf('out of date') !== -1)) {
			return true;
		}

		var text = (xhr.responseText || '').toLowerCase();
		return text.indexOf('csrf') !== -1 || text.indexOf('forgery') !== -1;
	};

	var currentCsrfToken = function() {
		var meta = document.querySelector('meta[name="csrf-token"]');
		if (meta && meta.content) {
			return meta.content;
		}

		var field = document.querySelector('input[name="_csrf_token"]');
		return field ? field.value : '';
	};

	var applyCsrfToken = function(token) {
		if (!token) {
			return;
		}

		var meta = document.querySelector('meta[name="csrf-token"]');

		if (meta) {
			meta.setAttribute('content', token);
		}

		$('input[name="_csrf_token"]').val(token);
	};

	var refreshCsrfToken = function() {
		if (csrfRefreshRequest) {
			return csrfRefreshRequest;
		}

		csrfRefreshRequest = $.ajax({
			url: '/csrf-token',
			type: 'GET',
			dataType: 'json',
			cache: false,
			headers: {
				'Cache-Control': 'no-cache'
			}
		})
			.then(function(response) {
				var token = response && response.csrf_token;

				if (!token) {
					return $.Deferred().reject().promise();
				}

				applyCsrfToken(token);
				return token;
			})
			.always(function() {
				csrfRefreshRequest = null;
			});

		return csrfRefreshRequest;
	};

	// Enable submit button if disabled (cache problem)
	$('input[type="submit"]').removeAttr('disabled');
	
	var handle_form_submit = function() {
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
					if (window.EirinchanFrontend && typeof window.EirinchanFrontend.dispatchAjaxAfterPostSuccess === 'function') {
						window.EirinchanFrontend.dispatchAjaxAfterPostSuccess(post_response, form);
					} else {
						$(document).trigger('ajax_after_post', [post_response, form]);
					}
				} catch (e) {
					console.error(e);
				}
			};

			var syncSeenForReply = function(post_response) {
				if (!is_reply_form || typeof window.markWatchedThreadSeen !== 'function') {
					return;
				}

				var threadId = parseInt($(form).find('input[name="thread_id"], input[name="thread"]').first().val(), 10);
				var boardUri = $(form).find('input[name="board"]').first().val();
				var watchLink = document.querySelector('.thread[data-thread-id="' + threadId + '"]');

				if (!threadId || !boardUri || !watchLink || watchLink.dataset.watched !== 'true') {
					return;
				}

				window.markWatchedThreadSeen(boardUri, threadId, post_response.id);
			};

			var syncThreadPageState = function(post_response) {
				if (!is_reply_form || !post_response) {
					return;
				}

				if (post_response.board_page_num) {
					$('#thread_stats_page').text(post_response.board_page_num);
				}

				if (post_response.board_page_path) {
					$('#thread-return, #thread-return-top').attr('href', post_response.board_page_path);
					$('#thread-refresh-target').attr('data-board-page-path', post_response.board_page_path);
				}

				if (post_response.board_page_num) {
					$('#thread-refresh-target').attr('data-board-page-num', post_response.board_page_num);
				}
			};

			var insertReplyMarkup = function(post_response) {
				if (!post_response || !post_response.html) {
					return $('div.post#reply_' + post_response.id).first();
				}

				var $reply = $('div.post#reply_' + post_response.id).first();
				if ($reply.length) {
					return $reply;
				}

				var $newReply = $($.parseHTML(post_response.html, document, true));
				var $container = $('#thread-refresh-target');

				if ($container.length) {
					$container.append($newReply);
				} else {
					var $thread = $('div.thread').first();
					if ($thread.length) {
						$thread.append($newReply);
					}
				}

				return $('div.post#reply_' + post_response.id).first();
			};


			var clearReplyFields = function() {
				$(form).find('input[name="subject"],input[name="file_url"],input[name="embed"],\
					textarea[name="body"],input[type="file"]').val('').change();
			};

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

			var submitAjax = function(retryOnCsrfFailure) {
				var formData = new FormData(form);
				formData.set('_csrf_token', currentCsrfToken());
				formData.set('json_response', '1');
				formData.set('post', submit_txt);

				$(document).trigger("ajax_before_post", [formData, form]);

				$.ajax({
					url: form.action,
					type: 'POST',
					dataType: 'json',
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
							var $reply = insertReplyMarkup(post_response);

							if ($reply.length) {
								var anchor = document.getElementById(String(post_response.id)) || $reply[0];

								try {
									if (typeof window.syncBacklinksFromPost === 'function') {
										window.syncBacklinksFromPost($reply[0]);
									}
								} catch (e) {
									console.error(e);
								}

								clearReplyFields();
								resetSubmit();
								syncSeenForReply(post_response);
								syncThreadPageState(post_response);
								triggerAjaxAfterPost(post_response);

								try {
									if (window.EirinchanFrontend && typeof window.EirinchanFrontend.dispatchNewPost === 'function') {
										window.EirinchanFrontend.dispatchNewPost($reply[0]);
									} else {
										$(document).trigger('new_post', $reply[0]);
									}
								} catch (e) {
									console.error(e);
								}

								window.requestAnimationFrame(function() {
									window.requestAnimationFrame(function() {
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
											$(window).scrollTop($reply.offset().top);
										}

										try {
											highlightReply(post_response.id);
										} catch (e) {
											console.error(e);
										}

										setTimeout(function() { $(window).trigger("scroll"); }, 50);
									});
								});
							} else {
								clearReplyFields();
								resetSubmit();
								syncSeenForReply(post_response);
								syncThreadPageState(post_response);
								triggerAjaxAfterPost(post_response);
								try {
									if (history && history.replaceState) {
										history.replaceState(null, document.title, window.location.pathname + window.location.search + '#' + post_response.id);
									} else {
										window.location.hash = post_response.id;
									}
								} catch (_e) {
									window.location.hash = post_response.id;
								}
								alert(_('Reply posted. Refresh to see it.'));
							}
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
						var csrfFailure = looksLikeCsrfFailure(xhr, extracted);

						if (retryOnCsrfFailure && csrfFailure) {
							refreshCsrfToken().done(function() {
								submitAjax(false);
							}).fail(function() {
								alert(_('Your tab is out of date. Refresh the page and try again.'));
								resetSubmit();
							});
							return;
						}

						if (extracted) {
							alert(extracted);
						} else if (csrfFailure) {
							alert(_('Your tab is out of date. Refresh the page and try again.'));
						} else if (xhr && xhr.status >= 400 && xhr.status < 500) {
							alert(_('Your post was rejected by the server. Refresh and try again.'));
						} else if (xhr && xhr.status >= 500) {
							alert(_('The server hit an internal error while processing your post. Please try again in a moment.'));
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
			};

			submitAjax(true);
			
			$submit.val(_('Posting...'));
			$submit.attr('disabled', true);
			
			return false;
	};
	$(document).off('submit.ajax_post', 'form[data-post-form]');
	$(document).on('submit.ajax_post', 'form[data-post-form]', handle_form_submit);
});
