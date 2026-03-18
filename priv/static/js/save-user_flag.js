function user_flag() {
	var selector = 'input[name="user_flag"], textarea[name="user_flag"], select[name="user_flag"]';

	var resolveBoardValue = function(scope) {
		var boardField = (scope || document).querySelector('[name="board"]');
		return boardField ? boardField.value : null;
	};

	var storageKeyForScope = function(scope) {
		var boardValue = resolveBoardValue(scope);
		return boardValue ? "flag_" + boardValue : null;
	};

	var storedValueForScope = function(scope) {
		var key = storageKeyForScope(scope);
		if (!key) return null;

		var item = window.localStorage.getItem(key);
		if (item !== null) return item;

		var field = (scope || document).querySelector(selector);
		if (!field) return null;

		var defaultFlag = (field.value || '').toString();
		if (defaultFlag !== '') {
			window.localStorage.setItem(key, defaultFlag);
		}

		return defaultFlag;
	};

	var applyStoredValue = function(scope) {
		var value = storedValueForScope(scope);
		if (value === null) return;

		$(scope || document)
			.find(selector)
			.val(value);
	};

	if (!resolveBoardValue(document)) {
		return;
	}

	var $field = $(selector).first();
	if (!$field.length) {
		return;
	}

	applyStoredValue(document);

	$(document).on('change input', selector, function() {
		var key = storageKeyForScope($(this).closest('form')[0] || document);
		if (!key) return;
		window.localStorage.setItem(key, $(this).val());
	});

	$(window).on('quick-reply', function(_event, formNode) {
		var scope = formNode || document.getElementById('quick-reply') || document;
		applyStoredValue(scope);
	});
}
if (active_page == 'thread' || active_page == 'index') {
	$(document).ready(user_flag);
}
