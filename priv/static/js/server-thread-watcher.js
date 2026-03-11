(function() {
  var watcherDialog;

  var csrfToken = function(trigger) {
    var form = trigger && trigger.closest('form');
    var field = (form && form.querySelector('input[name="_csrf_token"]')) ||
      document.querySelector('input[name="_csrf_token"]');
    return field ? field.value : null;
  };

  var watcherCountLabel = function(count) {
    return '[' + 'Watcher' + (count > 0 ? ' (' + count + ')' : '') + ']';
  };

  var setWatcherCount = function(count) {
    if (document.body && document.body.dataset) {
      document.body.dataset.watcherCount = String(count);
    }

    var link = document.getElementById('watcher-link');

    if (link) {
      link.textContent = watcherCountLabel(count);
    }
  };

  var syncWatchLinks = function(threadId, watched) {
    var selector = '[data-thread-watch][data-thread-id="' + threadId + '"]';
    document.querySelectorAll(selector).forEach(function(link) {
      link.dataset.watched = watched ? 'true' : 'false';
      if (link.classList.contains('watch-thread-link')) {
        link.classList.toggle('watched', watched);
        link.classList.toggle('post-btn', watched);
        link.title = (watched ? 'Unwatch' : 'Watch') + ' Thread';
      } else {
        link.textContent = watched ? '[Unwatch]' : '[Watch]';
      }
    });

    document.querySelectorAll('.thread[data-thread-id="' + threadId + '"]').forEach(function(thread) {
      thread.dataset.watched = watched ? 'true' : 'false';
    });
  };

  if (typeof window.jQuery !== 'undefined') {
    jQuery(document).on('menu_ready', function() {
      var Menu = window.Menu;
      if (!Menu || Menu.__watchThreadMenuInstalled) return;
      Menu.__watchThreadMenuInstalled = true;
      Menu.add_item('watch_thread_menu', 'Watch');
      Menu.onclick(function(e, $buf) {
        var post = e.target.parentElement && e.target.parentElement.parentElement;
        var thread = post && post.closest && post.closest('.thread');

        if (!thread || !thread.dataset || !thread.dataset.threadId) {
          $buf.find('#watch_thread_menu').addClass('hidden');
          return;
        }

        var toggler = thread.querySelector('.watch-thread-link[data-thread-watch]');
        var watched = toggler ? toggler.dataset.watched === 'true' : thread.dataset.watched === 'true';
        var $item = $buf.find('#watch_thread_menu');
        $item.removeClass('hidden').text(watched ? 'Unwatch' : 'Watch').off('click').on('click', function(event) {
          event.preventDefault();
          var toggler = thread.querySelector('.watch-thread-link[data-thread-watch]');
          if (toggler) {
            toggler.click();
          }
        });
      });
    });
  }

  window.markWatchedThreadSeen = function(boardUri, threadId, lastSeenPostId) {
    var token = csrfToken(document.body);

    if (!boardUri || !threadId || !lastSeenPostId || !token) return Promise.resolve();

    return fetch('/watcher/' + encodeURIComponent(boardUri) + '/' + encodeURIComponent(threadId), {
      method: 'PATCH',
      headers: {
        'content-type': 'application/json',
        'x-csrf-token': token,
        'x-requested-with': 'XMLHttpRequest'
      },
      credentials: 'same-origin',
      body: JSON.stringify({last_seen_post_id: lastSeenPostId})
    }).then(function(response) {
      if (!response.ok && response.status !== 404) throw new Error('watch seen failed');
    }).catch(function(error) {
      console.error(error);
    });
  };

  var ensureWatcherDialog = function() {
    if (watcherDialog) return watcherDialog;

    watcherDialog = document.createElement('div');
    watcherDialog.id = 'server-watcher-dialog';
    watcherDialog.innerHTML =
      '<div class="watcher-dialog-background"></div>' +
      '<div class="watcher-dialog-panel">' +
      '<a href="javascript:void(0)" class="watcher-dialog-close">[Close]</a>' +
      '<div class="watcher-dialog-body"></div>' +
      '</div>';

    watcherDialog.querySelector('.watcher-dialog-background').addEventListener('click', function() {
      watcherDialog.style.display = 'none';
    });

    watcherDialog.querySelector('.watcher-dialog-close').addEventListener('click', function(event) {
      event.preventDefault();
      watcherDialog.style.display = 'none';
    });

    document.body.appendChild(watcherDialog);
    return watcherDialog;
  };

  var renderWatcherDialog = function(html) {
    var dialog = ensureWatcherDialog();
    dialog.querySelector('.watcher-dialog-body').innerHTML = html;
    dialog.style.display = 'block';
  };

  var watcherDialogOpen = function() {
    return watcherDialog && watcherDialog.style.display === 'block';
  };

  var refreshWatcherDialog = function() {
    return fetch('/watcher/fragment', {
      headers: {'x-requested-with': 'XMLHttpRequest'},
      credentials: 'same-origin'
    }).then(function(response) {
      if (!response.ok) throw new Error('watcher fragment failed');
      return response.text();
    }).then(function(html) {
      renderWatcherDialog(html);
    }).catch(function() {
      if (typeof alert === 'function') alert('Watcher refresh failed.');
    });
  };

  document.addEventListener('click', function(event) {
    var watcherLink = event.target.closest('#watcher-link');

    if (watcherLink && event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey) {
      event.preventDefault();
      refreshWatcherDialog();
      return;
    }

    var link = event.target.closest('[data-thread-watch]');
    if (!link) return;

    event.preventDefault();

    if (link.dataset.pending === 'true') return;

    var watched = link.dataset.watched === 'true';
    var url = watched ? link.dataset.unwatchUrl : link.dataset.watchUrl;
    var method = watched ? 'DELETE' : 'POST';
    var token = csrfToken(link);

    if (!url || !token) return;

    link.dataset.pending = 'true';

    fetch(url, {
      method: method,
      headers: {
        'x-csrf-token': token,
        'x-requested-with': 'XMLHttpRequest'
      },
      credentials: 'same-origin'
    }).then(function(response) {
      if (!response.ok) throw new Error('watch request failed');
      return response.json();
    }).then(function(payload) {
      syncWatchLinks(payload.thread_id, !!payload.watched);
      if (typeof payload.watcher_count === 'number') {
        setWatcherCount(payload.watcher_count);
      }
      if (watcherDialogOpen()) {
        refreshWatcherDialog();
      }
    }).catch(function() {
      if (typeof alert === 'function') alert('Watcher update failed.');
    }).finally(function() {
      delete link.dataset.pending;
    });
  });
})();
