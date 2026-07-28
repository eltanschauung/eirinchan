(function (window, document) {
  "use strict";

  var $ = window.jQuery;
  if (!$) return;

  var supportedPages = {catalog: true, thread: true, index: true};

  function translate(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function readSetting(name) {
    try {
      var value = window.localStorage.getItem(name);
      if (value === null) {
        window.localStorage.setItem(name, "true");
        return true;
      }
      return value === "true";
    } catch (_error) {
      return true;
    }
  }

  function writeSetting(name, enabled) {
    try {
      window.localStorage.setItem(name, enabled ? "true" : "false");
    } catch (_error) {}
  }

  function addOptions() {
    if (!window.Options || !window.Options.get_tab("general")) return;

    if (!document.getElementById("imageHover")) {
      window.Options.extend_tab(
        "general",
        "<fieldset><legend>" +
          translate("Image hover") +
          "</legend><label class='image-hover' id='imageHover'><input type='checkbox'> " +
          translate("Image hover") +
          "</label><label class='image-hover' id='catalogImageHover'><input type='checkbox'> " +
          translate("Image hover on catalog") +
          "</label><label class='image-hover' id='imageHoverFollowCursor'><input type='checkbox'> " +
          translate("Image hover should follow cursor") +
          "</label></fieldset>"
      );
    }

    $(".image-hover").each(function () {
      var label = $(this);
      var name = label.attr("id");
      var checkbox = label.children("input");
      checkbox.prop("checked", readSetting(name));
      checkbox.off("change.imageHover").on("change.imageHover", function () {
        writeSetting(name, checkbox.is(":checked"));
      });
    });
  }

  function extension(url) {
    var match = String(url || "").match(/\.([a-z0-9]+)(?:&loop.*)?$/i);
    if (match) return match[1].toLowerCase();
    return /https?:\/\/(?:www\.)?youtube\.com/i.test(String(url || "")) ? "youtube" : "";
  }

  function catalogPage() {
    return window.active_page === "catalog";
  }

  function fullImageUrl(image) {
    if (catalogPage()) return image.attr("data-fullimage") || null;

    var fileLink = image
      .closest(".file, .files > div, .post, .thread")
      .find("p.fileinfo a")
      .first();
    if (fileLink.length && fileLink.attr("href")) return fileLink.attr("href");

    var parentLink = image.closest("a");
    return parentLink.length ? parentLink.attr("href") || null : null;
  }

  function movePreview(preview, event) {
    var left = event.clientX + 20;
    var top = event.clientY + 20;
    var width = $(window).width();
    var height = $(window).height();
    var previewWidth = preview.outerWidth() || 0;
    var previewHeight = preview.outerHeight() || 0;

    if (left + previewWidth > width - 10) left = Math.max(10, event.clientX - previewWidth - 20);
    if (top + previewHeight > height - 10) top = Math.max(10, height - previewHeight - 10);
    preview.css({left: left, top: top});
  }

  function removePreview() {
    $("#chx_hoverImage").remove();
  }

  function showPreview(event) {
    var existing = $("#chx_hoverImage");
    var image = $(this);
    if (image.hasClass("yt-embed") || image.closest(".video-container").length) return;

    if (existing.length) {
      if (readSetting("imageHoverFollowCursor")) movePreview(existing, event);
      return;
    }

    var url = fullImageUrl(image);
    if (catalogPage() && url && !["jpg", "jpeg", "gif", "png"].includes(extension(url))) {
      url = image.attr("src");
    }
    if (!url || ["webm", "mp4"].includes(extension(url))) return;

    var preview = $("<img>").attr({id: "chx_hoverImage", src: url});
    var baseStyles = {
      position: "fixed",
      "z-index": 101,
      "pointer-events": "none",
      "max-width": "100%",
      "max-height": "100%"
    };

    if (readSetting("imageHoverFollowCursor")) {
      baseStyles["max-width"] = "70vw";
      baseStyles["max-height"] = "70vh";
    } else {
      baseStyles.top = 0;
      baseStyles.right = 0;
    }

    preview.css(baseStyles).appendTo("body");
    if (readSetting("imageHoverFollowCursor")) movePreview(preview, event);
  }

  function bindImageHover(root) {
    var selectors = [];
    if (readSetting("imageHover")) selectors.push("img.post-image", "canvas.post-image");
    if (readSetting("catalogImageHover") && catalogPage()) selectors.push(".thread-image");
    if (!selectors.length) return;

    var selector = selectors.join(", ");
    var scope = $(root);
    scope
      .filter(selector)
      .add(scope.find(selector))
      .each(function () {
        if ($(this).parent().data("expanded") || this.dataset.imageHoverBound === "true") return;
        this.dataset.imageHoverBound = "true";
        $(this).on("mousemove", showPreview).on("mouseout click", removePreview);
      });
  }

  $(function () {
    addOptions();
    if (!supportedPages[window.active_page]) return;

    if (catalogPage() && readSetting("catalogImageHover")) {
      $(".theme-catalog div.thread").css("position", "inherit");
    }

    window.bind_image_hover = bindImageHover;
    bindImageHover(document.body);
    $(document).on("fragment_init new_post", function (_event, root) {
      bindImageHover(root);
    });
  });
})(window, document);
