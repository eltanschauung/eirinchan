(function () {
  function onReady(callback) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', callback, { once: true });
    } else {
      callback();
    }
  }

  function initAnnouncementEditor() {
    var addButton = document.getElementById('blotter-add-row');
    var rows = document.getElementById('blotter-rows');
    var form = rows ? rows.closest('form') : null;
    if (!addButton || !rows || !form || addButton.dataset.bound === 'true') return;

    function renumberRows() {
      Array.prototype.forEach.call(rows.querySelectorAll('tr'), function (row, index) {
        var dateInput = row.querySelector('input[name$="[date]"]');
        var messageInput = row.querySelector('textarea[name$="[message]"]');

        if (dateInput) {
          dateInput.name = 'entries[' + index + '][date]';
        }

        if (messageInput) {
          messageInput.name = 'entries[' + index + '][message]';
        }
      });

      rows.setAttribute('data-next-index', String(rows.querySelectorAll('tr').length));
    }

    function buildRow(index) {
      var row = document.createElement('tr');
      row.innerHTML =
        '<td><input type="text" name="entries[' +
        index +
        '][date]"></td>' +
        '<td><textarea name="entries[' +
        index +
        '][message]" rows="3"></textarea></td>';
      return row;
    }

    addButton.addEventListener('click', function (event) {
      event.preventDefault();
      var row = buildRow(0);

      if (rows.firstElementChild) {
        rows.insertBefore(row, rows.firstElementChild);
      } else {
        rows.appendChild(row);
      }

      renumberRows();

      var firstInput = row.querySelector('input, textarea');
      if (firstInput) {
        firstInput.focus();
      }
    });

    form.addEventListener('submit', renumberRows);
    renumberRows();
    addButton.dataset.bound = 'true';
  }

  function initToggleDisabledTargets() {
    document.querySelectorAll('[data-toggle-disabled-target]').forEach(function (input) {
      if (input.dataset.bound === 'true') return;

      var selector = input.getAttribute('data-toggle-disabled-target');
      var target = selector ? document.querySelector(selector) : null;
      if (!target) return;

      var sync = function () {
        target.disabled = !input.checked;
      };

      sync();
      input.addEventListener('change', sync);
      input.dataset.bound = 'true';
    });
  }

  function initConfirmSubmit() {
    document.querySelectorAll('form[data-confirm-submit]').forEach(function (form) {
      if (form.dataset.bound === 'true') return;

      form.addEventListener('submit', function (event) {
        var message = form.getAttribute('data-confirm-submit');
        if (message && !window.confirm(message)) {
          event.preventDefault();
        }
      });

      form.dataset.bound = 'true';
    });
  }

  function initConfirmButtons() {
    document
      .querySelectorAll('button[data-confirm-message], input[type="submit"][data-confirm-message]')
      .forEach(function (button) {
        if (button.dataset.confirmBound === 'true') return;

        button.addEventListener('click', function (event) {
          var message = button.getAttribute('data-confirm-message');
          if (message && !window.confirm(message)) {
            event.preventDefault();
          }
        });

        button.dataset.confirmBound = 'true';
      });
  }

  onReady(function () {
    initAnnouncementEditor();
    initToggleDisabledTargets();
    initConfirmSubmit();
    initConfirmButtons();
  });
})();
