(function () {
  "use strict";

  function onReady(callback) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback, {once: true});
    } else {
      callback();
    }
  }

  function positivePage(value) {
    var page = Number.parseInt(value, 10);
    return Number.isInteger(page) && page > 0 ? page : 1;
  }

  function validSortField(value) {
    return ["mask", "reason", "board", "created"].indexOf(value) !== -1 ? value : null;
  }

  function currentUnixTime() {
    return Math.floor(Date.now() / 1000);
  }

  function durationText(seconds) {
    var value = Math.max(0, Math.floor(seconds));
    var units = [
      [31536000, "y"],
      [2592000, "mo"],
      [604800, "w"],
      [86400, "d"],
      [3600, "h"],
      [60, "m"]
    ];

    for (var index = 0; index < units.length; index += 1) {
      if (value >= units[index][0]) {
        return Math.floor(value / units[index][0]) + units[index][1];
      }
    }

    return value + "s";
  }

  function relativeText(timestamp, future) {
    var seconds = future ? timestamp - currentUnixTime() : currentUnixTime() - timestamp;
    return future ? "in " + durationText(seconds) : durationText(seconds) + " ago";
  }

  function timestampElement(timestamp, text) {
    var element = document.createElement("time");
    var date = new Date(Number(timestamp) * 1000);

    element.textContent = text;

    if (!Number.isNaN(date.getTime())) {
      element.dateTime = date.toISOString();
      element.title = date.toLocaleString();
    }

    return element;
  }

  function safeManagePath(value) {
    if (typeof value !== "string" || value.indexOf("/manage/") !== 0) {
      return null;
    }

    try {
      var url = new URL(value, window.location.origin);
      return url.origin === window.location.origin && url.pathname.indexOf("/manage/") === 0
        ? url.pathname + url.search + url.hash
        : null;
    } catch (_error) {
      return null;
    }
  }

  function detailElement(label, value) {
    var detail = document.createElement("span");
    var heading = document.createElement("span");

    detail.className = "banlist-detail";
    heading.className = "banlist-detail-label";
    heading.textContent = label + ": ";
    detail.appendChild(heading);

    if (value instanceof Node) {
      detail.appendChild(value);
    } else {
      detail.appendChild(document.createTextNode(String(value)));
    }

    return detail;
  }

  function BanList(form) {
    this.form = form;
    this.url = form.getAttribute("data-banlist-url");
    this.browserPath = new URL(form.action, window.location.origin).pathname;
    this.rows = [];
    this.selectedIds = new Set();
    this.sortField = null;
    this.sortDescending = false;
    this.currentPage = 1;
    this.paginationData = null;
    this.searchTimer = null;
    this.requestController = null;
    this.tableWrap = form.querySelector(".banlist-table-wrap");
    this.tableBody = form.querySelector("#banlist tbody");
    this.pagination = form.querySelector("#banlist-pagination");
    this.status = form.querySelector("#banlist-status");
    this.selectAll = form.querySelector("#select-all");
    this.onlyMine = form.querySelector("#only_mine");
    this.onlyActive = form.querySelector("#only_not_expired");
    this.search = form.querySelector("#search");
    this.unbanButton = form.querySelector("#unban");
  }

  BanList.prototype.start = function () {
    this.applyLocationState();
    this.bindControls();
    this.loadPage(this.currentPage, null);
  };

  BanList.prototype.applyLocationState = function () {
    var params = new URLSearchParams(window.location.search);

    this.currentPage = positivePage(params.get("page"));
    this.sortField = validSortField(params.get("sort_by"));
    this.sortDescending = params.get("sort_dir") === "desc";

    if (this.onlyMine) {
      this.onlyMine.checked = params.get("only_mine") === "1";
    }

    if (this.onlyActive) {
      this.onlyActive.checked = params.get("only_not_expired") === "1";
    }

    if (this.search) {
      this.search.value = params.get("search") || "";
    }
  };

  BanList.prototype.requestParams = function (page) {
    var params = new URLSearchParams();

    if (this.onlyMine && this.onlyMine.checked) params.set("only_mine", "1");
    if (this.onlyActive && this.onlyActive.checked) params.set("only_not_expired", "1");
    if (this.search && this.search.value.trim()) params.set("search", this.search.value.trim());
    if (this.sortField) params.set("sort_by", this.sortField);
    if (this.sortField && this.sortDescending) params.set("sort_dir", "desc");
    if (page > 1) params.set("page", String(page));

    return params;
  };

  BanList.prototype.loadPage = function (page, historyMode) {
    var list = this;
    var requestPage = positivePage(page);
    var params = this.requestParams(requestPage);
    var requestUrl = new URL(this.url, window.location.origin);

    requestUrl.search = params.toString();

    if (this.requestController) {
      this.requestController.abort();
    }

    this.requestController = new AbortController();
    this.status.classList.remove("is-error");
    this.status.hidden = false;
    this.status.textContent = "Loading bans...";

    // Keep fetch's default */* Accept header: this JSON action shares the
    // authenticated browser pipeline, whose content negotiation accepts HTML.
    fetch(requestUrl, {
      credentials: "same-origin",
      signal: this.requestController.signal
    })
      .then(function (response) {
        if (!response.ok) {
          throw new Error("Ban list request failed with status " + response.status);
        }

        return response.json();
      })
      .then(function (payload) {
        if (!payload || !Array.isArray(payload.rows) || !payload.pagination) {
          throw new Error("Ban list response had an invalid shape");
        }

        list.rows = payload.rows;
        list.paginationData = payload.pagination;
        list.currentPage = payload.pagination.page;
        list.tableWrap.hidden = false;
        list.render();

        if (historyMode) {
          var browserUrl = list.browserPath;
          var query = list.requestParams(list.currentPage).toString();
          if (query) browserUrl += "?" + query;
          window.history[historyMode + "State"]({}, "", browserUrl);
        }
      })
      .catch(function (error) {
        if (error.name === "AbortError") return;
        list.status.classList.add("is-error");
        list.status.textContent = "The ban list could not be loaded. Refresh the page to try again.";
      });
  };

  BanList.prototype.bindControls = function () {
    var list = this;

    this.form.querySelectorAll("[data-ban-sort]").forEach(function (button) {
      button.addEventListener("click", function () {
        var field = button.getAttribute("data-ban-sort");

        if (list.sortField === field) {
          list.sortDescending = !list.sortDescending;
        } else {
          list.sortField = field;
          list.sortDescending = false;
        }

        list.loadPage(1, "replace");
      });
    });

    [this.onlyMine, this.onlyActive].forEach(function (control) {
      if (control) {
        control.addEventListener("change", function () {
          list.selectedIds.clear();
          list.loadPage(1, "replace");
        });
      }
    });

    if (this.search) {
      this.search.addEventListener("input", function () {
        window.clearTimeout(list.searchTimer);
        list.searchTimer = window.setTimeout(function () {
          list.selectedIds.clear();
          list.loadPage(1, "replace");
        }, 250);
      });

      this.search.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
          event.preventDefault();
          window.clearTimeout(list.searchTimer);
          list.selectedIds.clear();
          list.loadPage(1, "replace");
        }
      });
    }

    this.pagination.addEventListener("click", function (event) {
      var link = event.target.closest("a[data-ban-page]");
      if (!link) return;
      event.preventDefault();
      list.loadPage(positivePage(link.getAttribute("data-ban-page")), "push");
    });

    window.addEventListener("popstate", function () {
      list.applyLocationState();
      list.selectedIds.clear();
      list.loadPage(list.currentPage, null);
    });

    this.selectAll.addEventListener("change", function () {
      list.rows.forEach(function (row) {
        if (row.access !== false) {
          if (list.selectAll.checked) {
            list.selectedIds.add(String(row.id));
          } else {
            list.selectedIds.delete(String(row.id));
          }
        }
      });

      list.renderRows();
    });

    this.form.addEventListener("submit", function (event) {
      var submitter = event.submitter;

      if (!submitter || submitter.value !== "unban") return;

      if (list.selectedIds.size === 0) {
        event.preventDefault();
        list.status.hidden = false;
        list.status.textContent = "Select at least one ban to remove.";
        return;
      }

      if (!window.confirm("Are you sure you want to unban the selected targets?")) {
        event.preventDefault();
        return;
      }

      list.form.querySelectorAll("input.banlist-selected-hidden").forEach(function (input) {
        input.remove();
      });

      list.selectedIds.forEach(function (id) {
        var input = document.createElement("input");
        input.type = "hidden";
        input.name = "ban_ids[]";
        input.value = id;
        input.className = "banlist-selected-hidden";
        list.form.appendChild(input);
      });
    });
  };

  BanList.prototype.render = function () {
    var pagination = this.paginationData;

    this.renderRows();
    this.renderPagination();
    this.updateSortState();
    this.status.classList.remove("is-error");
    this.status.hidden = false;

    if (pagination.total_entries === 0) {
      this.status.textContent = "No bans match the current filters.";
    } else {
      var first = (pagination.page - 1) * pagination.page_size + 1;
      var last = first + this.rows.length - 1;
      this.status.textContent = "Showing bans " + first + "-" + last + " of " + pagination.total_entries + ".";
    }
  };

  BanList.prototype.renderRows = function () {
    var list = this;
    var fragment = document.createDocumentFragment();

    this.rows.forEach(function (row) {
      fragment.appendChild(list.rowElement(row));
    });

    this.tableBody.replaceChildren(fragment);
    this.updateSelectAll();
  };

  BanList.prototype.renderPagination = function () {
    var list = this;
    var data = this.paginationData;
    var fragment = document.createDocumentFragment();

    this.pagination.replaceChildren();
    this.pagination.hidden = data.total_pages <= 1;
    if (this.pagination.hidden) return;

    fragment.appendChild(this.paginationControl("Previous", data.page - 1, data.page > 1, "prev"));

    var pages = document.createElement("span");
    pages.className = "banlist-pagination-pages";

    data.page_items.forEach(function (page) {
      if (page == null) {
        var ellipsis = document.createElement("span");
        ellipsis.className = "banlist-pagination-ellipsis";
        ellipsis.setAttribute("aria-hidden", "true");
        ellipsis.textContent = "\u2026";
        pages.appendChild(ellipsis);
        return;
      }

      pages.appendChild(document.createTextNode("["));

      if (page === data.page) {
        var current = document.createElement("span");
        current.className = "selected";
        current.setAttribute("aria-current", "page");
        current.textContent = String(page);
        pages.appendChild(current);
      } else {
        pages.appendChild(list.paginationControl(String(page), page, true, null));
      }

      pages.appendChild(document.createTextNode("]"));
    });

    fragment.appendChild(pages);
    fragment.appendChild(this.paginationControl("Next", data.page + 1, data.page < data.total_pages, "next"));
    this.pagination.appendChild(fragment);
  };

  BanList.prototype.paginationControl = function (label, page, enabled, relation) {
    var control;

    if (enabled) {
      control = document.createElement("a");
      control.href = this.browserPath + this.paginationQuery(page);
      control.setAttribute("data-ban-page", String(page));
      if (relation) control.rel = relation;
    } else {
      control = document.createElement("span");
      control.className = "banlist-pagination-disabled";
      control.setAttribute("aria-disabled", "true");
    }

    control.textContent = label;
    return control;
  };

  BanList.prototype.paginationQuery = function (page) {
    var query = this.requestParams(page).toString();
    return query ? "?" + query : "";
  };

  BanList.prototype.rowElement = function (row) {
    var tableRow = document.createElement("tr");
    var expired = row.expires && Number(row.expires) < currentUnixTime();

    if (row.active === false || expired) tableRow.className = "banlist-row-inactive";

    tableRow.appendChild(this.targetCell(row));
    tableRow.appendChild(this.reasonCell(row));
    tableRow.appendChild(this.contextCell(row));
    tableRow.appendChild(this.timingCell(row));

    var editCell = document.createElement("td");
    var editPath = safeManagePath(row.edit_url);
    editCell.setAttribute("data-label", "Edit");

    if (editPath) {
      var editLink = document.createElement("a");
      editLink.href = editPath;
      editLink.textContent = "Edit";
      editCell.appendChild(editLink);
    }

    tableRow.appendChild(editCell);
    return tableRow;
  };

  BanList.prototype.targetCell = function (row) {
    var list = this;
    var cell = document.createElement("td");
    var wrapper = document.createElement("div");
    var checkbox = document.createElement("input");
    var historyPath = safeManagePath(row.history_url);
    var key = historyPath ? document.createElement("a") : document.createElement("span");

    cell.setAttribute("data-label", "Target");
    wrapper.className = "banlist-target";
    checkbox.type = "checkbox";
    checkbox.className = "unban";
    checkbox.name = "ban_ids[]";
    checkbox.value = String(row.id);
    checkbox.checked = this.selectedIds.has(String(row.id));
    checkbox.disabled = row.access === false;
    checkbox.setAttribute("aria-label", "Select ban for " + String(row.mask || "unknown target"));
    checkbox.addEventListener("change", function () {
      if (checkbox.checked) {
        list.selectedIds.add(String(row.id));
      } else {
        list.selectedIds.delete(String(row.id));
      }

      list.updateSelectAll();
    });

    key.className = "banlist-key";
    key.textContent = row.mask || "Unknown target";
    if (historyPath) key.href = historyPath;

    wrapper.appendChild(checkbox);
    wrapper.appendChild(key);
    cell.appendChild(wrapper);
    return cell;
  };

  BanList.prototype.reasonCell = function (row) {
    var cell = document.createElement("td");
    var content = document.createElement("div");
    content.className = "banlist-cell-content";
    cell.setAttribute("data-label", "Reason");
    content.appendChild(document.createTextNode(row.reason || "-"));

    if (row.seen === 1) {
      var seen = document.createElement("span");
      seen.className = "banlist-detail";
      seen.textContent = "Seen by user";
      content.appendChild(seen);
    }

    if (row.message) {
      var message = document.createElement("div");
      var label = document.createElement("strong");
      message.className = "banlist-message";
      label.textContent = "Message: ";
      message.appendChild(label);
      message.appendChild(document.createTextNode(String(row.message)));
      content.appendChild(message);
    }

    cell.appendChild(content);
    return cell;
  };

  BanList.prototype.contextCell = function (row) {
    var cell = document.createElement("td");
    var content = document.createElement("div");
    var board = row.board ? "/" + row.board + "/" : "all boards";
    var staff = row.username || row.staff || "system";

    cell.setAttribute("data-label", "Scope");
    content.className = "banlist-cell-content";
    content.appendChild(detailElement("Board", board));
    content.appendChild(detailElement("Staff", staff));
    cell.appendChild(content);
    return cell;
  };

  BanList.prototype.timingCell = function (row) {
    var cell = document.createElement("td");
    var content = document.createElement("div");
    var created = Number(row.created);

    cell.setAttribute("data-label", "Timing");
    content.className = "banlist-cell-content";
    content.appendChild(detailElement("Set", timestampElement(created, relativeText(created, false))));

    if (!row.expires || Number(row.expires) === 0) {
      content.appendChild(detailElement("Expires", "never"));
    } else {
      var expires = Number(row.expires);
      var expiryText = expires < currentUnixTime()
        ? relativeText(expires, false)
        : relativeText(expires, true);
      content.appendChild(detailElement("Expires", timestampElement(expires, expiryText)));
    }

    cell.appendChild(content);
    return cell;
  };

  BanList.prototype.updateSelectAll = function () {
    var list = this;
    var selectable = this.rows.filter(function (row) {
      return row.access !== false;
    });
    var selectedCount = selectable.filter(function (row) {
      return list.selectedIds.has(String(row.id));
    }).length;

    this.selectAll.checked = selectable.length > 0 && selectedCount === selectable.length;
    this.selectAll.indeterminate = selectedCount > 0 && selectedCount < selectable.length;
    this.unbanButton.disabled = this.selectedIds.size === 0;
  };

  BanList.prototype.updateSortState = function () {
    var list = this;

    this.form.querySelectorAll("[data-ban-sort]").forEach(function (button) {
      var heading = button.closest("th");
      var active = button.getAttribute("data-ban-sort") === list.sortField;

      heading.removeAttribute("aria-sort");
      button.removeAttribute("data-sort-direction");

      if (active) {
        var direction = list.sortDescending ? "descending" : "ascending";
        heading.setAttribute("aria-sort", direction);
        button.setAttribute("data-sort-direction", direction);
      }
    });
  };

  onReady(function () {
    var form = document.querySelector(".banform[data-banlist-url]");
    if (form) new BanList(form).start();
  });
})();
