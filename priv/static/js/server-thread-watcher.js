(function() {
  var watcherTab = null;
  var watcherContent = null;

  var csrfToken = function(trigger) {
    var form = trigger && trigger.closest('form');
    var field = (form && form.querySelector('input[name="_csrf_token"]')) ||
      document.querySelector('input[name="_csrf_token"]');
    if (field) {
      return field.value;
    }

    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : null;
  };

  var setWatcherCount = function(count, youCount, unreadCount) {
    if (typeof youCount !== 'number' || isNaN(youCount)) {
      youCount = parseInt(document.body && document.body.dataset ? document.body.dataset.watcherYouCount || '0' : '0', 10) || 0;
    }

    if (typeof unreadCount !== 'number' || isNaN(unreadCount)) {
      unreadCount = parseInt(document.body && document.body.dataset ? document.body.dataset.watcherUnreadCount || '0' : '0', 10) || 0;
    }

    if (document.body && document.body.dataset) {
      document.body.dataset.watcherCount = String(count);
      document.body.dataset.watcherUnreadCount = String(unreadCount);
      document.body.dataset.watcherYouCount = String(youCount);
    }

    var link = document.getElementById('watcher-link');

    if (link) {
      var label = 'Watcher' + (count > 0 ? ' (' + count + ')' : '');
      link.title = label;
      link.setAttribute('aria-label', label);
      link.dataset.count = String(count);
      link.dataset.unreadCount = String(unreadCount);
      link.classList.toggle('has-unread', unreadCount > 0);
      link.classList.toggle('replies-quoting-you', youCount > 0);
    }
  };

  var boardUriFor = function(element) {
    if (!element) return '';

    if (element.dataset) {
      if (element.dataset.boardUri) return element.dataset.boardUri;
      if (element.dataset.board) return element.dataset.board;
    }

    var container = element.closest && element.closest('[data-board],[data-board-uri]');
    if (!container || !container.dataset) return '';

    return container.dataset.boardUri || container.dataset.board || '';
  };

  var syncWatchLinks = function(boardUri, threadId, watched) {
    document.querySelectorAll('[data-thread-watch][data-thread-id="' + threadId + '"]').forEach(function(link) {
      if (boardUri && boardUriFor(link) !== boardUri) return;
      link.dataset.watched = watched ? 'true' : 'false';
      if (link.classList.contains('watch-thread-link')) {
        link.classList.toggle('watched', watched);
        link.title = (watched ? 'Unwatch' : 'Watch') + ' Thread';
      } else {
        link.textContent = watched ? '[Unwatch]' : '[Watch]';
      }
    });

    document.querySelectorAll('.thread[data-thread-id="' + threadId + '"]').forEach(function(thread) {
      if (boardUri && boardUriFor(thread) !== boardUri) return;
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
        var post = e.target.closest && e.target.closest('.post');
        var thread = post && post.closest && post.closest('.thread');

        if (!post || !post.classList || !post.classList.contains('op') || !thread || !thread.dataset || !thread.dataset.threadId) {
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
      return response.ok ? response.json() : null;
    }).then(function(payload) {
      if (payload && typeof payload.watcher_count === 'number') {
        setWatcherCount(payload.watcher_count, payload.watcher_you_count, payload.watcher_unread_count);
      }
    }).catch(function(error) {
      console.error(error);
    });
  };

  var ensureWatcherTab = function() {
    if (!(window.Options && Options.add_tab)) return null;
    if (watcherTab) return watcherTab;

    watcherTab = Options.add_tab('watcher', 'eye', _('Watcher'));
    watcherContent = $('#watcher-tab-content');

    if (watcherTab && watcherTab.content && watcherTab.content.length) {
      var heading = watcherTab.content.children('h2').first();
      if (heading.length) {
        heading.html('Watcher | <a id="watcher-unwatch-all" href="#" style="color: inherit;">Unwatch All</a>');
      }
    }

    if (!watcherContent.length) {
      watcherContent = $('<div id="watcher-tab-content"><div class="watcher-loading">Loading...</div></div>');
      watcherContent.appendTo(watcherTab.content);
    }

    var webmTab = Options.get_tab('webm');
    if (webmTab && webmTab.icon && watcherTab.icon) {
      watcherTab.icon.insertAfter(webmTab.icon);
    }

    return watcherTab;
  };

  var refreshWatcherTab = function() {
    ensureWatcherTab();
    if (!watcherContent) return Promise.resolve();

    return fetch('/watcher/fragment', {
      headers: {'x-requested-with': 'XMLHttpRequest'},
      credentials: 'same-origin',
      cache: 'no-store'
    }).then(function(response) {
      if (!response.ok) throw new Error('watcher fragment failed');
      setWatcherCount(
        parseInt(response.headers.get('x-watcher-count') || '', 10),
        parseInt(response.headers.get('x-watcher-you-count') || '', 10),
        parseInt(response.headers.get('x-watcher-unread-count') || '', 10)
      );
      return response.text();
    }).then(function(html) {
      watcherContent.html(html);
    }).catch(function() {
      watcherContent.html('<div class="post reply watcher-entry"><p class="body">Watcher refresh failed.</p></div>');
    });
  };

  var openWatcherTab = function() {
    if (!(window.Options && Options.show && Options.select_tab)) {
      window.location = '/watcher';
      return;
    }

    ensureWatcherTab();
    refreshWatcherTab().finally(function() {
      Options.show();
      Options.select_tab('watcher');
    });
  };

  document.addEventListener('click', function(event) {
    var watcherLink = event.target.closest('#watcher-link');

    if (watcherLink && event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey) {
      event.preventDefault();
      openWatcherTab();
      return;
    }

    var unwatchAllLink = event.target.closest('#watcher-unwatch-all');
    if (unwatchAllLink) {
      event.preventDefault();

      var token = csrfToken(unwatchAllLink);
      if (!token) return;

      fetch('/watcher', {
        method: 'DELETE',
        headers: {
          'x-csrf-token': token,
          'x-requested-with': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      }).then(function(response) {
        if (!response.ok) throw new Error('watch clear failed');
        return response.json();
      }).then(function(payload) {
        if (typeof payload.watcher_count === 'number') {
          setWatcherCount(payload.watcher_count, payload.watcher_you_count, payload.watcher_unread_count);
        }
        if (watcherContent && watcherContent.length) {
          watcherContent.html('<div class="post reply watcher-entry"><p class="body">No watched threads yet.</p></div>');
        }
      }).catch(function() {
        if (typeof alert === 'function') alert('Watcher update failed.');
      });
      return;
    }

    var link = event.target.closest('[data-thread-watch]');
    if (!link) return;

    event.preventDefault();

    if (link.dataset.pending === 'true') return;

    var watched = link.dataset.watched === 'true';
    var watcherEntry = link.closest('.watcher-thread');
    var inWatcherTab = !!watcherEntry;
    var boardUri = boardUriFor(link);
    var threadId = link.dataset.threadId;
    var url = boardUri && threadId ? '/watcher/' + encodeURIComponent(boardUri) + '/' + encodeURIComponent(threadId) : null;
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
      if (!response.ok) {
        if (response.status === 404 && inWatcherTab && watched) {
          watcherEntry.remove();
          return refreshWatcherTab().then(function() {
            return null;
          });
        }
        throw new Error('watch request failed');
      }
      return response.json();
    }).then(function(payload) {
      if (!payload) {
        return;
      }

      if (inWatcherTab && watched && !payload.watched) {
        watcherEntry.remove();

        if (watcherContent && watcherContent.length && !watcherContent.find('.watcher-thread').length) {
          watcherContent.html('<div class="post reply watcher-entry"><p class="body">No watched threads yet.</p></div>');
        }
      } else {
        syncWatchLinks(payload.board, payload.thread_id, !!payload.watched);
      }

      if (typeof payload.watcher_count === 'number') {
        setWatcherCount(payload.watcher_count, payload.watcher_you_count, payload.watcher_unread_count);
      }
      if (watcherTab && window.Options && Options.get_tab && Options.get_tab('watcher') && watcherTab.icon.hasClass('active')) {
        refreshWatcherTab();
      }
    }).catch(function() {
      if (typeof alert === 'function') alert('Watcher update failed.');
    }).finally(function() {
      delete link.dataset.pending;
    });
  });

  document.addEventListener('DOMContentLoaded', function() {
    if (window.Options && Options.get_tab) {
      ensureWatcherTab();
      if (Options.select_tab && !Options.__watcherRefreshPatched) {
        Options.__watcherRefreshPatched = true;
        var originalSelectTab = Options.select_tab;
        Options.select_tab = function(id, quick) {
          var tab = originalSelectTab.call(Options, id, quick);
          if (id === 'watcher') {
            refreshWatcherTab();
          }
          return tab;
        };
      }
      setWatcherCount(
        parseInt(document.body && document.body.dataset ? document.body.dataset.watcherCount || '0' : '0', 10) || 0,
        parseInt(document.body && document.body.dataset ? document.body.dataset.watcherYouCount || '0' : '0', 10) || 0,
        parseInt(document.body && document.body.dataset ? document.body.dataset.watcherUnreadCount || '0' : '0', 10) || 0
      );
    }
  });
})();
