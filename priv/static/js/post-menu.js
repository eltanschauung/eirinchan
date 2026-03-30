/*
 * post-menu.js - adds dropdown menu to posts
 *
 * Creates a global Menu object with four public methods:
 *
 *   Menu.onclick(fnc)
 *     registers a function to be executed after button click, before the menu is displayed
 *   Menu.add_item(id, text[, title])
 *     adds an item to the top level of menu
 *   Menu.add_submenu(id, text)
 *     creates and returns a List object through which to manipulate the content of the submenu
 *   Menu.get_submenu(id)
 *     returns the submenu with the specified id from the top level menu
 *
 *   The List object contains all the methods from Menu except onclick()
 *
 *   Example usage:
 *     Menu.add_item('filter-menu-hide', 'Hide post');
 *     Menu.add_item('filter-menu-unhide', 'Unhide post');
 *
 *     submenu = Menu.add_submenu('filter-menu-add', 'Add filter');
 *         submenu.add_item('filter-add-post-plus', 'Post +', 'Hide post and all replies');
 *         submenu.add_item('filter-add-id', 'ID');
 *  
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/post-menu.js';
 */
$(document).ready(function () {

var List = function (menuId, text) {
	this.id = menuId;
	this.text = text;
	this.items = [];

	this.add_item = function (itemId, text, title) {
		this.items.push(new Item(itemId, text, title));
	};
	this.list_items = function () {
		var array = [];
		var i, length, obj, $ele;

		if ($.isEmptyObject(this.items))
			return;

		length = this.items.length;
		for (i = 0; i < length; i++) {
			obj = this.items[i];

			$ele = $('<li>', {id: obj.id}).text(obj.text);
			if ('title' in obj) $ele.attr('title', obj.title);

			if (obj instanceof Item) {
				$ele.addClass('post-item');
			} else {
				$ele.addClass('post-submenu');

				$ele.prepend(obj.list_items());
				$ele.append($('<span>', {class: 'post-menu-arrow'}).text('»'));
			}

			array.push($ele);
		}

		return $('<ul>').append(array);
	};
	this.add_submenu = function (menuId, text) {
		var ele = new List(menuId, text);
		this.items.push(ele);
		return ele;
	};
	this.get_submenu = function (menuId) {
		for (var i = 0; i < this.items.length; i++) {
			if ((this.items[i] instanceof Item) || this.items[i].id != menuId) continue;
			return this.items[i];
		}
	};
};

var Item = function (itemId, text, title) {
	this.id = itemId;
	this.text = text;

	// optional
	if (typeof title != 'undefined') this.title = title;
};

function isTransparentColor(value) {
	return !value || value === 'transparent' || value === 'rgba(0, 0, 0, 0)' || value === 'rgba(0,0,0,0)';
}

function cssVariableValue(node, name) {
	while (node && node.nodeType === 1) {
		var value = window.getComputedStyle(node).getPropertyValue(name);
		if (value && $.trim(value)) {
			return $.trim(value);
		}
		node = node.parentElement;
	}

	var rootValue = window.getComputedStyle(document.documentElement).getPropertyValue(name);
	return rootValue ? $.trim(rootValue) : '';
}

function sampleReplyBackground($context) {
	var $scope = $context && $context.length ? $context.closest('.thread') : $();
	var $reply = $scope.find('.post.reply:visible').first();

	if (!$reply.length) {
		$reply = $('.post.reply:visible').first();
	}

	if (!$reply.length) {
		return '';
	}

	var sampled = $reply.css('background-color');
	return isTransparentColor(sampled) ? '' : sampled;
}

function resolveMenuBackground($trigger, $post) {
	var sampled = '';

	if ($post && $post.length) {
		sampled = $post.css('background-color');
		if (!isTransparentColor(sampled) && !$post.hasClass('op')) {
			return sampled;
		}
	}

	sampled = sampleReplyBackground($post);
	if (sampled) {
		return sampled;
	}

	var triggerNode = $trigger && $trigger.length ? $trigger[0] : null;
	var themedFallback = cssVariableValue(triggerNode || document.body, '--fg-primary');
	if (themedFallback) {
		return themedFallback;
	}

	return '';
}

function buildMenu(e) {
	var pos = $(e.target).offset();
	var i, length;
	var $menu = $('#post-menu-root');
	var $target = $(e.target);
	var $post = $target.closest('.post.reply, .post.op, .post');
	var menuBackground = '';

	if (!$menu.length) {
		$menu = $('<div id="post-menu-root" class="post-menu hidden" hidden></div>').appendTo('body');
	}

	$menu.empty().append(mainMenu.list_items());
	menuBackground = resolveMenuBackground($target, $post);
	$menu.css('--post-menu-bg-local', menuBackground);
	$menu.find('ul').css('background-color', menuBackground);

	//  execute registered click handlers
	length = onclick_callbacks.length;
	for (i = 0; i < length; i++) {
		onclick_callbacks[i](e, $menu);
	}

	//  set menu position and append to page
	$menu.css({top: pos.top, left: pos.left + 20}).removeClass('hidden').prop('hidden', false);
}

function addButton(post) {
	var $ele = $(post);

	if ($ele.find('> p.intro > .thread-top-controls > .post-btn, > p.intro > .post-btn').length) {
		return;
	}
}


/* * * * * * * * * *
    Public methods
 * * * * * * * * * */
var Menu = {};
var mainMenu = new List();
var onclick_callbacks = [];

Menu.onclick = function (fnc) {
	onclick_callbacks.push(fnc);
};

Menu.add_item = function (itemId, text, title) {
	mainMenu.add_item(itemId, text, title);
};

Menu.add_submenu = function (menuId, text) {
	return mainMenu.add_submenu(menuId, text);
};

Menu.get_submenu = function (id) {
	return mainMenu.get_submenu(id);
};

window.Menu = Menu;


/* * * * * * * *
    Initialize
 * * * * * * * */

/*  Add buttons
 */
$('.reply:not(.hidden), .thread>.op').each(function () {
	addButton(this);
 });

 /*  event handlers
  */
$(document).on('click', '.post-btn', function (e) {
	e.preventDefault();
	var post = $(e.target).closest('.post')[0];
	if (!post) {
		return;
	}
	$('#post-menu-root').empty().addClass('hidden').prop('hidden', true);

	if ($(e.target).hasClass('post-btn-open')) {
		$('.post-btn-open').removeClass('post-btn-open');
	} else {
		//  close previous button
		$('.post-btn-open').removeClass('post-btn-open');
		$(post).find('.post-btn').addClass('post-btn-open');

		buildMenu(e);
	}
});

$(document).on('click', function (e){
	if ($(e.target).hasClass('post-btn') || $(e.target).hasClass('post-submenu'))
		return;

	$('#post-menu-root').empty().addClass('hidden').prop('hidden', true);
	$('.post-btn-open').removeClass('post-btn-open');
});

// on new posts
$(document).on('new_post', function (e, post) {
	addButton(post);
});

$(document).trigger('menu_ready');
});
