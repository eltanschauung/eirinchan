/*
 * show-own-posts.js
 * https://github.com/savetheinternet/Tinyboard/blob/master/js/show-op.js
 *
 * Adds "(You)" to a name field when the post is yours. Update references as well.
 *
 * Released under the MIT license
 * Copyright (c) 2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/ajax.js';
 *   $config['additional_javascript'][] = 'js/show-own-posts.js';
 *
 */


+function(){

function parsePostId(value) {
  var parsed = parseInt(value, 10);
  return isNaN(parsed) ? null : parsed;
}

function loadOwnPosts() {
  try {
    return JSON.parse(localStorage.own_posts || '{}');
  } catch (_error) {
    return {};
  }
}

function storeOwnPosts(posts) {
  localStorage.own_posts = JSON.stringify(posts);
}

function mergeStoredPosts(board, ids) {
  if (!board || !ids.length) return;

  var posts = loadOwnPosts();
  var existing = posts[board] || [];

  ids.forEach(function(id) {
    var normalized = String(id);
    if (existing.indexOf(normalized) === -1) {
      existing.push(normalized);
    }
  });

  posts[board] = existing;
  storeOwnPosts(posts);
}

function boardForElement(element) {
  var $element = $(element);
  var $thread = $element.is('.thread[data-board]') ? $element : $element.closest('.thread[data-board]');
  return $thread.attr('data-board') || null;
}

function collectPostIds(container) {
  var ids = {};

  $(container).find('.post_no[id^="post_no_"], a[data-cite-reply], a[data-highlight-reply]').each(function() {
    var id = null;

    if (this.hasAttribute('data-cite-reply')) {
      id = parsePostId(this.getAttribute('data-cite-reply'));
    } else if (this.hasAttribute('data-highlight-reply')) {
      id = parsePostId(this.getAttribute('data-highlight-reply'));
    } else {
      id = parsePostId((this.id || '').replace('post_no_', ''));
    }

    if (id !== null) {
      ids[id] = true;
    }
  });

  return Object.keys(ids);
}

function appendOwnLabel($post) {
  if ($post.is('.you')) return;
  $post.addClass('you');

  if ($post.find('.own_post').length) return;

  var $name = $post.find('span.name').first();
  if ($name.length) {
    $name.append(' <span class="own_post">'+_('(You)')+'</span>');
  }
}

function appendQuoteMarker(link) {
  var next = link.nextSibling;

  while (next && next.nodeType === 3 && /^\s*$/.test(next.nodeValue)) {
    next = next.nextSibling;
  }

  if (next && next.nodeType === 1 && next.tagName === 'SMALL' && $(next).text() === _('(You)')) {
    return;
  }

  $(link).after(' <small>'+_('(You)')+'</small>');
}

function applyQuoteMarkers(links, owned) {
  $(links).each(function() {
    var postID = this.getAttribute('data-cite-reply') || this.getAttribute('data-highlight-reply');
    if (postID && owned[postID]) {
      appendQuoteMarker(this);
    }
  });
}

function applyOwnMarkers(scope, board, ids) {
  var owned = {};
  ids.forEach(function(id) {
    owned[String(id)] = true;
  });

  $(scope).find('.post.op, .post.reply').each(function() {
    var match = (this.id || '').match(/^(?:op|reply)_(\d+)$/);
    if (match && owned[match[1]]) {
      appendOwnLabel($(this));
    }
  });

  applyQuoteMarkers($(scope).find('div.body a[data-cite-reply], div.body a[data-highlight-reply]'), owned);
  applyQuoteMarkers($(scope).find('span.mentioned a[data-highlight-reply]'), owned);

  if (board && ids.length) {
    mergeStoredPosts(board, ids);
  }
}

function applyStoredOwnMarkers(scope, board) {
  var posts = loadOwnPosts();
  var owned = posts[board] || [];
  if (owned.length) {
    applyOwnMarkers(scope, board, owned);
  }
}

function syncOwnMarkersFor(scope) {
  var board = boardForElement(scope);
  var ids = collectPostIds(scope);

  if (!board || !ids.length) return;

  applyStoredOwnMarkers(scope, board);

  $.ajax({
    type: 'POST',
    url: '/api/you-markers/' + encodeURIComponent(board),
    contentType: 'application/json',
    dataType: 'json',
    data: JSON.stringify({post_ids: ids})
  }).done(function(response) {
    if (!response || response.enabled === false) return;
    applyOwnMarkers(scope, board, response.post_ids || []);
  });
}


var update_own = function() {
  syncOwnMarkersFor(this);
};

var threads_for_scope = function(scope) {
  var $scope = $(scope);
  return $scope.filter('.thread[data-board]').add($scope.find('.thread[data-board]'));
};

var update_threads = function(scope) {
  threads_for_scope(scope || document.body).each(update_own);
};

var board = null;

$(function() {
  board = $('input[name="board"]').first().val();

  update_threads(document.body);
});

$(document).on('ajax_after_post', function(e, r) {
  if (!board) return;
  mergeStoredPosts(board, [r.id]);
});

$(document).on('new_post', function(e,post) {
  var thread = $(post).closest('.thread[data-board]')[0] || post;
  update_own.call(thread);
});

$(document).on('fragment_init', function(e, root) {
  update_threads(root);
});



}();
