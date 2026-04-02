/*
 * post-hover.js
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/post-hover.js
 *
 * Released under the MIT license
 * Copyright (c) 2012 Michael Save <savetheinternet@tinyboard.org>
 * Copyright (c) 2013-2014 Marcin Łabanowski <marcin@6irc.net>
 * Copyright (c) 2013 Macil Tech <maciltech@gmail.com>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/post-hover.js';
 *
 */

onReady(function() {
	let dontFetchAgain = [];
	let hoverTargets = 'div.body a:not([rel="nofollow"]), p.intro span.mentioned a';
	let hoverRoot = function() {
		return $('body').first();
	};
	let cacheRoot = function() {
		let root = $('form[name="postcontrols"]').first();
		if (!root.length) {
			root = $('body').first();
		}
		return root;
	};

	let insertHiddenReplies = function(board, threadid, replies) {
		let thread = $('[data-board="' + board + '"]#thread_' + threadid);
		if (!thread.length) {
			return;
		}

		let firstReply = thread.find('.post.reply:first');
		if (firstReply.length) {
			replies.each(function() {
				if ($('[data-board="' + board + '"] #' + $(this).attr('id')).length == 0) {
					firstReply.before($(this).hide().addClass('hidden'));
				}
			});
			return;
		}

		let refreshTarget = thread.find('#thread-refresh-target');
		if (refreshTarget.length) {
			replies.each(function() {
				if ($('[data-board="' + board + '"] #' + $(this).attr('id')).length == 0) {
					refreshTarget.append($(this).hide().addClass('hidden'));
				}
			});
		}
	};
	let cacheFetchedPost = function(board, id, fetchedPost) {
		if (!fetchedPost || !fetchedPost.length) {
			return $();
		}

		let existing = $(hoverSelector(board, id, true));
		if (existing.length) {
			return existing.first();
		}

		let cached = fetchedPost
			.first()
			.clone(true, true)
			.hide()
			.attr('data-cached', 'yes')
			.attr('data-board', board);
		cacheRoot().prepend(cached);
		return cached;
	};
	let hoverSelector = function(board, id, includeThread) {
		let selectors = [
			'div.post#reply_' + id + '[data-board="' + board + '"]',
			'div.post#op_' + id + '[data-board="' + board + '"]',
			'[data-board="' + board + '"] div.post#reply_' + id,
			'[data-board="' + board + '"] div.post#op_' + id
		];

		if (includeThread) {
			selectors.push('div#thread_' + id + '[data-board="' + board + '"]');
			selectors.push('[data-board="' + board + '"] div#thread_' + id);
		}

		return selectors.join(', ');
	};

	let initHover = function() {
		let link = $(this);
		let id;
		let matches;
		let href = link.attr('href') || '';
		let crossBoardMatch = href.match(/\/([^\/]+)\/res\/[^#?]+#(\d+)$/);

		if (link.is('[data-thread]')) {
			id = link.attr('data-thread');
		} else if (link.is('[data-highlight-reply]')) {
			id = link.attr('data-highlight-reply');
			matches = [];
			if (crossBoardMatch) {
				matches[1] = crossBoardMatch[1];
				matches[2] = crossBoardMatch[2];
			}
		} else if (matches = link.text().trim().match(/^>>(?:>\/([^\/]+)\/)?(\d+)$/)) {
			id = matches[2];
		} else {
			return;
		}

		let board = $(this);
		while (board.data('board') === undefined) {
			board = board.parent();
		}
		let threadid;
		if (link.is('[data-thread]')) {
			threadid = 0;
		} else {
			threadid = board.attr('id').replace("thread_", "");
		}

		board = board.data('board');

		let parentboard = board;

		if (link.is('[data-thread]')) {
			parentboard = $('form[name="post"] input[name="board"]').val();
		} else if (matches && matches[1] !== undefined) {
			board = matches[1];
		}

		let post = false;
		let hovering = false;
		let hoveredAt;
		link.hover(function(e) {
			hovering = true;
			hoveredAt = {'x': e.pageX, 'y': e.pageY};

			let startHover = function(link) {
				if (post.is(':visible') &&
						post.offset().top >= $(window).scrollTop() &&
						post.offset().top + post.height() <= $(window).scrollTop() + $(window).height()) {
					// post is in view
					post.addClass('highlighted');
				} else {
					let newPost = post.clone();
					newPost.find('>.reply, >br').remove();
					newPost.find('span.mentioned').remove();
					newPost.find('a.post_anchor').remove();

					if (post.is('#op_' + id)) {
						let fileBlock = post.prev('.files');
						if (fileBlock.length) {
							newPost.prepend(fileBlock.clone());
						}
					}

					newPost
						.attr('id', 'post-hover-' + id)
						.attr('data-board', board)
						.addClass('post-hover')
						.css('border-style', 'solid')
						.css('box-shadow', '1px 1px 1px #999')
						.css('display', 'block')
						.css('position', 'absolute')
						.css('font-style', 'normal')
						.css('z-index', '100')
						.addClass('reply').addClass('post');

					// Mount the floating hover at the page root so its absolute
					// positioning always uses document coordinates, regardless of
					// whether the source link came from the post body or intro.
					hoverRoot().append(newPost);

					link.trigger('mousemove');
				}
			};

			post = $(hoverSelector(board, id, link.is('[data-thread]')));
			if (post.length > 0) {
				startHover($(this));
			} else {
				let url = href.replace(/#.*$/, '');

				if ($.inArray(url, dontFetchAgain) != -1) {
					post = $(hoverSelector(board, id, link.is('[data-thread]')));
					if (post.length > 0) {
						if (hovering) {
							startHover(link);
						}
						return;
					}

					dontFetchAgain = $.grep(dontFetchAgain, function(seenUrl) {
						return seenUrl != url;
					});
				}
				dontFetchAgain.push(url);

				$.ajax({
					url: url,
					context: document.body,
					success: function(data) {
						let fetchedThread = $(data).find('div[id^="thread_"]').first();
						if (!fetchedThread.length) {
							return;
						}

						let mythreadid = fetchedThread.attr('id').replace("thread_", "");
						let fetchedReplies = $(data).find('div.post.reply');
						let fetchedTarget = $(data).find('#reply_' + id + ', #op_' + id).first();

						if (mythreadid == threadid && parentboard == board) {
							insertHiddenReplies(board, threadid, fetchedReplies);
						} else if ($('[data-board="' + board + '"]#thread_' + mythreadid).length > 0) {
							insertHiddenReplies(board, mythreadid, fetchedReplies);
						} else {
							fetchedThread.hide().attr('data-cached', 'yes').prependTo(cacheRoot());
						}

						post = $(hoverSelector(board, id, link.is('[data-thread]')));
						if (!post.length) {
							post = cacheFetchedPost(board, id, fetchedTarget);
						}

						if (hovering && post.length > 0) {
							startHover(link);
						}
					}
				});
			}
		}, function() {
			hovering = false;
			if (!post) {
				return;
			}

			post.removeClass('highlighted');
			if (post.hasClass('hidden') || post.data('cached') == 'yes') {
				post.css('display', 'none');
			}
			$('.post-hover').remove();
		}).mousemove(function(e) {
			if (!post) {
				return;
			}

			let hover = $('#post-hover-' + id + '[data-board="' + board + '"]');
			if (hover.length == 0) {
				return;
			}

			let scrollTop = $(window).scrollTop();
			if (link.is("[data-thread]")) {
				scrollTop = 0;
			}
			let epy = e.pageY;
			if (link.is("[data-thread]")) {
				epy -= $(window).scrollTop();
			}

			let top = (epy ? epy : hoveredAt['y']) - 10;

			if (epy < scrollTop + 15) {
				top = scrollTop;
			} else if (epy > scrollTop + $(window).height() - hover.height() - 15) {
				top = scrollTop + $(window).height() - hover.height() - 15;
			}

			hover.css('left', (e.pageX ? e.pageX : hoveredAt['x'])).css('top', top);
		});
	};

	let bindHover = function(root) {
		let $root = root ? $(root) : $(document);
		let $targets = $root.filter(hoverTargets).add($root.find(hoverTargets));

		$targets.each(function() {
			if (this.dataset.postHoverBound === 'true') {
				return;
			}

			this.dataset.postHoverBound = 'true';
			initHover.call(this);
		});
	};

	bindHover(document.body);
	window.init_hover = bindHover;
	$(document).on('fragment_init', function(e, root) {
		bindHover(root);
	});

	// allow to work with auto-reload.js, etc.
	$(document).on('new_post', function(e, post) {
		bindHover(post);
	});
});
