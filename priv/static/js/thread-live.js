;(function () {
  if (!window.Phoenix || !window.Phoenix.LiveView) return;

  var tokenMeta = document.querySelector("meta[name='csrf-token']");
  if (!tokenMeta) return;

  var Hooks = {};

  Hooks.ThreadReply = {
    mounted: function () {
      var self = this;

      this.handleEvent("reply-visible", function (payload) {
        var id = String(payload.id);

        window.requestAnimationFrame(function () {
          window.requestAnimationFrame(function () {
            var anchor = document.getElementById(id);
            var reply = document.getElementById("reply_" + id);
            var target = anchor || reply;
            var submit = self.el.querySelector("[data-reply-submit]");

            if (submit) {
              submit.disabled = false;
              submit.value = submit.dataset.label || submit.value;
            }

            if (!target) return;

            try {
              if (window.history && window.history.replaceState) {
                window.history.replaceState(null, document.title, window.location.pathname + window.location.search + "#" + id);
              } else {
                window.location.hash = id;
              }
            } catch (_error) {
              window.location.hash = id;
            }

            if (target.scrollIntoView) {
              target.scrollIntoView({block: "start"});
            }

            if (window.highlightReply) {
              window.highlightReply(id);
            }
          });
        });
      });
    }
  };

  var liveSocket = new window.Phoenix.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    params: {_csrf_token: tokenMeta.getAttribute("content")},
    hooks: Hooks
  });

  liveSocket.connect();
  window.liveSocket = liveSocket;
})();
