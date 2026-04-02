/*
 * inline-expanding.js
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/inline-expanding.js
 *
 * Released under the MIT license
 * Copyright (c) 2012-2013 Michael Save <savetheinternet@tinyboard.org>
 * Copyright (c) 2013-2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/inline-expanding.js';
 *
 */

$(document).ready(function(){
	'use strict';

	function bindInlineExpand(root) {
		var $root = root ? $(root) : $(document);
		var $threads;

		if ($root.is('div[id^="thread_"]')) {
			$threads = $root;
		} else {
			$threads = $root.find('div[id^="thread_"]');

			if (!$threads.length) {
				$threads = $root.closest('div[id^="thread_"]');
			}
		}

		$threads.each(function() {
			inline_expand_post.call(this);
		});
	}

	function thumbElement(link) {
		return link.querySelector('canvas.post-image, img.post-image');
	}

	function fullImageElement(link) {
		return link.querySelector('img.full-image');
	}

	var DEFAULT_MAX = 5;  // default maximum image loads
	var inline_expand_post = function() {
		var link = this.querySelectorAll('a[data-inline-expandable="true"]');

		var loadingQueue = (function () {
			var MAX_IMAGES = localStorage.inline_expand_max || DEFAULT_MAX;   // maximum number of images to load concurrently, 0 to disable
			var loading = 0;                                                  // number of images that is currently loading
			var waiting = [];                                                 // waiting queue

			var enqueue = function (ele) {
				waiting.push(ele);
			};
			var dequeue = function () {
				return waiting.shift();
			};
			var update = function() {
				var ele;
				while (loading < MAX_IMAGES || MAX_IMAGES === 0) {
					ele = dequeue();
					if (ele) {
						++loading;
						ele.deferred.resolve();
					} else {
						return;
					}
				}
			};
			return {
				remove: function (ele) {
					var i = waiting.indexOf(ele);
					if (i > -1) {
						waiting.splice(i, 1);
					}
					if ($(ele).data('imageLoading') === 'true') {
						$(ele).data('imageLoading', 'false');
						clearTimeout(ele.timeout);
						--loading;
					}
				},
				add: function (ele) {
					ele.deferred = $.Deferred();
					ele.deferred.done(function () {
						var $loadstart = $.Deferred();
						var thumb = thumbElement(ele);
						var img = fullImageElement(ele);

						if (!thumb || !img) {
							--loading;
							$(ele).data('imageLoading', 'false');
							update();
							return;
						}

						var onLoadStart = function (img) {
							if (img.naturalWidth) {
								$loadstart.resolve(img, thumb);
							} else {
								return (ele.timeout = setTimeout(onLoadStart, 30, img));
							}
						};

						$(img).one('load', function () {
							$.when($loadstart).done(function () {
								//  once fully loaded, update the waiting queue
								--loading;
								$(ele).data('imageLoading', 'false');
								update();
							});
						});
						$loadstart.done(function (img, thumb) {
							thumb.style.display = 'none';
							img.style.display = '';
						});

						img.setAttribute('src', img.dataset.fullImageSrc || ele.href);
						$(ele).data('imageLoading', 'true');
						ele.timeout = onLoadStart(img);
					});

					if (loading < MAX_IMAGES || MAX_IMAGES === 0) {
						++loading;
						ele.deferred.resolve();
					} else {
						enqueue(ele);
					}

				}
			};
		})();

		for (var i = 0; i < link.length; i++) {
			if (typeof link[i] == "object" && !link[i].dataset.inlineExpandBound) {
				link[i].dataset.inlineExpandBound = 'true';
				link[i].onclick = function(e) {
					var img, post_body, still_open, canvas, scroll;
					var thumb = thumbElement(this);
					var padding = 5;
					var boardlist = $('.boardlist')[0];
					
					if (!thumb)
						return true;

					if (thumb.className == 'hidden')
						return false;
					if (e.which == 2 || e.ctrlKey) //  open in new tab
						return true;
					if (!$(this).data('expanded')) {

						if (~this.parentNode.className.indexOf('multifile'))
							$(this).data('width', this.parentNode.style.width);

						this.parentNode.removeAttribute('style');
						$(this).data('expanded', 'true');

						if (thumb.tagName === 'CANVAS') {
							canvas = thumb;
							thumb = thumb.nextElementSibling;
							this.removeChild(canvas);
							canvas.style.display = 'block';
						}

					thumb.style.opacity = '0.4';
					thumb.style.filter = 'alpha(opacity=40)';

					img = fullImageElement(this);
					if (!img) {
						img = document.createElement('img');
						img.className = 'full-image';
						img.style.display = 'none';
						img.setAttribute('alt', 'Fullsized image');
						img.dataset.fullImageSrc = this.href;
						this.appendChild(img);
					}

						loadingQueue.add(this);
					} else {
						loadingQueue.remove(this);

						scroll = false;

						//  scroll to thumb if not triggered by 'shrink all image'
						if (e.target.className == 'full-image') {
							scroll = true;
						}

						if (~this.parentNode.className.indexOf('multifile'))
							this.parentNode.style.width = $(this).data('width');

						thumb.style.opacity = '';
						thumb.style.display = '';
						img = fullImageElement(this);
						if (img) {
							img.style.display = 'none';
							img.removeAttribute('src');
						}
						$(this).removeData('expanded');
						delete thumb.style.filter;

						//  do the scrolling after page reflow
						if (scroll) {
							post_body = $(thumb).closest('.post');

							if (!post_body.length) {
								if (localStorage.no_animated_gif === 'true' && typeof unanimate_gif === 'function') {
									unanimate_gif(thumb);
								}

								return false;
							}

							//  on multifile posts, determin how many other images are still expanded
							still_open = post_body.find('.post-image').filter(function(){
								return $(this).parent().data('expanded') == 'true';
							}).length;

							//  deal with differnt boards' menu styles
							if ($(boardlist).css('position') == 'fixed')
								padding += boardlist.getBoundingClientRect().height;

							if (still_open > 0) {
								if (thumb.getBoundingClientRect().top - padding < 0)
									$(document).scrollTop($(thumb).parent().parent().offset().top - padding);
							} else {
								if (post_body[0].getBoundingClientRect().top - padding < 0)
									$(document).scrollTop(post_body.offset().top - padding);
							}
						}

						if (localStorage.no_animated_gif === 'true' && typeof unanimate_gif === 'function') {
							unanimate_gif(thumb);
						}
					}
					return false;
				};
			}
		}
	};

	//  setting up user option
	if (window.Options && Options.get_tab('general')) {
		Options.extend_tab('general', '<span id="inline-expand-max">'+ _('Number of simultaneous image downloads (0 to disable): ') + 
										'<input type="number" step="1" min="0" size="4"></span>');
		$('#inline-expand-max input')
			.css('width', '50px')
			.val(localStorage.inline_expand_max || DEFAULT_MAX)
			.on('change', function (e) {
				// validation in case some fucktard tries to enter a negative floating point number
				var n = parseInt(e.target.value);
				var val = (n<0) ? 0 : n;

				localStorage.inline_expand_max = val;
			});
	}

	if (window.jQuery) {
		window.bind_inline_expanding = bindInlineExpand;
		bindInlineExpand(document.body);
		$(document).on('fragment_init', function(e, root) {
			bindInlineExpand(root);
		});

		// allow to work with auto-reload.js, etc.
		$(document).on('new_post', function(e, post) {
			bindInlineExpand(post);
		});
	} else {
		inline_expand_post.call(document);
	}
});
