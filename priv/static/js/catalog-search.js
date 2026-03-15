if (active_page == 'catalog') {
	onReady(function() {
		'use strict';

		var useKeybinds = true;
		var delay = 400;
		var timeoutHandle;

		function catalogBase() {
			var sort = document.getElementById('sort_by');
			return sort && sort.dataset && sort.dataset.catalogBase ? sort.dataset.catalogBase : window.location.pathname;
		}

		function currentSortValue() {
			var sort = document.getElementById('sort_by');
			return sort ? (sort.value || 'bump:desc') : 'bump:desc';
		}

		function currentSearchField() {
			return document.getElementById('search_field');
		}

		function navigateCatalog(searchTerm) {
			var url = new URL(catalogBase(), window.location.origin);
			var sortBy = currentSortValue();
			var trimmedSearch = (searchTerm || '').trim();

			if (sortBy && sortBy !== 'bump:desc') {
				url.searchParams.set('sort_by', sortBy);
			}

			if (trimmedSearch !== '') {
				url.searchParams.set('search', trimmedSearch);
			}

			window.location.assign(url.toString());
		}

		function ensureField() {
			var field = currentSearchField();
			if (field) return field;

			var container = document.querySelector('.catalog_search');
			if (!container) return null;

			field = document.createElement('input');
			field.id = 'search_field';
			field.autocomplete = 'off';
			field.style.border = 'inset 1px';
			container.appendChild(document.createTextNode(' '));
			container.appendChild(field);
			return field;
		}

		function closeSearch(clearSearch) {
			var button = $('#catalog_search_button');
			var field = currentSearchField();

			button.removeData('expanded');
			button.text('Search');

			if (field) {
				field.remove();
			}

			window.clearTimeout(timeoutHandle);

			if (clearSearch) {
				navigateCatalog('');
			}
		}

		function openSearch() {
			var button = $('#catalog_search_button');
			var field = ensureField();

			button.data('expanded', '1');
			button.text('Close');

			if (field) {
				field.focus();
				field.setSelectionRange(field.value.length, field.value.length);
			}
		}

		function searchToggle() {
			if ($('#catalog_search_button').data('expanded')) {
				closeSearch(true);
			} else {
				openSearch();
			}
		}

		$('#catalog_search_button').on('click', function(e) {
			e.preventDefault();
			searchToggle();
		});

		$('.catalog_search').on('keyup', 'input#search_field', function(e) {
			window.clearTimeout(timeoutHandle);
			timeoutHandle = window.setTimeout(navigateCatalog, delay, e.target.value);
		});

		if (useKeybinds) {
			$('body').on('keydown', function(e) {
				if (e.which === 83 && e.target.tagName === 'BODY' && !(e.ctrlKey || e.altKey || e.shiftKey)) {
					e.preventDefault();
					if (currentSearchField()) {
						currentSearchField().focus();
					} else {
						openSearch();
					}
				}
			});

			$('.catalog_search').on('keydown', 'input#search_field', function(e) {
				if (e.which === 27 && !(e.ctrlKey || e.altKey || e.shiftKey)) {
					e.preventDefault();
					closeSearch(true);
				}
			});
		}
	});
}
