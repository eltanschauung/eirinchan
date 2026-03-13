/*
 * thread-stats.js
 *   - Updates the pre-rendered thread statistics block
 *   - Shows ID post count beside each postID on hover
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/thread-stats.js';
 */
if (active_page == 'thread') {
$(document).ready(function(){
	var el = $('#thread_stats');
	if (!el.length) {
		return;
	}

	var thread_id = (document.location.pathname + document.location.search).split('/');
	thread_id = thread_id[thread_id.length -1].split('+')[0].split('-')[0].split('.')[0];

	function refreshThreadPage() {
		var board_name = $('input[name="board"]').val();
		$.getJSON('//' + document.location.host + '/' + board_name + '/threads.json').success(function(data){
			var found, page = '???';
			for (var i = 0; data[i]; i++) {
				var threads = data[i].threads;
				for (var j = 0; threads[j]; j++) {
					if (parseInt(threads[j].no) == parseInt(thread_id)) {
						page = data[i].page + 1;
						found = true;
						break;
					}
				}
				if (found) break;
			}
			$('#thread_stats_page').text(page);
			if (!found) $('#thread_stats_page').css('color','red');
			else $('#thread_stats_page').css('color','');
		});
	}

	function update_thread_stats(){
		var replies = $('#thread_'+ thread_id +' > div.post.reply:not(.post-hover):not(.inline)');

		$('#thread_stats_posts').text(replies.length);
		$('#thread_stats_images').text(replies.filter(function(){
			return $(this).find('> .files').text().trim() != false;
		}).length);

		refreshThreadPage();
	}

	setInterval(refreshThreadPage, 30000);
	update_thread_stats();
	$('#update_thread').off('click.threadStats').on('click.threadStats', update_thread_stats);
	$(document).on('new_post', update_thread_stats);
});
}
