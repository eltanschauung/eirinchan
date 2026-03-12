/*
 * auto-reload.js
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/auto-reload.js
 *
 * Brings AJAX to Tinyboard.
 *
 * Released under the MIT license
 * Copyright (c) 2012 Michael Save <savetheinternet@tinyboard.org>
 * Copyright (c) 2013-2014 Marcin Łabanowski <marcin@6irc.net>
 * Copyright (c) 2013 undido <firekid109@hotmail.com>
 * Copyright (c) 2014 Fredrick Brennan <admin@8chan.co>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   //$config['additional_javascript'][] = 'js/titlebar-notifications.js';
 *   $config['additional_javascript'][] = 'js/auto-reload.js';
 *
 * You must have boardlinks or else this script will not load.
 * Search for "$config['boards'] = array(" within your inc/config.php and add something similar to your instance-config.php.
 *
 */


auto_reload_enabled = true; // for watch.js to interop

$(document).ready(function(){
	var is_thread_page = $('div.banner').length != 0 && $(".post.op").length == 1;
	var is_catalog_page = $('body').hasClass('active-catalog') && $('#Grid').length == 1;
	var is_board_page = $('body').hasClass('active-index') && !is_thread_page && !is_catalog_page && $('#board-refresh-target').length == 1;
	var active_poll_request = null;

	if(!is_thread_page && !is_catalog_page && !is_board_page)
		return;
	
	var countdown_interval;

	// Add the update controls inline with the existing thread links.
	var updater_html = " <span id='updater'><a href='#' id='update_thread'>["+_("Update")+"]</a> (<input type='checkbox' id='auto_update_status' checked> "+_("Auto")+") <span id='update_secs'>10</span></span>";
	if ($('#updater').length === 0) {
		if ($('#thread-links').length) {
			$('#thread-links').append(updater_html);
		} else if (is_board_page && $('form[action="/search.php"] p').length) {
			$('form[action="/search.php"] p').append(updater_html);
		} else {
			$('.boardlist.bottom').prev().after("<span id='updater'><a href='#' id='update_thread' style='padding-left:10px'>["+_("Update")+"]</a> (<input type='checkbox' id='auto_update_status' checked> "+_("Auto")+") <span id='update_secs'>10</span></span>");
		}
	}

	// Grab the settings
	var settings = new script_settings('auto-reload');
	var poll_interval_mindelay        = settings.get('min_delay_bottom', 5000);
	var poll_interval_maxdelay        = settings.get('max_delay', 600000);
	var poll_interval_errordelay      = settings.get('error_delay', 30000);

	if (is_board_page) {
		poll_interval_mindelay = 5000;
		poll_interval_maxdelay = 5000;
		poll_interval_errordelay = 5000;
	}

	// number of ms to wait before reloading
	var poll_interval_delay = poll_interval_mindelay;
	var poll_current_time = poll_interval_delay;

	var end_of_page = false;

        var new_posts = 0;
	var first_new_post = null;
	
	var title = document.title;

	if (typeof update_title == "undefined") {
	   var update_title = function() { 
	   	if (new_posts) {
	   		document.title = "("+new_posts+") "+title;
	   	} else {
	   		document.title = title;
	   	}
	   };
	}

	if (typeof add_title_collector != "undefined")
	add_title_collector(function(){
	  return new_posts;
	});

	var window_active = true;
	$(window).focus(function() {
		window_active = true;
		recheck_activated();

		// Reset the delay if needed
		if(settings.get('reset_focus', true)) {
			poll_interval_delay = poll_interval_mindelay;
		}
	});
	$(window).blur(function() {
		window_active = false;
	});
	

	$('#auto_update_status').change(function() {
		if($("#auto_update_status").is(':checked')) {
			auto_update(poll_interval_mindelay);
		} else {
			stop_auto_update();
			$('#update_secs').text("");
		}

		update_live_button_state();
	});
	

	var decrement_timer = function() {
		poll_current_time = poll_current_time - 1000;
		if (poll_current_time <= 0) {
			poll_current_time = 0;
			$('#update_secs').text("0");
			if (is_catalog_page) {
				refresh_if_changed(poll_catalog);
			} else if (is_board_page) {
				refresh_if_changed(poll_board);
			} else {
				refresh_if_changed(poll_thread);
			}
			return;
		}

		$('#update_secs').text(poll_current_time/1000);
	}

	var recheck_activated = function() {
		if (is_catalog_page) {
			return;
		}

		if (new_posts && window_active &&
			$(window).scrollTop() + $(window).height() >=
			$('div.boardlist.bottom').position().top) {

			new_posts = 0;
		}
		update_title();
		first_new_post = null;
	};
	
	// automatically updates the thread after a specified delay
	var auto_update = function(delay) {
		clearInterval(countdown_interval);

		poll_current_time = delay;		
		countdown_interval = setInterval(decrement_timer, 1000);
		$('#update_secs').text(poll_current_time/1000);
		update_live_button_state();
	}
	
	var stop_auto_update = function() {
		clearInterval(countdown_interval);
		update_live_button_state();
	}

	var update_live_button_state = function() {
		var updater = $('#updater');
		var active = $('#auto_update_status').is(':checked') && !$('#auto_update_status').is(':disabled');

		updater.toggleClass('paused', !active);
		updater.toggleClass('active', active);
	}

	var can_start_poll = function() {
		return active_poll_request === null;
	}

	var finish_poll = function() {
		active_poll_request = null;
	}

	var begin_poll = function(request) {
		active_poll_request = request;
	}
		
    	var epoch = (new Date).getTime();
    	var epochold = epoch;
    	
	var timeDiff = function (delay) {
		if((epoch-epochold) > delay) {
			epochold = epoch = (new Date).getTime();
			return true;
		}else{
			epoch = (new Date).getTime();
			return;
		}
	}
	
	var fragment_url = function() {
		var url = new URL(document.location.href);
		url.searchParams.set('fragment', '1');
		return url.toString();
	};

	var has_active_inline_video = function() {
		return Array.prototype.some.call(document.querySelectorAll('video'), function(video) {
			if (!video.offsetParent) return false;
			if (video.closest('#alert_handler')) return false;
			return !!video.controls || !video.paused;
		});
	};

	var should_defer_for_media = function() {
		return has_active_inline_video();
	};

	var fragment_md5_url = function() {
		var url = new URL(document.location.href);
		url.searchParams.set('fragment', 'md5');
		return url.toString();
	};

	var current_fragment_container = function() {
		if (is_catalog_page)
			return document.getElementById('Grid');
		if (is_board_page)
			return document.getElementById('board-refresh-target');
		if (is_thread_page)
			return document.getElementById('thread-refresh-target');
		return null;
	};

	var current_fragment_md5 = function() {
		var container = current_fragment_container();
		if (!container || !container.dataset) {
			return '';
		}

		return container.dataset.fragmentMd5 || '';
	};

	var refresh_if_changed = function(pollFn) {
		if (!can_start_poll()) {
			return false;
		}

		if (should_defer_for_media()) {
			if ($('#auto_update_status').is(':checked')) {
				poll_interval_delay = poll_interval_mindelay;
				auto_update(poll_interval_delay);
			}
			return false;
		}

		stop_auto_update();
		$('#update_secs').text("0");

		var localMd5 = current_fragment_md5();
		var request = $.ajax({
			url: fragment_md5_url(),
			cache: false,
			success: function(data) {
				var serverMd5 = $.trim(data || '');

				if (serverMd5 && localMd5 && serverMd5 === localMd5) {
					if ($('#auto_update_status').is(':checked')) {
						poll_interval_delay = poll_interval_mindelay;
						auto_update(poll_interval_delay);
					}
					return;
				}

				finish_poll();
				pollFn(false);
			},
			error: function() {
				$('#update_secs').text("0");
				if ($('#auto_update_status').is(':checked')) {
					poll_interval_delay = poll_interval_errordelay;
					auto_update(poll_interval_delay);
				}
			},
			complete: function() {
				if (active_poll_request === request) {
					finish_poll();
				}
			}
		});

		begin_poll(request);
		return false;
	};

	var sync_thread_seen = function() {
		if (!is_thread_page || typeof window.markWatchedThreadSeen !== 'function') {
			return;
		}

		var watchLink = document.querySelector('.thread[data-thread-id]');
		if (!watchLink || watchLink.dataset.watched !== 'true') {
			return;
		}

		var replyIds = Array.prototype.map.call(document.querySelectorAll('div.thread div.post[id^="reply_"]'), function(node) {
			return parseInt(node.id.replace('reply_', ''), 10);
		}).filter(function(value) {
			return !isNaN(value);
		});

		var threadId = parseInt(watchLink.dataset.threadId, 10);
		var lastSeenPostId = replyIds.length ? Math.max.apply(null, replyIds) : threadId;
		if (threadId > lastSeenPostId) lastSeenPostId = threadId;

		window.markWatchedThreadSeen(watchLink.dataset.boardUri, threadId, lastSeenPostId);
	};
	
	var poll_catalog = function(manualUpdate) {
		if (!can_start_poll()) {
			return false;
		}

		stop_auto_update();
		$('#update_secs').text("0");

		var request = $.ajax({
			url: fragment_url(),
			cache: false,
			success: function(data) {
				var new_threads = 0;
				var parser = new DOMParser();
				var doc = parser.parseFromString(data, 'text/html');
				var replacement = doc.querySelector('#Grid');
				var currentGrid = document.getElementById('Grid');
				var current_ids = {};
				var seen_ids = {};
				var cards_to_prepend = [];

				if (!replacement || !currentGrid) {
					$('#update_secs').text(_("Unknown error"));
					if ($('#auto_update_status').is(':checked')) {
						poll_interval_delay = poll_interval_errordelay;
						auto_update(poll_interval_delay);
					}
					return;
				}

				if (replacement.dataset && replacement.dataset.fragmentMd5) {
					currentGrid.dataset.fragmentMd5 = replacement.dataset.fragmentMd5;
				}

				$(currentGrid).children('.mix').each(function() {
					var id = this.getAttribute('data-id');
					if (id) {
						current_ids[id] = this;
					}
				});

				Array.prototype.forEach.call(replacement.querySelectorAll('.mix'), function(card) {
					var id = card.getAttribute('data-id');
					var clone = card.cloneNode(true);

					if (id) {
						seen_ids[id] = true;
					}

					if (id && current_ids[id]) {
						current_ids[id].replaceWith(clone);
						current_ids[id] = clone;
					} else {
						new_threads++;
						cards_to_prepend.push(clone);
					}
				});

				$(currentGrid).children('.mix').each(function() {
					var id = this.getAttribute('data-id');
					if (id && !seen_ids[id]) {
						this.remove();
					}
				});

				for (var i = cards_to_prepend.length - 1; i >= 0; i--) {
					currentGrid.insertBefore(cards_to_prepend[i], currentGrid.firstChild);
				}

				if (window.bind_image_hover) {
					window.bind_image_hover(currentGrid);
				}

				if ($('#auto_update_status').is(':checked')) {
					poll_interval_delay = poll_interval_mindelay;
					auto_update(poll_interval_delay);
				} else {
					if (new_threads > 0)
						$('#update_secs').text(fmt(_("Catalog updated with {0} new thread(s)"), [new_threads]));
					else
						$('#update_secs').text(_("No new threads found"));
				}
			},
			error: function(xhr, status_text, error_text) {
				if (status_text == "error" && error_text) {
					$('#update_secs').text("Error: "+error_text);
				} else if (status_text) {
					$('#update_secs').text(_("Error: ")+status_text);
				} else {
					$('#update_secs').text(_("Unknown error"));
				}

				if ($('#auto_update_status').is(':checked')) {
					poll_interval_delay = poll_interval_errordelay;
					auto_update(poll_interval_delay);
				}
			},
			complete: function() {
				finish_poll();
			}
		});
		begin_poll(request);

		return false;
	};

	var poll_board = function(manualUpdate) {
		if (!can_start_poll()) {
			return false;
		}

		stop_auto_update();
		$('#update_secs').text("0");

		var request = $.ajax({
			url: fragment_url(),
			cache: false,
			success: function(data) {
				var parser = new DOMParser();
				var doc = parser.parseFromString(data, 'text/html');
				var replacement = doc.querySelector('#board-refresh-target');
				var current = document.querySelector('#board-refresh-target');
				var currentThreads;
				var hiddenStateById = {};

				if (!replacement || !current) {
					$('#update_secs').text(_("Unknown error"));
					if ($('#auto_update_status').is(':checked')) {
						poll_interval_delay = poll_interval_errordelay;
						auto_update(poll_interval_delay);
					}
					return;
				}

				currentThreads = current.querySelector('#board-threads');
				if (currentThreads) {
					Array.prototype.forEach.call(currentThreads.querySelectorAll('.thread'), function(node) {
						if (!node.id) return;
						hiddenStateById[node.id] = {
							threadHidden: node.classList.contains('thread-hidden'),
							display: node.style.display || '',
							watched: node.dataset ? node.dataset.watched : null
						};
					});
				}

				Array.prototype.forEach.call(replacement.querySelectorAll('#board-threads .thread'), function(node) {
					var state = node.id ? hiddenStateById[node.id] : null;
					if (!state) return;

					if (state.threadHidden) {
						node.classList.add('thread-hidden');
					}
					if (state.display) {
						node.style.display = state.display;
					}
					if (state.watched !== null && node.dataset) {
						node.dataset.watched = state.watched;
					}
				});

				current.replaceWith(replacement);

				$(replacement).find('.post').each(function() {
					if (window.EirinchanFrontend && typeof window.EirinchanFrontend.initPost === 'function') {
						window.EirinchanFrontend.initPost(this);
					} else {
						$(document).trigger('new_post', this);
					}
				});

				if ($('#auto_update_status').is(':checked')) {
					poll_interval_delay = poll_interval_mindelay;
					auto_update(poll_interval_delay);
				} else {
					$('#update_secs').text("5");
				}
			},
			error: function(xhr, status_text, error_text) {
				if (status_text == "error" && error_text) {
					$('#update_secs').text("Error: " + error_text);
				} else if (status_text) {
					$('#update_secs').text("5");
				} else {
					$('#update_secs').text("5");
				}

				if ($('#auto_update_status').is(':checked')) {
					poll_interval_delay = poll_interval_errordelay;
					auto_update(poll_interval_delay);
				}
			},
			complete: function() {
				finish_poll();
			}
		});
		begin_poll(request);

		return false;
	};

	var poll_thread = function(manualUpdate) {
		if (!can_start_poll()) {
			return false;
		}

		stop_auto_update();
		$('#update_secs').text("0");
	
		var request = $.ajax({
			url: fragment_url(),
			cache: false,
			success: function(data) {
				var parser = new DOMParser();
				var doc = parser.parseFromString(data, 'text/html');
				var replacement = doc.querySelector('#thread-refresh-target');
				var loaded_posts = 0;	// the number of new posts loaded in this update
				var elementsToAppend = [];
				var insertedPostIds = [];
				if (replacement && replacement.dataset && replacement.dataset.fragmentMd5) {
					var currentContainer = document.getElementById('thread-refresh-target');
					if (currentContainer) {
						currentContainer.dataset.fragmentMd5 = replacement.dataset.fragmentMd5;
					}
				}
				$(replacement || data).find('div.post.reply').each(function() {
					var id = $(this).attr('id');
					if($('#' + id).length == 0) {
						if (!new_posts) {
							first_new_post = this;
						}
						new_posts++;
						loaded_posts++;
						elementsToAppend.push($(this));
						elementsToAppend.push($('<br class="clear">'));
						insertedPostIds.push(id);
					}
				});
				$('div.post:last').next().after(elementsToAppend);
				recheck_activated();
				insertedPostIds.forEach(function(id){
					var inserted = document.getElementById(id);
					if (inserted) {
						if (window.EirinchanFrontend && typeof window.EirinchanFrontend.initPost === 'function') {
							window.EirinchanFrontend.initPost(inserted);
						} else {
							$(document).trigger('new_post', inserted);
						}
					}
				});
				sync_thread_seen();
				time_loaded = Date.now(); // interop with watch.js
				
				
				if ($('#auto_update_status').is(':checked')) {
					poll_interval_delay = poll_interval_mindelay;
					auto_update(poll_interval_delay);
				} else {
					// Decide the message to show if auto update is disabled
					if (loaded_posts > 0)
						$('#update_secs').text(fmt(_("Thread updated with {0} new post(s)"), [loaded_posts]));
					else
						$('#update_secs').text(_("No new posts found"));
				}
			},
			error: function(xhr, status_text, error_text) {
				if (status_text == "error") {
					if (error_text == "Not Found") {
						$('#update_secs').text(_("Thread deleted or pruned"));
						$('#auto_update_status').prop('checked', false);
						$('#auto_update_status').prop('disabled', true); // disable updates if thread is deleted
						return;
					} else {
						$('#update_secs').text("Error: "+error_text);
					}
				} else if (status_text) {
					$('#update_secs').text(_("Error: ")+status_text);
				} else {
					$('#update_secs').text(_("Unknown error"));
				}
				
				// Keep trying to update
				if ($('#auto_update_status').is(':checked')) {
					poll_interval_delay = poll_interval_errordelay;
					auto_update(poll_interval_delay);
				}
			},
			complete: function() {
				finish_poll();
			}
		});
		begin_poll(request);
		
		return false;
	};
	
	if (is_thread_page) {
		$(window).scroll(function() {
			recheck_activated();
			
			// if the newest post is not visible
			if($(this).scrollTop() + $(this).height() <
				$('div.post:last').position().top + $('div.post:last').height()) {
				end_of_page = false;
				return;
			} else {
				if($("#auto_update_status").is(':checked') && timeDiff(poll_interval_mindelay)) {
					poll_thread(manualUpdate = true);
				}
				end_of_page = true;
			}
		});
	}

	$('#update_thread').on('click', function() {
		var checkbox = $('#auto_update_status');
		checkbox.prop('checked', !checkbox.is(':checked'));
		checkbox.trigger('change');
		return false;
	});

	update_live_button_state();

	if($("#auto_update_status").is(':checked')) {
		auto_update(poll_interval_delay);
	}
});
