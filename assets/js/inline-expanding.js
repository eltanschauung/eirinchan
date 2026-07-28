/*
 * Derived from Tinyboard's inline-expanding.js.
 * Released under the MIT license.
 * Copyright (c) 2012-2013 Michael Save
 * Copyright (c) 2013-2014 Marcin Łabanowski
 */

(function (window, document, $) {
  "use strict";

  if (!$) return;

  var DEFAULT_MAX_IMAGES = 10;

  function configuredMaxImages() {
    var runtime = window.EirinchanRuntime || {};
    var configured = runtime.inlineExpandMax;

    return Number.isInteger(configured) && configured >= 0
      ? configured
      : DEFAULT_MAX_IMAGES;
  }

  function bindInlineExpand(root) {
    var $root = root ? $(root) : $(document);
    var $threads;

    if ($root.is('div[id^="thread_"]')) {
      $threads = $root;
    } else {
      $threads = $root.find('div[id^="thread_"]');

      if (!$threads.length) {
        $threads = $root.closest('div[id^="thread_"]');
      }
    }

    $threads.each(function () {
      inlineExpandThread.call(this);
    });
  }

  function thumbnailElement(link) {
    return link.querySelector("canvas.post-image, img.post-image");
  }

  function fullImageElement(link) {
    return link.querySelector("img.full-image");
  }

  function loadingQueue() {
    var maxImages = configuredMaxImages();
    var loading = 0;
    var waiting = [];

    function update() {
      var element;

      while (loading < maxImages || maxImages === 0) {
        element = waiting.shift();
        if (!element) return;

        loading += 1;
        element.deferred.resolve();
      }
    }

    return {
      remove: function (element) {
        var index = waiting.indexOf(element);

        if (index > -1) {
          waiting.splice(index, 1);
        }

        if ($(element).data("imageLoading") === "true") {
          $(element).data("imageLoading", "false");
          clearTimeout(element.timeout);
          loading -= 1;
        }
      },

      add: function (element) {
        element.deferred = $.Deferred();
        element.deferred.done(function () {
          var loadStarted = $.Deferred();
          var thumbnail = thumbnailElement(element);
          var image = fullImageElement(element);

          if (!thumbnail || !image) {
            loading -= 1;
            $(element).data("imageLoading", "false");
            update();
            return;
          }

          function onLoadStart(candidate) {
            if (candidate.naturalWidth) {
              loadStarted.resolve(candidate, thumbnail);
            } else {
              element.timeout = setTimeout(onLoadStart, 30, candidate);
            }
          }

          $(image).one("load", function () {
            $.when(loadStarted).done(function () {
              loading -= 1;
              $(element).data("imageLoading", "false");
              update();
            });
          });

          loadStarted.done(function (loadedImage, originalThumbnail) {
            originalThumbnail.style.display = "none";
            loadedImage.style.display = "";
          });

          image.setAttribute("src", image.dataset.fullImageSrc || element.href);
          $(element).data("imageLoading", "true");
          onLoadStart(image);
        });

        if (loading < maxImages || maxImages === 0) {
          loading += 1;
          element.deferred.resolve();
        } else {
          waiting.push(element);
        }
      }
    };
  }

  function inlineExpandThread() {
    var links = this.querySelectorAll('a[data-inline-expandable="true"]');
    var queue = loadingQueue();

    for (var index = 0; index < links.length; index += 1) {
      var link = links[index];
      if (typeof link !== "object" || link.dataset.inlineExpandBound) continue;

      link.dataset.inlineExpandBound = "true";
      link.onclick = function (event) {
        var image;
        var postBody;
        var stillOpen;
        var canvas;
        var shouldScroll;
        var thumbnail = thumbnailElement(this);
        var padding = 5;
        var boardlist = $(".boardlist")[0];

        if (!thumbnail) return true;
        if (thumbnail.className === "hidden") return false;
        if (event.which === 2 || event.ctrlKey) return true;

        if (!$(this).data("expanded")) {
          if (this.parentNode.className.indexOf("multifile") > -1) {
            $(this).data("width", this.parentNode.style.width);
          }

          this.parentNode.removeAttribute("style");
          $(this).data("expanded", "true");

          if (thumbnail.tagName === "CANVAS") {
            canvas = thumbnail;
            thumbnail = thumbnail.nextElementSibling;
            this.removeChild(canvas);
            canvas.style.display = "block";
          }

          thumbnail.style.opacity = "0.4";
          thumbnail.style.filter = "alpha(opacity=40)";

          image = fullImageElement(this);
          if (!image) {
            image = document.createElement("img");
            image.className = "full-image";
            image.style.display = "none";
            image.setAttribute("alt", "Fullsized image");
            image.dataset.fullImageSrc = this.href;
            this.appendChild(image);
          }

          queue.add(this);
        } else {
          queue.remove(this);
          shouldScroll = event.target.className === "full-image";

          if (this.parentNode.className.indexOf("multifile") > -1) {
            this.parentNode.style.width = $(this).data("width");
          }

          thumbnail.style.opacity = "";
          thumbnail.style.display = "";
          image = fullImageElement(this);

          if (image) {
            image.style.display = "none";
            image.removeAttribute("src");
          }

          $(this).removeData("expanded");
          delete thumbnail.style.filter;

          if (shouldScroll) {
            postBody = $(thumbnail).closest(".post");

            if (!postBody.length) {
              if (
                localStorage.no_animated_gif === "true" &&
                typeof window.unanimate_gif === "function"
              ) {
                window.unanimate_gif(thumbnail);
              }

              return false;
            }

            stillOpen = postBody
              .find(".post-image")
              .filter(function () {
                return $(this).parent().data("expanded") === "true";
              }).length;

            if (boardlist && $(boardlist).css("position") === "fixed") {
              padding += boardlist.getBoundingClientRect().height;
            }

            if (stillOpen > 0) {
              if (thumbnail.getBoundingClientRect().top - padding < 0) {
                $(document).scrollTop($(thumbnail).parent().parent().offset().top - padding);
              }
            } else if (postBody[0].getBoundingClientRect().top - padding < 0) {
              $(document).scrollTop(postBody.offset().top - padding);
            }
          }

          if (
            localStorage.no_animated_gif === "true" &&
            typeof window.unanimate_gif === "function"
          ) {
            window.unanimate_gif(thumbnail);
          }
        }

        return false;
      };
    }
  }

  $(document).ready(function () {
    window.bind_inline_expanding = bindInlineExpand;
    bindInlineExpand(document.body);

    $(document).on("fragment_init", function (_event, root) {
      bindInlineExpand(root);
    });

    $(document).on("new_post", function (_event, post) {
      bindInlineExpand(post);
    });
  });
})(window, document, window.jQuery);
