/* image-hover.js 
 * This script is copied almost verbatim from https://github.com/Pashe/8chanX/blob/2-0/8chan-x.user.js
 * All I did was remove the sprintf dependency and integrate it into 8chan's Options as opposed to Pashe's.
 * I also changed initHover() to also bind on new_post.
 * Thanks Pashe for using WTFPL.
 */

if (active_page === "catalog" || active_page === "thread" || active_page === "index") {
$(function(){

if (window.Options && Options.get_tab('general')) {
	Options.extend_tab("general", 
	"<fieldset><legend>Image hover</legend>"
	+ ("<label class='image-hover' id='imageHover'><input type='checkbox' /> "+_('Image hover')+"</label>")
	+ ("<label class='image-hover' id='catalogImageHover'><input type='checkbox' /> "+_('Image hover on catalog')+"</label>")
	+ ("<label class='image-hover' id='imageHoverFollowCursor'><input type='checkbox' /> "+_('Image hover should follow cursor')+"</label>")
	+ "</fieldset>");
}

$('.image-hover').on('change', function(){
	var setting = $(this).attr('id');

	localStorage[setting] = $(this).children('input').is(':checked');
});

if (typeof localStorage.imageHover === 'undefined') {
	localStorage.imageHover = 'true';
}
if (typeof localStorage.catalogImageHover === 'undefined') {
	localStorage.catalogImageHover = 'true';
}
if (typeof localStorage.imageHoverFollowCursor === 'undefined') {
	localStorage.imageHoverFollowCursor = 'true';
}

if (getSetting('imageHover')) $('#imageHover>input').prop('checked', 'checked');
if (getSetting('catalogImageHover')) $('#catalogImageHover>input').prop('checked', 'checked');
if (getSetting('imageHoverFollowCursor')) $('#imageHoverFollowCursor>input').prop('checked', 'checked');

function getFileExtension(filename) { //Pashe, WTFPL
	if (filename.match(/\.([a-z0-9]+)(&loop.*)?$/i) !== null) {
		return filename.match(/\.([a-z0-9]+)(&loop.*)?$/i)[1];
	} else if (filename.match(/https?:\/\/(www\.)?youtube.com/)) {
		return 'Youtube';
	} else {
		return "unknown: " + filename;
	}
}

function isImage(fileExtension) { //Pashe, WTFPL
	return ($.inArray(fileExtension, ["jpg", "jpeg", "gif", "png"]) !== -1);
}

function isVideo(fileExtension) { //Pashe, WTFPL
	return ($.inArray(fileExtension, ["webm", "mp4"]) !== -1);
}

function isOnCatalog() {
	return window.active_page === "catalog";
}

function isOnThread() {
	return window.active_page === "thread";
}

function resolveFullImageUrl($thumb) {
	if (isOnCatalog()) {
		return $thumb.attr("data-fullimage") || null;
	}

	var $file = $thumb.closest(".file, .files > div, .post, .thread");
	var $fileInfoLink = $file.find("p.fileinfo a").first();

	if ($fileInfoLink.length && $fileInfoLink.attr("href")) {
		return $fileInfoLink.attr("href");
	}

	var $link = $thumb.closest("a");
	if ($link.length && $link.attr("href")) {
		return $link.attr("href");
	}

	return null;
}

function getSetting(key) {
	return (localStorage[key] == 'true');
}

function initImageHover() { //Pashe, influenced by tux, et al, WTFPL
	if (!getSetting("imageHover") && !getSetting("catalogImageHover")) {return;}
	
	var selectors = [];
	
	if (getSetting("imageHover")) {selectors.push("img.post-image", "canvas.post-image");}
	if (getSetting("catalogImageHover") && isOnCatalog()) {
		selectors.push(".thread-image");
		$(".theme-catalog div.thread").css("position", "inherit");
	}
	
	function bindEvents(el) {
		$(el).find(selectors.join(", ")).each(function () {
			if ($(this).parent().data("expanded")) {return;}
			
			var $this = $(this);
			
			$this.on("mousemove", imageHoverStart);
			$this.on("mouseout",  imageHoverEnd);
			$this.on("click",     imageHoverEnd);
		});
	}

	window.bind_image_hover = bindEvents;

	bindEvents(document.body);
	$(document).on('new_post', function(e, post) {
		bindEvents(post);
	});
}

function imageHoverStart(e) { //Pashe, anonish, WTFPL
	var hoverImage = $("#chx_hoverImage");
	var $this = $(this);

	if ($this.hasClass('yt-embed') || $this.closest('.video-container').length) {
		return;
	}
	
	if (hoverImage.length) {
		if (getSetting("imageHoverFollowCursor")) {
			positionHoverImage(hoverImage, e);
		}
		
		return;
	}

	var fullUrl = resolveFullImageUrl($this);

	if (isOnCatalog() && fullUrl && !isImage(getFileExtension(fullUrl))) {
		fullUrl = $this.attr("src");
	}

	if (!fullUrl) {return;}
	
	if (isVideo(getFileExtension(fullUrl))) {return;}
	
	hoverImage = $('<img id="chx_hoverImage" src="'+fullUrl+'" />');

	if (getSetting("imageHoverFollowCursor")) {
		hoverImage.css({
			"position"      : "fixed",
			"z-index"       : 101,
			"pointer-events": "none",
			"max-width"     : "70vw",
			"max-height"    : "70vh",
		});
	} else {
		hoverImage.css({
			"position"      : "fixed",
			"top"           : 0,
			"right"         : 0,
			"z-index"       : 101,
			"pointer-events": "none",
			"max-width"     : "100%",
			"max-height"    : "100%",
		});
	}
	hoverImage.appendTo($("body"));
	if (getSetting("imageHoverFollowCursor")) {
		positionHoverImage(hoverImage, e);
	}
}

function imageHoverEnd() { //Pashe, WTFPL
	$("#chx_hoverImage").remove();
}

function positionHoverImage(hoverImage, e) {
	var offset = 20;
	var left = e.clientX + offset;
	var top = e.clientY + offset;
	var windowWidth = $(window).width();
	var windowHeight = $(window).height();
	var imageWidth = hoverImage.outerWidth() || 0;
	var imageHeight = hoverImage.outerHeight() || 0;

	if (left + imageWidth > windowWidth - 10) {
		left = Math.max(10, e.clientX - imageWidth - offset);
	}

	if (top + imageHeight > windowHeight - 10) {
		top = Math.max(10, windowHeight - imageHeight - 10);
	}

	hoverImage.css({
		left: left,
		top: top
	});
}

initImageHover();
});
}
