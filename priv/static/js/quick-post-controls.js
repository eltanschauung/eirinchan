$(document).ready(function () {
  function resolveBoard($checkbox) {
    var board = $("input[name=board]:first").val();

    if (board) {
      return board;
    }

    var $container = $checkbox.closest("[data-board],[data-board-uri]");
    return $container.attr("data-board") || $container.attr("data-board-uri") || "";
  }

  function resolvePostId($checkbox) {
    var match = ($checkbox.attr("name") || "").match(/^delete_(\d+)$/);
    return match ? match[1] : null;
  }

  function buildActionsForm($checkbox) {
    var $post = $checkbox.closest("div.post");
    var postId = resolvePostId($checkbox);

    if (!$post.length || !postId) {
      return $();
    }

    var isOp = $post.hasClass("op");
    var board = resolveBoard($checkbox);
    var csrfToken = $("input[name=_csrf_token]:first").val() || $('meta[name="csrf-token"]').attr("content") || "";
    var action = $('form[name="post"]:first').attr("action") || "/post.php";
    var $form = $(
      '<form class="post-actions" method="post" style="margin:10px 0 0 0">' +
        '<div style="text-align:right">' +
          (isOp ? "" : "<hr>") +
          '<input type="hidden" name="delete_' + postId + '">' +
          '<label for="password_' + postId + '">' + _("Password") + '</label>: ' +
          '<input id="password_' + postId + '" type="password" name="password" size="11" maxlength="18" autocomplete="off">' +
          '<input title="' + _("Delete file only") + '" type="checkbox" name="file" id="delete_file_' + postId + '">' +
          '<label for="delete_file_' + postId + '">' + _("File") + '</label> ' +
          '<input type="submit" name="delete" value="' + _("Delete") + '">' +
          '<br><label for="reason_' + postId + '">' + _("Reason") + '</label>: ' +
          '<input id="reason_' + postId + '" type="text" name="reason" size="20" maxlength="100"> ' +
          '<input type="submit" name="report" value="' + _("Report") + '">' +
        '</div>' +
      '</form>'
    );

    $form
      .attr("action", action)
      .append($('<input type="hidden" name="board">').val(board))
      .append($('<input type="hidden" name="_csrf_token">').val(csrfToken))
      .find('input:not([type="checkbox"]):not([type="submit"]):not([type="hidden"])')
      .keypress(function (event) {
        if (event.which !== 13) {
          return;
        }

        event.preventDefault();

        if ($(this).attr("name") === "password") {
          $form.find('input[name="delete"]').trigger("click");
        } else if ($(this).attr("name") === "reason") {
          $form.find('input[name="report"]').trigger("click");
        }

        return false;
      });

    $form.find('input[type="password"]').val(localStorage.password || "");

    if (isOp) {
      $form.prependTo($post.find("div.body").first());
    } else {
      $form.appendTo($post);
    }

    $(window).trigger("quick-post-controls", $form);
    return $form;
  }

  function removeActionsForm($checkbox) {
    $checkbox.closest("div.post").find("form.post-actions").remove();
  }

  function syncActionsForm(checkbox) {
    var $checkbox = $(checkbox);

    if ($checkbox.is(":checked")) {
      buildActionsForm($checkbox);
    } else {
      removeActionsForm($checkbox);
    }
  }

  function hydrateChecked(root) {
    var $root = root ? $(root) : $(document);

    $root
      .filter('div.post input[type="checkbox"].delete:checked')
      .add($root.find('div.post input[type="checkbox"].delete:checked'))
      .each(function () {
        this.dataset.quickPostControlsBound = "true";
        syncActionsForm(this);
      });

    $root
      .filter('div.post input[type="checkbox"].delete')
      .add($root.find('div.post input[type="checkbox"].delete'))
      .each(function () {
        this.dataset.quickPostControlsBound = "true";
      });
  }

  $(document)
    .off("change.quickPostControls")
    .on("change.quickPostControls", 'div.post input[type="checkbox"].delete', function () {
      this.dataset.quickPostControlsBound = "true";
      syncActionsForm(this);
    });

  hydrateChecked(document.body);

  $(document).on("fragment_init", function (_event, root) {
    hydrateChecked(root);
  });

  $(document).on("new_post", function (_event, root) {
    hydrateChecked(root);
  });
});
