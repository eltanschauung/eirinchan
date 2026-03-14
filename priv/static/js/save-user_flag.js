function user_flag() {
	var boardField = document.getElementsByName('board')[0];
	if (!boardField) {
		return;
	}

	var cookieName = "flag_" + boardField.value;
	var legacyStorageKey = "flag_" + boardField.value;
	var selector = 'input[name="user_flag"], textarea[name="user_flag"], select[name="user_flag"]';
	var $field = $(selector).first();
	if (!$field.length) {
		return;
	}

	function readCookie(name) {
		var match = document.cookie.match(new RegExp('(?:^|; )' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '=([^;]*)'));
		return match ? decodeURIComponent(match[1]) : null;
	}

	function writeCookie(value) {
		document.cookie =
			cookieName +
			'=' +
			encodeURIComponent(value) +
			'; path=/; max-age=31536000; samesite=lax';
	}

	var cookieValue = readCookie(cookieName);
	var legacyValue = null;

	try {
		legacyValue = window.localStorage.getItem(legacyStorageKey);
	} catch (err) {
		legacyValue = null;
	}

	if ((cookieValue === null || cookieValue === '') && legacyValue && legacyValue !== $field.val()) {
		writeCookie(legacyValue);
		$field.val(legacyValue);
	}

	$(document).on('change input', selector, function() {
		writeCookie($(this).val());
	});

	$(window).on('quick-reply', function() {
		var value = $(selector).first().val();
		$('form#quick-reply input[name="user_flag"], form#quick-reply textarea[name="user_flag"], form#quick-reply select[name="user_flag"]').val(value);
	});
}
if (active_page == 'thread' || active_page == 'index') {
	$(document).ready(user_flag);
}
