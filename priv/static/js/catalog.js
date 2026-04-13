"catalog" == active_page &&
  onReady(function () {
    "use strict";

    var catalogState;

    try {
      catalogState = localStorage.catalog !== undefined ? JSON.parse(localStorage.catalog) : {};
    } catch (_error) {
      catalogState = {};
    }

    function writeCatalogState() {
      localStorage.catalog = JSON.stringify(catalogState);
    }

    function currentSearch() {
      var field = document.getElementById("search_field");
      return field ? field.value.trim() : "";
    }

    function applyImageSize(size, root) {
      var scope = root ? $(root) : $(document);
      var cards = scope.hasClass("grid-li") ? scope : scope.find(".grid-li");
      var resolvedSize = size || "large";

      cards.removeClass("grid-size-vsmall grid-size-small grid-size-large");
      cards.addClass("grid-size-" + resolvedSize);
    }

    function readHiddenThreads() {
      try {
        return localStorage.hiddenthreads !== undefined
          ? JSON.parse(localStorage.hiddenthreads)
          : {};
      } catch (_error) {
        return {};
      }
    }

    function writeHiddenThreads(hiddenThreads) {
      localStorage.hiddenthreads = JSON.stringify(hiddenThreads);
    }

    function pruneHiddenThreads(hiddenThreads) {
      var cutoff = Math.round(Date.now() / 1000) - 60 * 60 * 24 * 7;

      for (var board in hiddenThreads) {
        if (!Object.prototype.hasOwnProperty.call(hiddenThreads, board)) {
          continue;
        }

        for (var threadId in hiddenThreads[board]) {
          if (
            Object.prototype.hasOwnProperty.call(hiddenThreads[board], threadId) &&
            hiddenThreads[board][threadId] < cutoff
          ) {
            delete hiddenThreads[board][threadId];
          }
        }
      }

      return hiddenThreads;
    }

    var hiddenThreads = pruneHiddenThreads(readHiddenThreads());
    writeHiddenThreads(hiddenThreads);

    function readLegacyPostFilter() {
      try {
        return localStorage.postFilter !== undefined ? JSON.parse(localStorage.postFilter) : {};
      } catch (_error) {
        return {};
      }
    }

    function migrateLegacyCatalogHiddenThreads() {
      var postFilterState = readLegacyPostFilter();
      var boardFilters = (postFilterState.postFilter || {})[board_name];

      if (!boardFilters) {
        return;
      }

      var changed = false;

      if (!hiddenThreads[board_name]) {
        hiddenThreads[board_name] = {};
      }

      for (var threadId in boardFilters) {
        if (!Object.prototype.hasOwnProperty.call(boardFilters, threadId)) {
          continue;
        }

        var filters = boardFilters[threadId];

        if (!Array.isArray(filters)) {
          continue;
        }

        for (var index = 0; index < filters.length; index++) {
          var filter = filters[index];

          if (
            filter &&
            filter.post !== undefined &&
            String(filter.post) === String(threadId) &&
            !filter.uid
          ) {
            if (!hiddenThreads[board_name][String(threadId)]) {
              hiddenThreads[board_name][String(threadId)] = Math.round(Date.now() / 1000);
              changed = true;
            }

            break;
          }
        }
      }

      if (changed) {
        writeHiddenThreads(hiddenThreads);
      }
    }

    migrateLegacyCatalogHiddenThreads();

    function threadIdForCard(card) {
      var id = card && card.getAttribute ? card.getAttribute("data-id") : null;
      return id ? String(id) : "";
    }

    function isThreadHidden(threadId) {
      return !!(
        threadId &&
        hiddenThreads[board_name] &&
        hiddenThreads[board_name][String(threadId)]
      );
    }

    function hideCatalogThread(card, options) {
      var settings = options || {};
      var threadId = threadIdForCard(card);

      if (!threadId) {
        return;
      }

      if (!settings.skipStore) {
        if (!hiddenThreads[board_name]) {
          hiddenThreads[board_name] = {};
        }

        hiddenThreads[board_name][threadId] = Math.round(Date.now() / 1000);
        writeHiddenThreads(hiddenThreads);
      }

      card.classList.add("catalog-thread-hidden");
      card.style.display = "none";
    }

    function showCatalogThread(card) {
      card.classList.remove("catalog-thread-hidden");
      card.style.removeProperty("display");

      if (!card.getAttribute("style")) {
        card.removeAttribute("style");
      }
    }

    function syncHiddenThreads(root) {
      var scope = root ? $(root) : $(document);

      scope
        .filter(".mix[data-id]")
        .add(scope.find(".mix[data-id]"))
        .each(function () {
          if (isThreadHidden(threadIdForCard(this))) {
            hideCatalogThread(this, {skipStore: true});
          } else {
            showCatalogThread(this);
          }
        });
    }

    function catalogBaseUrl() {
      var sortBy = document.getElementById("sort_by");
      return new URL(
        sortBy && sortBy.dataset && sortBy.dataset.catalogBase
          ? sortBy.dataset.catalogBase
          : window.location.pathname,
        window.location.origin
      );
    }

    $("#sort_by").change(function () {
      var sortBy = this.value || "bump:desc";

      catalogState.sort_by = sortBy;
      writeCatalogState();

      var nextUrl = catalogBaseUrl();

      if (sortBy && sortBy !== "bump:desc") {
        nextUrl.searchParams.set("sort_by", sortBy);
      }

      var search = currentSearch();
      if (search) {
        nextUrl.searchParams.set("search", search);
      }

      window.location.assign(nextUrl.toString());
    });

    $("#image_size").change(function () {
      var size = this.value || "large";

      applyImageSize(size, document);
      catalogState.image_size = size;
      writeCatalogState();
    });

    $(document).on("fragment_init", function (_event, root) {
      applyImageSize(catalogState.image_size || $("#image_size").val() || "large", root);
      syncHiddenThreads(root);
    });

    $(document).on("clear_hidden_threads", function () {
      hiddenThreads = {};
      writeHiddenThreads(hiddenThreads);
      syncHiddenThreads(document.body);
    });

    document.addEventListener(
      "click",
      function (event) {
        if (!event.shiftKey) {
          return;
        }

        var card = event.target.closest ? event.target.closest(".mix[data-id]") : null;

        if (!card) {
          return;
        }

        event.preventDefault();
        event.stopPropagation();

        if (typeof event.stopImmediatePropagation === "function") {
          event.stopImmediatePropagation();
        }

        hideCatalogThread(card);
      },
      true
    );

    if (catalogState.image_size !== undefined) {
      $("#image_size").val(catalogState.image_size).trigger("change");
    }

    syncHiddenThreads(document.body);
  });
