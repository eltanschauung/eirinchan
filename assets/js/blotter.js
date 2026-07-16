(function (window, document) {
  "use strict";

  function toggleNews() {
    var blotter = document.querySelector("#blotterContainer .news-blotter");
    if (!blotter) return;

    var visible = !blotter.hidden && blotter.style.display !== "none";
    blotter.hidden = visible;
    blotter.style.display = visible ? "none" : "block";

    var button = document.querySelector("#blotterContainer .news-button");
    if (button) button.setAttribute("aria-expanded", visible ? "false" : "true");
  }

  window.toggleNews = window.toggleNews || toggleNews;
})(window, document);
