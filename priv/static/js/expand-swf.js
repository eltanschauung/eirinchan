(function () {
  "use strict";

  function ready(callback) {
    if (typeof window.onReady === "function") {
      window.onReady(callback);
    } else if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback, { once: true });
    } else {
      callback();
    }
  }

  function swfUrlFor(link) {
    try {
      var url = new URL(link.getAttribute("href") || "", window.location.href);
      return /\.swf$/i.test(url.pathname) ? url.href : null;
    } catch (_error) {
      return null;
    }
  }

  function setupSWF(link, url) {
    if (link.swfAlreadySetUp) return;
    link.swfAlreadySetUp = true;

    var container = null;
    var player = null;
    var expanded = false;
    var originalParentWidth = link.parentElement ? link.parentElement.style.width : "";

    function collapse() {
      if (!expanded) return;

      expanded = false;
      link.style.display = "";

      if (container) {
        container.style.display = "none";
      }

      if (player && player.parentNode) {
        player.parentNode.removeChild(player);
      }

      player = null;

      if (link.parentElement) {
        link.parentElement.style.width = originalParentWidth;
      }
    }

    function ensureContainer() {
      if (container) return container;

      container = document.createElement("div");
      container.className = "ruffle";
      container.style.display = "none";
      container.style.paddingLeft = "15px";
      container.style.paddingRight = "15px";
      container.style.paddingBottom = "15px";

      var collapseButton = document.createElement("img");
      collapseButton.src = (window.configRoot || "/") + "static/collapse.gif";
      collapseButton.alt = "[ - ]";
      collapseButton.title = "Collapse SWF";
      collapseButton.style.marginLeft = "-15px";
      collapseButton.style.cssFloat = "left";
      collapseButton.addEventListener("click", collapse, false);

      link.parentNode.insertBefore(container, link.nextSibling);
      container.appendChild(collapseButton);

      return container;
    }

    link.addEventListener(
      "click",
      function (event) {
        if (
          event.button !== 0 ||
          event.metaKey ||
          event.ctrlKey ||
          event.shiftKey ||
          event.altKey
        ) {
          return;
        }

        if (!window.RufflePlayer || typeof window.RufflePlayer.newest !== "function") {
          return;
        }

        event.preventDefault();

        var swfContainer = ensureContainer();
        expanded = true;
        link.style.display = "none";
        swfContainer.style.display = "block";

        if (link.parentElement) {
          link.parentElement.style.width = "";
        }

        if (!player) {
          var ruffle = window.RufflePlayer.newest();
          player = ruffle.createPlayer();
          player.config = {
            allowScriptAccess: false,
            autoplay: "off",
            openUrlMode: "confirm",
            showSwfDownload: true
          };

          swfContainer.style.width = "550px";
          swfContainer.style.height = "400px";
          swfContainer.appendChild(player);

          player.addEventListener("loadedmetadata", function () {
            if (!player || !player.metadata) return;

            var width = player.metadata.width;
            var height = player.metadata.height;

            if (width && height) {
              swfContainer.style.width = width + "px";
              swfContainer.style.height = height + "px";
              player.style.width = width + "px";
              player.style.height = height + "px";
            }
          });
        }

        player.load({ url: url });
      },
      false
    );
  }

  function setupSWFsIn(root) {
    if (!root || !root.querySelectorAll) return;

    var links = root.querySelectorAll("a.file[href]");

    for (var i = 0; i < links.length; i++) {
      var url = swfUrlFor(links[i]);

      if (url) {
        setupSWF(links[i], url);
      }
    }
  }

  ready(function () {
    setupSWFsIn(document);

    document.addEventListener("eirinchan:fragment-init", function (event) {
      setupSWFsIn((event.detail && event.detail.root) || document);
    });

    if (window.MutationObserver) {
      new MutationObserver(function (mutations) {
        for (var i = 0; i < mutations.length; i++) {
          for (var j = 0; j < mutations[i].addedNodes.length; j++) {
            var node = mutations[i].addedNodes[j];
            if (node.nodeType === 1) {
              setupSWFsIn(node);
            }
          }
        }
      }).observe(document.body, { childList: true, subtree: true });
    }
  });
})();
