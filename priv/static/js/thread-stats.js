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

	function update_thread_stats(){
		var replies = $('#thread_'+ thread_id +' div.post.reply:not(.post-hover):not(.inline)');

		$('#thread_stats_posts').text(replies.length);
		$('#thread_stats_images').text(replies.filter(function(){
			return $(this).find('> .files').text().trim() != false;
		}).length);
	}

	update_thread_stats();
	$('#update_thread').off('click.threadStats').on('click.threadStats', update_thread_stats);
	$(document).on('new_post', update_thread_stats);
});
}
