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
    if (!addButton || !rows || addButton.dataset.bound === 'true') return;

    addButton.addEventListener('click', function (event) {
      event.preventDefault();
      var index = parseInt(rows.getAttribute('data-next-index') || '0', 10);
      if (isNaN(index)) index = 0;

      var row = document.createElement('tr');
      var dateCell = document.createElement('td');
      var dateInput = document.createElement('input');
      dateInput.type = 'text';
      dateInput.name = 'entries[' + index + '][date]';
      dateCell.appendChild(dateInput);

      var messageCell = document.createElement('td');
      var messageInput = document.createElement('textarea');
      messageInput.name = 'entries[' + index + '][message]';
      messageInput.rows = 3;
      messageCell.appendChild(messageInput);

      row.appendChild(dateCell);
      row.appendChild(messageCell);
      if (rows.firstChild) {
        rows.insertBefore(row, rows.firstChild);
      } else {
        rows.appendChild(row);
      }
      rows.setAttribute('data-next-index', String(index + 1));
    });

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

  onReady(function () {
    initAnnouncementEditor();
    initToggleDisabledTargets();
    initConfirmSubmit();
  });
})();
