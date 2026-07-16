(function (window, document) {
  "use strict";

  function onReady(callback) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback, {once: true});
    } else {
      callback();
    }
  }

  function createBlotterRow(index) {
    var row = document.createElement("tr");
    var dateCell = document.createElement("td");
    var messageCell = document.createElement("td");
    var date = document.createElement("input");
    var message = document.createElement("textarea");

    date.type = "text";
    date.name = "entries[" + index + "][date]";
    message.name = "entries[" + index + "][message]";
    message.rows = 3;
    dateCell.appendChild(date);
    messageCell.appendChild(message);
    row.append(dateCell, messageCell);
    return row;
  }

  function bindBlotterRows() {
    var addButton = document.getElementById("blotter-add-row");
    var rows = document.getElementById("blotter-rows");
    var form = rows && rows.closest("form");
    if (!addButton || !rows || !form || addButton.dataset.bound === "true") return;

    function renumber() {
      Array.prototype.forEach.call(rows.querySelectorAll("tr"), function (row, index) {
        var date = row.querySelector('input[name$="[date]"]');
        var message = row.querySelector('textarea[name$="[message]"]');
        if (date) date.name = "entries[" + index + "][date]";
        if (message) message.name = "entries[" + index + "][message]";
      });
      rows.dataset.nextIndex = String(rows.querySelectorAll("tr").length);
    }

    addButton.addEventListener("click", function (event) {
      event.preventDefault();
      var row = createBlotterRow(rows.querySelectorAll("tr").length);
      rows.insertBefore(row, rows.firstElementChild);
      renumber();
      var field = row.querySelector("input, textarea");
      if (field) field.focus();
    });

    form.addEventListener("submit", renumber);
    renumber();
    addButton.dataset.bound = "true";
  }

  function bindDisabledToggles() {
    document.querySelectorAll("[data-toggle-disabled-target]").forEach(function (control) {
      if (control.dataset.bound === "true") return;
      var selector = control.getAttribute("data-toggle-disabled-target");
      var target = selector ? document.querySelector(selector) : null;
      if (!target) return;

      function sync() {
        target.disabled = !control.checked;
      }

      sync();
      control.addEventListener("change", sync);
      control.dataset.bound = "true";
    });
  }

  function bindConfirmations() {
    document.querySelectorAll("form[data-confirm-submit]").forEach(function (form) {
      if (form.dataset.bound === "true") return;
      form.addEventListener("submit", function (event) {
        var message = form.getAttribute("data-confirm-submit");
        if (message && !window.confirm(message)) event.preventDefault();
      });
      form.dataset.bound = "true";
    });

    document
      .querySelectorAll('button[data-confirm-message], input[type="submit"][data-confirm-message]')
      .forEach(function (control) {
        if (control.dataset.confirmBound === "true") return;
        control.addEventListener("click", function (event) {
          var message = control.getAttribute("data-confirm-message");
          if (message && !window.confirm(message)) event.preventDefault();
        });
        control.dataset.confirmBound = "true";
      });
  }

  onReady(function () {
    bindBlotterRows();
    bindDisabledToggles();
    bindConfirmations();
  });
})(window, document);
