function init_file_selector(maxFiles, targetForm) {
  if (maxFiles === undefined) {
    maxFiles = 1;
  }

  var $form = targetForm ? $(targetForm) : $('form[name="post"]').first();

  if (!$form.length || $form.data("file-selector-initialized")) {
    return false;
  }

  var $row = $form.find("#upload td, [data-upload-row] td").first();
  var $input = $row.find("#upload_file, [data-upload-file]").first();
  var $nativeWrap = $row.find("[data-native-upload]").first();
  var $shell = $row.find(".dropzone-wrap").first();
  var $dropzone = $shell.find(".dropzone").first();
  var $thumbs = $shell.find(".file-thumbs").first();

  if (!$row.length || !$input.length || !$nativeWrap.length || !$shell.length || !$dropzone.length || !$thumbs.length) {
    return false;
  }

  if (!supportsEnhancedFileSelector()) {
    $form.attr("data-file-selector-enhanced", "false");
    $shell.attr("hidden", true).hide();
    $nativeWrap.show();
    return false;
  }

  var files = [];
  var namespace = ".file_selector_" + ($form.attr("id") || Math.floor(Math.random() * 1000000));
  var dragDepth = 0;

  $form.data("file-selector-initialized", true);
  $form.attr("data-file-selector-enhanced", "true");

  function showEnhancedUi() {
    $shell.removeAttr("hidden").show();
    $nativeWrap.hide();

    if (typeof window.syncFileSelectorVisibility === "function") {
      window.syncFileSelectorVisibility($form);
    }
  }

  function syncInputFiles() {
    var transfer = new DataTransfer();

    files.slice(0, maxFiles).forEach(function (file) {
      transfer.items.add(file);
    });

    files = Array.from(transfer.files);
    $input[0].files = transfer.files;
  }

  function updateMoveButtons() {
    $thumbs.find(".tmb-container").each(function (index) {
      var $thumb = $(this);
      $thumb.find(".move-up-btn").toggle(index !== 0);
      $thumb.find(".move-down-btn").toggle(index !== $thumbs.find(".tmb-container").length - 1);
    });
  }

  function renderFileThumb(file) {
    var filename = file.name.length < 24 ? file.name : file.name.substr(0, 22) + "…";
    var majorType = file.type.split("/")[0];
    var extension = (file.type.split("/")[1] || file.name.split(".").pop() || "").toUpperCase();

    var $thumb = $("<div>")
      .addClass("tmb-container")
      .data("file-ref", file)
      .append(
        $("<div>")
          .addClass("tmb-controls")
          .append(
            $("<div>").addClass("remove-btn").text("✖"),
            $("<div>").addClass("move-up-btn").text("⬆"),
            $("<div>").addClass("move-down-btn").text("⬇"),
            $("<div>").addClass("strip-fn-btn").text("strip filename")
          ),
        $("<div>").addClass("file-tmb"),
        $("<div>").addClass("tmb-filename").text(filename)
      )
      .appendTo($thumbs);

    var $preview = $thumb.find(".file-tmb");

    if (majorType === "image") {
      $preview.css("background-image", "url(" + window.URL.createObjectURL(file) + ")");
    } else {
      $("<span>").text(extension).appendTo($preview.empty());
    }
  }

  function renderFiles() {
    $thumbs.empty();
    files.forEach(renderFileThumb);
    updateMoveButtons();
  }

  function applyFiles(nextFiles) {
    files = nextFiles.slice(0, maxFiles);
    syncInputFiles();
    renderFiles();
  }

  function mergeFiles(newFiles) {
    if (!newFiles.length) {
      return;
    }

    applyFiles(files.concat(newFiles));
  }

  function removeFile(file) {
    applyFiles(
      files.filter(function (candidate) {
        return candidate !== file;
      })
    );
  }

  function reorderFile(file, offset) {
    var index = files.indexOf(file);
    var nextIndex = index + offset;

    if (index < 0 || nextIndex < 0 || nextIndex >= files.length) {
      return;
    }

    var swapped = files.slice();
    var temp = swapped[nextIndex];
    swapped[nextIndex] = swapped[index];
    swapped[index] = temp;
    applyFiles(swapped);
  }

  function stripFilename(file) {
    if (!file || !file.name) {
      return;
    }

    var extension = file.name.indexOf(".") !== -1 ? file.name.split(".").pop() : "";
    var strippedName = extension ? Date.now() + "." + extension : String(Date.now());
    var renamed = new File([file.slice(0, file.size, file.type)], strippedName, { type: file.type });

    applyFiles(
      files.map(function (candidate) {
        return candidate === file ? renamed : candidate;
      })
    );
  }

  function preventBrowserFileHandling(event) {
    event.preventDefault();
  }

  function handleNativeInputChange() {
    mergeFiles(Array.from($input[0].files || []));
  }

  function handleDrop(event) {
    event.stopPropagation();
    event.preventDefault();
    dragDepth = 0;
    $dropzone.removeClass("dragover");

    var droppedFiles = Array.from((event.originalEvent || event).dataTransfer.files || []);
    mergeFiles(droppedFiles);
  }

  function normalizePastedFile(file) {
    if (!file) {
      return null;
    }

    var name = file.name || "";
    var dotIndex = name.lastIndexOf(".");
    var baseName = dotIndex === -1 ? name : name.slice(0, dotIndex);
    var extension = dotIndex === -1 ? "" : name.slice(dotIndex + 1);

    if (!extension) {
      extension = (file.type.split("/")[1] || "").trim();
    }

    if (name && !/^image$/i.test(baseName)) {
      return file;
    }

    var normalizedName = extension ? "file." + extension : "file";

    if (name === normalizedName) {
      return file;
    }

    return new File([file], normalizedName, {
      type: file.type,
      lastModified: file.lastModified
    });
  }

  function handlePaste(event) {
    if (!$.contains($form[0], document.activeElement) && document.activeElement !== $form[0]) {
      return;
    }

    var clipboardData = (event.originalEvent || event).clipboardData;
    if (!clipboardData || clipboardData.items === undefined || clipboardData.items.length === 0) {
      return;
    }

    var pastedFiles = [];

    for (var index = 0; index < clipboardData.items.length; index++) {
      if (clipboardData.items[index].kind === "file") {
        pastedFiles.push(normalizePastedFile(clipboardData.items[index].getAsFile()));
      }
    }

    mergeFiles(
      pastedFiles.filter(function (file) {
        return !!file;
      })
    );
  }

  $form.on("change" + namespace, "#upload_file, [data-upload-file]", handleNativeInputChange);

  $form.on("click" + namespace, ".remove-btn", function (event) {
    event.stopPropagation();
    removeFile($(event.target).closest(".tmb-container").data("file-ref"));
  });

  $form.on("click" + namespace, ".move-up-btn", function (event) {
    event.stopPropagation();
    reorderFile($(event.target).closest(".tmb-container").data("file-ref"), -1);
  });

  $form.on("click" + namespace, ".move-down-btn", function (event) {
    event.stopPropagation();
    reorderFile($(event.target).closest(".tmb-container").data("file-ref"), 1);
  });

  $form.on("click" + namespace, ".strip-fn-btn", function (event) {
    event.stopPropagation();
    stripFilename($(event.target).closest(".tmb-container").data("file-ref"));
  });

  $dropzone.on("click" + namespace, function (event) {
    if ($(event.target).closest(".tmb-container, .tmb-controls").length) {
      return;
    }

    $input.trigger("click");
  });

  $dropzone.on("keydown" + namespace, function (event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      $input.trigger("click");
    }
  });

  ["dragenter", "dragover", "dragleave", "drop"].forEach(function (eventName) {
    $form[0].addEventListener(eventName, preventBrowserFileHandling, true);
  });

  $form.on("dragenter" + namespace, function (event) {
    event.stopPropagation();
    event.preventDefault();

    if (dragDepth === 0) {
      $dropzone.addClass("dragover");
    }

    dragDepth += 1;
  });

  $form.on("dragover" + namespace, function (event) {
    event.stopPropagation();
    event.preventDefault();
  });

  $form.on("dragleave" + namespace, function (event) {
    event.stopPropagation();
    event.preventDefault();

    dragDepth = Math.max(dragDepth - 1, 0);

    if (dragDepth === 0) {
      $dropzone.removeClass("dragover");
    }
  });

  $form.on("drop" + namespace, handleDrop);
  $(document).off("paste" + namespace).on("paste" + namespace, handlePaste);
  $(document)
    .off("ajax_after_post" + namespace)
    .on("ajax_after_post" + namespace, function (_event, _payload, submittedForm) {
      if (submittedForm !== $form[0]) {
        return;
      }

      applyFiles([]);
    });

  showEnhancedUi();
  applyFiles(Array.from($input[0].files || []));
  return true;
}

function supportsEnhancedFileSelector() {
  return !!(
    window.File &&
    window.URL &&
    typeof window.URL.createObjectURL === "function" &&
    typeof window.DataTransfer === "function"
  );
}

$((function () {
  $("form[data-post-form]").each(function () {
    var maxImages = parseInt($(this).attr("data-max-images") || "1", 10);

    if (isNaN(maxImages) || maxImages < 1) {
      maxImages = 1;
    }

    init_file_selector(maxImages, this);
  });
}));
