if (active_page == 'catalog') {
	onReady(function() {
		'use strict';

		var catalog;
		try {
			catalog = localStorage.catalog !== undefined ? JSON.parse(localStorage.catalog) : {};
		} catch (_err) {
			catalog = {};
		}

		function saveCatalogState() {
			localStorage.catalog = JSON.stringify(catalog);
		}

		function currentCatalogBase() {
			var sort = document.getElementById('sort_by');
			return sort && sort.dataset && sort.dataset.catalogBase ? sort.dataset.catalogBase : window.location.pathname;
		}

		function currentSearchValue() {
			var field = document.getElementById('search_field');
			return field ? field.value.trim() : '';
		}

		function navigateCatalog(params) {
			var url = new URL(currentCatalogBase(), window.location.origin);

			if (params.sort_by && params.sort_by !== 'bump:desc') {
				url.searchParams.set('sort_by', params.sort_by);
			}

			if (params.search) {
				url.searchParams.set('search', params.search);
			}

			window.location.assign(url.toString());
		}

		$("#sort_by").change(function() {
			var value = this.value || 'bump:desc';
			catalog.sort_by = value;
			saveCatalogState();
			navigateCatalog({ sort_by: value, search: currentSearchValue() });
		});

		$("#image_size").change(function() {
			var value = this.value;
			$(".grid-li").removeClass("grid-size-vsmall");
			$(".grid-li").removeClass("grid-size-small");
			$(".grid-li").removeClass("grid-size-large");
			$(".grid-li").addClass("grid-size-" + value);
			catalog.image_size = value;
			saveCatalogState();
		});

		if (catalog.image_size !== undefined) {
			$('#image_size').val(catalog.image_size).trigger('change');
		}
	});
}
