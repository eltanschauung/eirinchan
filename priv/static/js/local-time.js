/*
 * local-time.js
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/local-time.js
 *
 * Released under the MIT license
 * Copyright (c) 2012 Michael Save <savetheinternet@tinyboard.org>
 * Copyright (c) 2013-2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   // $config['additional_javascript'][] = 'js/jquery.min.js';
 *   // $config['additional_javascript'][] = 'js/strftime.min.js';
 *   $config['additional_javascript'][] = 'js/local-time.js';
 *
 */

$(document).ready(function(){
	'use strict';
	var runtime = window.EirinchanRuntime || {};

	var syncTimezoneCookie = function() {
		try {
			var tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
			var offset = -new Date().getTimezoneOffset();

			var current = (document.body && document.body.dataset && document.body.dataset.timezone) || '';
			var currentOffset = parseInt((document.body && document.body.dataset && document.body.dataset.timezoneOffset) || '', 10);
			if (tz === current && offset === currentOffset) return;

			if (tz) {
				if (runtime.writeCookie) {
					runtime.writeCookie('timezone', tz, { path: '/', maxAge: 31536000, sameSite: 'lax' });
				} else {
					document.cookie = 'timezone=' + encodeURIComponent(tz) + '; path=/; max-age=31536000; samesite=lax';
				}
			}
			if (!isNaN(offset)) {
				if (runtime.writeCookie) {
					runtime.writeCookie('timezone_offset', offset, { path: '/', maxAge: 31536000, sameSite: 'lax' });
				} else {
					document.cookie = 'timezone_offset=' + offset + '; path=/; max-age=31536000; samesite=lax';
				}
			}
		} catch (err) {
		}
	};

	var iso8601 = function(s) {
		s = s.replace(/\.\d\d\d+/,""); // remove milliseconds
		s = s.replace(/-/,"/").replace(/-/,"/");
		s = s.replace(/T/," ").replace(/Z/," UTC");
		s = s.replace(/([\+\-]\d\d)\:?(\d\d)/," $1$2"); // -04:00 -> -0400
		return new Date(s);
	};
	var zeropad = function(num, count) {
		return [Math.pow(10, count - num.toString().length), num].join('').substr(1);
	};

	var dateformat = (typeof strftime === 'undefined') ? function(t) {
		return zeropad(t.getMonth() + 1, 2) + "/" + zeropad(t.getDate(), 2) + "/" + t.getFullYear().toString().substring(2) +
				" (" + [_("Sun"), _("Mon"), _("Tue"), _("Wed"), _("Thu"), _("Fri"), _("Sat"), _("Sun")][t.getDay()]  + ") " +
				// time
				zeropad(t.getHours(), 2) + ":" + zeropad(t.getMinutes(), 2) + ":" + zeropad(t.getSeconds(), 2);

	} : function(t) {
		// post_date is defined in templates/main.js
		return strftime(window.post_date, t, datelocale);
	};

	function timeDifference(current, previous) {

		var msPerMinute = 60 * 1000;
		var msPerHour = msPerMinute * 60;
		var msPerDay = msPerHour * 24;
		var msPerMonth = msPerDay * 30;
		var msPerYear = msPerDay * 365;

		var elapsed = current - previous;

		if (elapsed < msPerMinute) {
			return 'Just now';
		} else if (elapsed < msPerHour) {
			return Math.round(elapsed/msPerMinute) + (Math.round(elapsed/msPerMinute)<=1 ? ' minute ago':' minutes ago');
		} else if (elapsed < msPerDay ) {
			return Math.round(elapsed/msPerHour ) + (Math.round(elapsed/msPerHour)<=1 ? ' hour ago':' hours ago');
		} else if (elapsed < msPerMonth) {
			return Math.round(elapsed/msPerDay) + (Math.round(elapsed/msPerDay)<=1 ? ' day ago':' days ago');
		} else if (elapsed < msPerYear) {
			return Math.round(elapsed/msPerMonth) + (Math.round(elapsed/msPerMonth)<=1 ? ' month ago':' months ago');
		} else {
			return Math.round(elapsed/msPerYear ) + (Math.round(elapsed/msPerYear)<=1 ? ' year ago':' years ago');
		}
	}

	var do_localtime = function(elem) {	
		var times = elem.getElementsByTagName('time');
		var currentTime = Date.now();

		for(var i = 0; i < times.length; i++) {
			if (times[i].getAttribute('data-local') === 'true' && times[i].getAttribute('title') && times[i].innerHTML.trim() !== '') {
				continue;
			}

			var t = times[i].getAttribute('datetime');
			var postTime = new Date(t);

			times[i].setAttribute('data-local', 'true');

			if (localStorage.show_relative_time === 'false') {
				times[i].innerHTML = dateformat(iso8601(t));
				times[i].setAttribute('title', timeDifference(currentTime, postTime.getTime()));
			} else {
				times[i].innerHTML = dateformat(iso8601(t));
				times[i].setAttribute('title', timeDifference(currentTime, postTime.getTime()));
			}
		
		}
	};

	window.do_localtime = do_localtime;
	syncTimezoneCookie();
	do_localtime(document.body);

	$(document).on('fragment_init', function(e, root) {
		do_localtime(root);
	});

	$(document).on('new_post', function(e, post) {
		do_localtime(post);
	});
});
