(function () {
  "use strict";

  function onReady(callback) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback, {once: true});
    } else {
      callback();
    }
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

  function parseBoards(form) {
    try {
      var boards = JSON.parse(form.getAttribute("data-my-boards") || "[]");
      return Array.isArray(boards) ? boards : [];
    } catch (_error) {
      return [];
    }
  }

  function BanList(form) {
    this.form = form;
    this.url = form.getAttribute("data-banlist-url");
    this.myBoards = parseBoards(form);
    this.rows = [];
    this.visibleRows = [];
    this.selectedIds = new Set();
    this.sortField = null;
    this.sortDescending = false;
    this.searchTimer = null;
    this.tableWrap = form.querySelector(".banlist-table-wrap");
    this.tableBody = form.querySelector("#banlist tbody");
    this.status = form.querySelector("#banlist-status");
    this.selectAll = form.querySelector("#select-all");
    this.onlyMine = form.querySelector("#only_mine");
    this.onlyActive = form.querySelector("#only_not_expired");
    this.search = form.querySelector("#search");
    this.unbanButton = form.querySelector("#unban");
  }

  BanList.prototype.start = function () {
    var list = this;

    this.bindControls();

    // Keep fetch's default */* Accept header: this JSON action shares the
    // authenticated browser pipeline, whose content negotiation accepts HTML.
    fetch(this.url, {credentials: "same-origin"})
      .then(function (response) {
        if (!response.ok) {
          throw new Error("Ban list request failed with status " + response.status);
        }

        return response.json();
      })
      .then(function (rows) {
        if (!Array.isArray(rows)) {
          throw new Error("Ban list response was not an array");
        }

        list.rows = rows;
        list.tableWrap.hidden = false;
        list.render();
      })
      .catch(function () {
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

        list.render();
      });
    });

    [this.onlyMine, this.onlyActive].forEach(function (control) {
      if (control) {
        control.addEventListener("change", function () {
          list.render();
        });
      }
    });

    if (this.search) {
      this.search.addEventListener("input", function () {
        window.clearTimeout(list.searchTimer);
        list.searchTimer = window.setTimeout(function () {
          list.render();
        }, 120);
      });

      this.search.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
          event.preventDefault();
          window.clearTimeout(list.searchTimer);
          list.render();
        }
      });
    }

    this.selectAll.addEventListener("change", function () {
      list.visibleRows.forEach(function (row) {
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

      if (!submitter || submitter.value !== "unban") {
        return;
      }

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

  BanList.prototype.matchesFilters = function (row) {
    if (this.onlyMine && this.onlyMine.checked && this.myBoards.indexOf(row.board) === -1) {
      return false;
    }

    if (this.onlyActive && this.onlyActive.checked) {
      if (row.active === false || (row.expires && Number(row.expires) < currentUnixTime())) {
        return false;
      }
    }

    var query = this.search ? this.search.value.trim().toLowerCase() : "";
    if (!query) {
      return true;
    }

    return query.split(/\s+/).every(function (term) {
      var match = term.match(/^(mask|reason|board|staff|message):(.*)$/);
      var fields = match ? [match[1]] : ["mask", "reason", "board", "staff", "message"];
      var needle = match ? match[2] : term;

      return fields.some(function (field) {
        var value = row[field];
        return value != null && String(value).toLowerCase().indexOf(needle) !== -1;
      });
    });
  };

  BanList.prototype.sortedRows = function (rows) {
    var field = this.sortField;
    var descending = this.sortDescending;

    if (!field) {
      return rows;
    }

    return rows.slice().sort(function (left, right) {
      var a = left[field] == null ? "" : left[field];
      var b = right[field] == null ? "" : right[field];
      var result;

      if (typeof a === "number" && typeof b === "number") {
        result = a - b;
      } else {
        result = String(a).localeCompare(String(b), undefined, {
          numeric: true,
          sensitivity: "base"
        });
      }

      return descending ? -result : result;
    });
  };

  BanList.prototype.render = function () {
    var list = this;
    var filteredRows = this.rows.filter(function (row) {
      return list.matchesFilters(row);
    });

    this.visibleRows = this.sortedRows(filteredRows);
    this.renderRows();
    this.updateSortState();

    this.status.classList.remove("is-error");
    this.status.hidden = false;

    if (this.visibleRows.length === 0) {
      this.status.textContent = this.rows.length === 0
        ? "There are no active bans."
        : "No bans match the current filters.";
    } else if (this.visibleRows.length === this.rows.length) {
      this.status.textContent = "Showing " + this.rows.length + " ban" + (this.rows.length === 1 ? "." : "s.");
    } else {
      this.status.textContent = "Showing " + this.visibleRows.length + " of " + this.rows.length + " bans.";
    }
  };

  BanList.prototype.renderRows = function () {
    var list = this;
    var fragment = document.createDocumentFragment();

    this.visibleRows.forEach(function (row) {
      fragment.appendChild(list.rowElement(row));
    });

    this.tableBody.replaceChildren(fragment);
    this.updateSelectAll();
  };

  BanList.prototype.rowElement = function (row) {
    var tableRow = document.createElement("tr");
    var expired = row.expires && Number(row.expires) < currentUnixTime();

    if (row.active === false || expired) {
      tableRow.className = "banlist-row-inactive";
    }

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
    if (historyPath) {
      key.href = historyPath;
    }

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
    var selectable = this.visibleRows.filter(function (row) {
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

    if (form) {
      new BanList(form).start();
    }
  });
})();
