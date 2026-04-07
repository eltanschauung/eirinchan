$(window).ready(function () {
  var fallbackSubmit = false;
  var csrfRefreshRequest = null;

  function currentCsrfToken() {
    var metaToken = document.querySelector('meta[name="csrf-token"]');
    if (metaToken && metaToken.content) {
      return metaToken.content;
    }

    var inputToken = document.querySelector('input[name="_csrf_token"]');
    return inputToken ? inputToken.value : "";
  }

  function applyCsrfToken(token) {
    if (!token) {
      return;
    }

    var metaToken = document.querySelector('meta[name="csrf-token"]');
    if (metaToken) {
      metaToken.setAttribute("content", token);
    }

    $('input[name="_csrf_token"]').val(token);
  }

  function refreshCsrfToken() {
    if (csrfRefreshRequest) {
      return csrfRefreshRequest;
    }

    csrfRefreshRequest = $.ajax({
      url: "/csrf-token",
      type: "GET",
      dataType: "json",
      cache: false,
      headers: {
        "Cache-Control": "no-cache",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(function (payload) {
        var token = payload && payload.csrf_token;

        if (!token) {
          return $.Deferred().reject().promise();
        }

        applyCsrfToken(token);
        return token;
      })
      .always(function () {
        csrfRefreshRequest = null;
      });

    return csrfRefreshRequest;
  }

  function ajaxPostUrl(form) {
    return form.getAttribute("data-ajax-action") || "/api/post";
  }

  function parsedErrorMessage(xhr) {
    if (!xhr) {
      return null;
    }

    if (xhr.responseJSON) {
      if (xhr.responseJSON.error) {
        return xhr.responseJSON.error;
      }

      if (
        xhr.responseJSON.errors &&
        typeof xhr.responseJSON.errors.detail === "string" &&
        xhr.responseJSON.errors.detail.length
      ) {
        return xhr.responseJSON.errors.detail;
      }
    }

    if (typeof xhr.responseText === "string" && xhr.responseText.length) {
      try {
        var parsed = JSON.parse(xhr.responseText);

        if (parsed && parsed.error) {
          return parsed.error;
        }

        if (
          parsed &&
          parsed.errors &&
          typeof parsed.errors.detail === "string" &&
          parsed.errors.detail.length
        ) {
          return parsed.errors.detail;
        }
      } catch (_error) {
        return null;
      }
    }

    return null;
  }

  function isCsrfFailure(xhr, parsedMessage) {
    if (!xhr || xhr.status !== 403) {
      return false;
    }

    if (xhr.responseJSON && xhr.responseJSON.csrf === true) {
      return true;
    }

    var message = (parsedMessage || "").toLowerCase();
    if (
      message.indexOf("csrf") !== -1 ||
      message.indexOf("forgery") !== -1 ||
      message.indexOf("out of date") !== -1
    ) {
      return true;
    }

    var responseText = (xhr.responseText || "").trim().toLowerCase();
    if (
      responseText.indexOf("csrf") !== -1 ||
      responseText.indexOf("forgery") !== -1 ||
      responseText === "forbidden"
    ) {
      return true;
    }

    return false;
  }

  $('input[type="submit"]').removeAttr("disabled");

  $(document).off("submit.ajax_post", "form[data-post-form]");
  $(document).on("submit.ajax_post", "form[data-post-form]", function () {
    if (fallbackSubmit) {
      return true;
    }

    var form = this;
    var $form = $(form);
    var $submitInputs = $form.find('input[type="submit"]');
    var submitLabel = $(this).find('input[type="submit"]').val();
    var isReply = $form.find('input[name="thread_id"], input[name="thread"]').length > 0;

    if (window.FormData === undefined) {
      return true;
    }

    if ($form.data("ajax-posting")) {
      return false;
    }

    function resetFormState() {
      $form.removeData("ajax-posting");
      $submitInputs.val(submitLabel);
      $submitInputs.removeAttr("disabled");
    }

    function dispatchAfterPost(postPayload) {
      try {
        if (
          window.EirinchanFrontend &&
          typeof window.EirinchanFrontend.dispatchAjaxAfterPostSuccess === "function"
        ) {
          window.EirinchanFrontend.dispatchAjaxAfterPostSuccess(postPayload, form);
        } else {
          $(document).trigger("ajax_after_post", [postPayload, form]);
        }
      } catch (error) {
        console.error(error);
      }
    }

    function maybeMarkWatchedThreadSeen(postPayload) {
      if (!isReply || typeof window.markWatchedThreadSeen !== "function") {
        return;
      }

      var threadId = parseInt(
        $(form).find('input[name="thread_id"], input[name="thread"]').first().val(),
        10
      );
      var board = $(form).find('input[name="board"]').first().val();
      var threadElement = document.querySelector('.thread[data-thread-id="' + threadId + '"]');

      if (threadId && board && threadElement && threadElement.dataset.watched === "true") {
        window.markWatchedThreadSeen(board, threadId, postPayload.id);
      }
    }

    function updateThreadPageState(postPayload) {
      if (!isReply || !postPayload) {
        return;
      }

      if (postPayload.board_page_num) {
        $("#thread_stats_page").text(postPayload.board_page_num);
        $("#thread-refresh-target").attr("data-board-page-num", postPayload.board_page_num);
      }

      if (postPayload.board_page_path) {
        $("#thread-return, #thread-return-top").attr("href", postPayload.board_page_path);
        $("#thread-refresh-target").attr("data-board-page-path", postPayload.board_page_path);
      }
    }

    function clearPostFields() {
      $(form)
        .find(
          'input[name="subject"], input[name="file_url"], input[name="embed"], textarea[name="body"], input[type="file"]'
        )
        .val("")
        .change();
    }

    function updateProgress(event) {
      var progress =
        event.position === undefined
          ? Math.round((event.loaded * 100) / event.total)
          : Math.round((event.position * 100) / event.total);

      $(form)
        .find('input[type="submit"]')
        .val(_("Posting... (#%)").replace("#", progress));
    }

    $form.data("ajax-posting", true);

    function syncEnhancedUploadPayload(payload) {
      var selectedFiles = $form.data("file-selector-files");
      var inputName = $form.data("file-selector-input-name");

      if (
        $form.attr("data-file-selector-enhanced") !== "true" ||
        !inputName ||
        !Array.isArray(selectedFiles) ||
        typeof payload.delete !== "function"
      ) {
        return;
      }

      payload.delete(inputName);

      selectedFiles.forEach(function (file) {
        payload.append(inputName, file);
      });
    }

    function submitAjax(firstAttempt) {
      var payload = new FormData(form);
      syncEnhancedUploadPayload(payload);
      payload.set("_csrf_token", currentCsrfToken());
      payload.set("post", submitLabel);

      $(document).trigger("ajax_before_post", [payload, form]);

      $.ajax(
        {
          url: ajaxPostUrl(form),
          type: "POST",
          dataType: "json",
          cache: false,
          contentType: false,
          processData: false,
          headers: {
            "Accept": "application/json",
            "X-CSRF-Token": currentCsrfToken(),
            "X-Requested-With": "XMLHttpRequest"
          },
          xhr: function () {
            var xhr = $.ajaxSettings.xhr();

            if (xhr.upload) {
              xhr.upload.addEventListener("progress", updateProgress, false);
            }

            return xhr;
          },
          success: function (response) {
            if (response.error) {
              if (response.banned) {
                fallbackSubmit = true;

                $(form)
                  .find('input[type="submit"]')
                  .each(function () {
                    var hidden = $("<input type=\"hidden\">");
                    hidden.attr("name", $(this).attr("name"));
                    hidden.val(submitLabel);
                    $(this).after(hidden).replaceWith($("<input type=\"button\">").val(submitLabel));
                  });

                $(form).submit();
              } else {
                alert(response.error);
                resetFormState();
              }

              return;
            }

            if (!(response.redirect && response.id)) {
              alert(_("An unknown error occured when posting!"));
              resetFormState();
              return;
            }

            if (!isReply) {
              dispatchAfterPost(response);
              document.location = response.redirect;
              return;
            }

            $submitInputs.val(_("Posted..."));

            var $reply = (function appendReply(replyPayload) {
              if (!replyPayload || !replyPayload.html) {
                return $("div.post#reply_" + replyPayload.id).first();
              }

              var existingReply = $("div.post#reply_" + replyPayload.id).first();
              if (existingReply.length) {
                return existingReply;
              }

              var replyNode = $($.parseHTML(replyPayload.html, document, true));
              var $threadRefreshTarget = $("#thread-refresh-target");

              if ($threadRefreshTarget.length) {
                $threadRefreshTarget.append(replyNode);
              } else {
                var $thread = $("div.thread").first();
                if ($thread.length) {
                  $thread.append(replyNode);
                }
              }

              return $("div.post#reply_" + replyPayload.id).first();
            })(response);

            if (!$reply.length) {
              clearPostFields();
              resetFormState();
              maybeMarkWatchedThreadSeen(response);
              updateThreadPageState(response);
              dispatchAfterPost(response);

              try {
                if (history && history.replaceState) {
                  history.replaceState(
                    null,
                    document.title,
                    window.location.pathname + window.location.search + "#" + response.id
                  );
                } else {
                  window.location.hash = response.id;
                }
              } catch (_error) {
                window.location.hash = response.id;
              }

              alert(_("Reply posted. Refresh to see it."));
              return;
            }

            var replyElement = document.getElementById(String(response.id)) || $reply[0];

            try {
              if (typeof window.syncBacklinksFromPost === "function") {
                window.syncBacklinksFromPost($reply[0]);
              }
            } catch (error) {
              console.error(error);
            }

            clearPostFields();
            resetFormState();
            maybeMarkWatchedThreadSeen(response);
            updateThreadPageState(response);
            dispatchAfterPost(response);

            try {
              if (
                window.EirinchanFrontend &&
                typeof window.EirinchanFrontend.dispatchNewPost === "function"
              ) {
                window.EirinchanFrontend.dispatchNewPost($reply[0]);
              } else {
                $(document).trigger("new_post", $reply[0]);
              }
            } catch (error) {
              console.error(error);
            }

            window.requestAnimationFrame(function () {
              window.requestAnimationFrame(function () {
                try {
                  if (history && history.replaceState) {
                    history.replaceState(
                      null,
                      document.title,
                      window.location.pathname + window.location.search + "#" + response.id
                    );
                  } else {
                    window.location.hash = response.id;
                  }
                } catch (_error) {
                  window.location.hash = response.id;
                }

                if (replyElement.scrollIntoView) {
                  replyElement.scrollIntoView({ block: "start" });
                } else {
                  $(window).scrollTop($reply.offset().top);
                }

                try {
                  highlightReply(response.id);
                } catch (error) {
                  console.error(error);
                }

                setTimeout(function () {
                  $(window).trigger("scroll");
                }, 50);
              });
            });
          },
          error: function (xhr) {
            console.log(xhr);

            var message = parsedErrorMessage(xhr);
            var csrfFailure = isCsrfFailure(xhr, message);

            if (firstAttempt && csrfFailure) {
              refreshCsrfToken()
                .done(function () {
                  submitAjax(false);
                })
                .fail(function () {
                  alert(_("Your tab is out of date. Refresh the page and try again."));
                  resetFormState();
                });

              return;
            }

            if (message) {
              alert(message);
            } else if (csrfFailure) {
              alert(_("Your tab is out of date. Refresh the page and try again."));
            } else if (xhr && xhr.status >= 400 && xhr.status < 500) {
              alert(_("Your post was rejected by the server. Refresh and try again."));
            } else if (xhr && xhr.status >= 500) {
              alert(_("The server hit an internal error while processing your post. Please try again in a moment."));
            } else {
              alert(
                _(
                  "The server took too long to submit your post. Your post was probably still submitted. If it wasn't, we might be experiencing issues right now -- please try your post again later."
                )
              );
            }

            resetFormState();
          },
          complete: function () {
            if ($submitInputs.val() !== _("Posted...")) {
              $form.removeData("ajax-posting");
            }
          },
          data: payload
        },
        "json"
      );
    }

    submitAjax(true);
    $submitInputs.val(_("Posting..."));
    $submitInputs.attr("disabled", true);
    return false;
  });
});
