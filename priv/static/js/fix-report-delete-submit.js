/*
 * fix-report-delete-submit.js
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/post-menu.js';
 *   $config['additional_javascript'][] = 'js/fix-report-delete-submit.js';
 *
 */

if (active_page == 'thread' || active_page == 'index' || active_page == 'ukko') {
$(document).on('menu_ready', function(){
var Menu = window.Menu;
if (!Menu || Menu.__quickActionMenuInstalled) {
	return;
}
Menu.__quickActionMenuInstalled = true;

function csrfToken() {
	var token = $('input[name=_csrf_token]:first').val();
	if (token) {
		return token;
	}

	return $('meta[name="csrf-token"]').attr('content') || '';
}

function boardUri($post) {
	var board = $('input[name=board]:first').val();
	if (board) {
		return board;
	}

	var container = $post.closest('[data-board],[data-board-uri]');
	return container.attr('data-board') || container.attr('data-board-uri') || '';
}

function postAction() {
	return $('form[name="post"]:first').attr('action') || '/post.php';
}

function buildQuickActionForm($post, postId) {
	if (!$post.length || !postId) {
		return $();
	}

	var thread = $post.hasClass('op');
	var board = boardUri($post);
	var $form = $(
		'<form class="post-actions" method="post" style="margin:10px 0 0 0">' +
			'<div style="text-align:right">' +
				(!thread ? '<hr>' : '') +
				'<input type="hidden" name="delete_' + postId + '">' +
				'<label for="password_' + postId + '">' + _("Password") + '</label>: ' +
				'<input id="password_' + postId + '" type="password" name="password" size="11" maxlength="18" autocomplete="off">' +
				'<input title="' + _('Delete file only') + '" type="checkbox" name="file" id="delete_file_' + postId + '">' +
					'<label for="delete_file_' + postId + '">' + _('File') + '</label>' +
				' <input type="submit" name="delete" value="' + _('Delete') + '">' +
				'<br>' +
				'<label for="reason_' + postId + '">' + _('Reason') + '</label>: ' +
				'<input id="reason_' + postId + '" type="text" name="reason" size="20" maxlength="100">' +
				' <input type="submit" name="report" value="' + _('Report') + '">' +
			'</div>' +
		'</form>'
	);

	$form
		.attr('action', postAction())
		.append($('<input type="hidden" name="board">').val(board))
		.append($('<input type="hidden" name="_csrf_token">').val(csrfToken()))
		.find('input:not([type="checkbox"]):not([type="submit"]):not([type="hidden"])').keypress(function(e) {
			if (e.which == 13) {
				e.preventDefault();
				if ($(this).attr('name') == 'password')  {
					$form.find('input[name=delete]').click();
				} else if ($(this).attr('name') == 'reason')  {
					$form.find('input[name=report]').click();
				}

				return false;
			}

			return true;
		});

	$form.find('input[type="password"]').val(localStorage.password || '');

	if (thread) {
		$form.prependTo($post.find('div.body').first());
	} else {
		$form.appendTo($post);
	}

	$(window).trigger('quick-post-controls', $form);
	return $form;
}

function ensureQuickActionForm($post, postId) {
	var $checkbox = $('#delete_' + postId);
	if ($checkbox.length && !$checkbox.prop('checked')) {
		$checkbox.prop('checked', true).trigger('change');
	}

	var $quickForm = $post.find('form.post-actions');
	if ($quickForm.length) {
		return $quickForm;
	}

	$quickForm = buildQuickActionForm($post, postId);
	if ($quickForm.length) {
		return $quickForm;
	}

	var $sharedForm = $('form[name="postcontrols"]:first');
	if ($sharedForm.length) {
		if (!$sharedForm.find('input[name="delete_post_id"]').length) {
			$sharedForm.prepend('<input type="hidden" name="delete_post_id" value="">');
		}

		if (!$sharedForm.find('input[name="report_post_id"]').length) {
			$sharedForm.prepend('<input type="hidden" name="report_post_id" value="">');
		}
	}

	return $sharedForm;
}

function prepareSharedActionForm($form, postId, action) {
	if (!$form.length || $form.hasClass('post-actions')) {
		return;
	}

	var $deletePostId = $form.find('input[name="delete_post_id"]').first();
	var $reportPostId = $form.find('input[name="report_post_id"]').first();

	if (action === 'delete') {
		$deletePostId.val('');
		$reportPostId.val('');
	} else if (action === 'report') {
		$reportPostId.val(postId);
		$deletePostId.val('');
	}
}

function syncLegacyDeleteSelection($form, postId, enabled) {
	if (!$form.length || !postId) {
		return;
	}

	$form.find('input[data-legacy-delete-selection="true"]').remove();

	if (enabled) {
		$('<input>', {
			type: 'hidden',
			name: 'delete_' + postId,
			value: 'on',
			'data-legacy-delete-selection': 'true'
		}).appendTo($form);
	}
}
	
if ($('#delete-fields #password').length) {
Menu.add_item("delete_post_menu", _("Delete post"));
	Menu.add_item("delete_file_menu", _("Delete file"));
Menu.onclick(function(e, $buf) {
		var ele = $(e.target).closest('.post')[0];
		var $ele = $(ele);
		var postId = $ele.find('.post_no').not('[id]').text();
		var hasFiles = $ele.find('.files .file, .files .multifile').length > 0;

		if (!hasFiles) {
			$buf.find('#delete_file_menu').addClass('hidden');
		}

		$buf.find('#delete_post_menu,#delete_file_menu').click(function(e) {
			e.preventDefault();
			var $form = ensureQuickActionForm($ele, postId);

			if (!$form.length) {
				return;
			}

			prepareSharedActionForm($form, postId, 'delete');
			syncLegacyDeleteSelection($form, postId, true);

			var $fileToggle = $form.find('#delete_file_' + postId + ', #delete_file, input[name="file"]').first();
			var $password = $form.find('input[name="password"]');
			var $deleteButton = $form.find('input[name="delete"]').first();
			var passwordValue = $.trim($password.val() || '');
			if ($(this).attr('id') === 'delete_file_menu') {
				$fileToggle.prop('checked', true);
			} else {
				$fileToggle.prop('checked', false);
			}

			if (passwordValue.length) {
				$deleteButton.trigger('click');
			} else {
				$password.trigger('focus');
			}
		});
	});
}

Menu.add_item("report_menu", _("Report"));
//Menu.add_item("global_report_menu", _("Global report"));
Menu.onclick(function(e, $buf) {
	var ele = $(e.target).closest('.post')[0];
	var $ele = $(ele);
	var postId = $ele.find('.post_no').not('[id]').text();

	$buf.find('#report_menu,#global_report_menu').click(function(e) {
		e.preventDefault();
		var $form = ensureQuickActionForm($ele, postId);

		if (!$form.length) {
			return;
		}

		syncLegacyDeleteSelection($form, postId, false);
		prepareSharedActionForm($form, postId, 'report');
		$form.find('input[name="reason"]').trigger('focus');
	});
});

$('#post-moderation-fields').hide();
});

if (typeof window.Menu !== "undefined") {
	$(document).trigger('menu_ready');
}
}
