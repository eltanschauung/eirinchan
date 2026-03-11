(function() {
  var csrfToken = function(trigger) {
    var form = trigger && trigger.closest('form');
    var field = (form && form.querySelector('input[name="_csrf_token"]')) ||
      document.querySelector('input[name="_csrf_token"]');
    return field ? field.value : null;
  };

  var syncWatchLinks = function(threadId, watched) {
    var selector = '[data-thread-watch][data-thread-id="' + threadId + '"]';
    document.querySelectorAll(selector).forEach(function(link) {
      link.dataset.watched = watched ? 'true' : 'false';
      link.textContent = watched ? '[Unwatch]' : '[Watch]';
    });
  };

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

  document.addEventListener('click', function(event) {
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
    }).catch(function() {
      if (typeof alert === 'function') alert('Watcher update failed.');
    }).finally(function() {
      delete link.dataset.pending;
    });
  });
})();
