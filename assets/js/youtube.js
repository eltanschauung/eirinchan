(function (window, document) {
  "use strict";

  var validVideoId = /^[A-Za-z0-9_-]{10,11}$/;

  function replaceWithPlayer(link) {
    var container = link && link.parentNode;
    var videoId = container && container.dataset ? String(container.dataset.video || "") : "";
    if (!container || !validVideoId.test(videoId)) return;

    var frame = document.createElement("iframe");
    frame.style.cssText = "float:left;margin:10px 20px";
    frame.width = "360";
    frame.height = "270";
    frame.src = "https://www.youtube.com/embed/" + encodeURIComponent(videoId) + "?autoplay=1&html5=1";
    frame.title = "YouTube video player";
    frame.allow = "autoplay; encrypted-media; picture-in-picture";
    frame.allowFullscreen = true;
    frame.referrerPolicy = "strict-origin-when-cross-origin";
    frame.setAttribute("frameborder", "0");
    container.replaceChildren(frame);
  }

  (window.onReady || function (callback) { callback(); })(function () {
    document.addEventListener("click", function (event) {
      var link = event.target.closest("div.video-container a");
      if (!link) return;
      event.preventDefault();
      replaceWithPlayer(link);
    });
  });
})(window, document);
