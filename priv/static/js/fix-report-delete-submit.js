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

function ensureQuickActionForm($post, postId) {
	var $checkbox = $('#delete_' + postId);
	if (!$checkbox.length) {
		return $();
	}

	if (!$checkbox.prop('checked')) {
		$checkbox.prop('checked', true).trigger('change');
	}

	return $post.find('form.post-actions');
}
	
if ($('#delete-fields #password').length) {
	Menu.add_item("delete_post_menu", _("Delete post"));
	Menu.add_item("delete_file_menu", _("Delete file"));
Menu.onclick(function(e, $buf) {
		var ele = e.target.dataset.postTarget ? document.getElementById(e.target.dataset.postTarget) : $(e.target).closest('.post')[0];
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

			var $fileToggle = $form.find('#delete_file_' + postId);
			var $password = $form.find('input[name="password"]');
			var passwordValue = $.trim($password.val() || '');
			if ($(this).attr('id') === 'delete_file_menu') {
				$fileToggle.prop('checked', true);
			} else {
				$fileToggle.prop('checked', false);
			}

			if (passwordValue.length) {
				$form.find('input[name="delete"]').trigger('click');
			} else {
				$password.trigger('focus');
			}
		});
	});
}

Menu.add_item("report_menu", _("Report"));
//Menu.add_item("global_report_menu", _("Global report"));
Menu.onclick(function(e, $buf) {
	var ele = e.target.dataset.postTarget ? document.getElementById(e.target.dataset.postTarget) : $(e.target).closest('.post')[0];
	var $ele = $(ele);
	var postId = $ele.find('.post_no').not('[id]').text();

	$buf.find('#report_menu,#global_report_menu').click(function(e) {
		e.preventDefault();
		var $form = ensureQuickActionForm($ele, postId);

		if (!$form.length) {
			return;
		}

		$form.find('input[name="reason"]').trigger('focus');
	});
});

$('#post-moderation-fields').hide();
});

if (typeof window.Menu !== "undefined") {
	$(document).trigger('menu_ready');
}
}
