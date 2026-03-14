/*
 * file-selector.js - Add support for drag and drop file selection, and paste from clipboard on supported browsers.
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/ajax.js';
 *   $config['additional_javascript'][] = 'js/file-selector.js';
 */
function init_file_selector(max_images, root) {
  if (/iPad|iPhone|iPod/.test(navigator.userAgent)) {
    return;
  }

  if (!(window.URL.createObjectURL && window.File)) {
    return;
  }

  if (typeof max_images === 'undefined') {
    max_images = 1;
  }

  var $root = root ? $(root) : $('form[name="post"]').first();
  if (!$root.length || $root.data('file-selector-initialized')) {
    return;
  }

  var $uploadCell = $root.find('#upload td, [data-upload-row] td').first();
  var $fileInput = $root.find('#upload_file, [data-upload-file]').first();

  if (!$uploadCell.length || !$fileInput.length) {
    return;
  }

  var $dropzoneWrap = $(
    '<div class="dropzone-wrap" style="display: none;">' +
      '<div class="dropzone" tabindex="0">' +
        '<div class="file-hint">' + _('Select/drop/paste files here') + '</div>' +
        '<div class="file-thumbs"></div>' +
      '</div>' +
    '</div>'
  );

  var files = [];
  var selectorNamespace = '.file_selector_' + ($root.attr('id') || Math.floor(Math.random() * 1000000));

  $dropzoneWrap.prependTo($uploadCell);
  $fileInput.remove();
  $dropzoneWrap.css('user-select', 'none').show();
  $root.data('file-selector-initialized', true);

  function thumbContainerCount() {
    return $root.find('.tmb-container').length;
  }

  function updateArrowVisibility() {
    $root.find('.tmb-container').each(function(index, element) {
      var $el = $(element);
      $el.find('.move-up-btn').toggle(index !== 0);
      $el.find('.move-down-btn').toggle(index !== thumbContainerCount() - 1);
    });
  }

  function removeFile(file) {
    files.splice(files.indexOf(file), 1);
  }

  function getThumbElement(file) {
    return $root.find('.tmb-container').filter(function() {
      return $(this).data('file-ref') === file;
    });
  }

  function addThumb(file) {
    var fileName = (file.name.length < 24) ? file.name : file.name.substr(0, 22) + '…';
    var fileType = file.type.split('/')[0];
    var fileExt = (file.type.split('/')[1] || file.name.split('.').pop() || '').toUpperCase();

    var $container = $('<div>')
      .addClass('tmb-container')
      .data('file-ref', file)
      .append(
        $('<div>').addClass('tmb-controls').append(
          $('<div>').addClass('remove-btn').text('✖'),
          $('<div>').addClass('move-up-btn').text('⬆'),
          $('<div>').addClass('move-down-btn').text('⬇'),
          $('<div>').addClass('strip-fn-btn').text('strip filename')
        ),
        $('<div>').addClass('file-tmb'),
        $('<div>').addClass('tmb-filename').text(fileName)
      )
      .appendTo($root.find('.file-thumbs').first());

    var $fileThumb = $container.find('.file-tmb');
    if (fileType === 'image') {
      var objURL = window.URL.createObjectURL(file);
      $fileThumb.css('background-image', 'url(' + objURL + ')');
    } else {
      $('<span>').text(fileExt).appendTo($fileThumb.empty());
    }

    updateArrowVisibility();
  }

  function addFile(file) {
    if (files.length === max_images) {
      return;
    }

    files.push(file);
    addThumb(file);
  }

  $root.on('click', '.move-up-btn', function(e) {
    e.stopPropagation();
    var $current = $(this).closest('.tmb-container');
    var file = $current.data('file-ref');
    var index = files.indexOf(file);

    if (index > 0) {
      var tmp = files[index - 1];
      files[index - 1] = files[index];
      files[index] = tmp;
      $current.insertBefore($current.prev());
      updateArrowVisibility();
    }
  });

  $root.on('click', '.move-down-btn', function(e) {
    e.stopPropagation();
    var $current = $(this).closest('.tmb-container');
    var file = $current.data('file-ref');
    var index = files.indexOf(file);

    if (index < files.length - 1) {
      var tmp = files[index + 1];
      files[index + 1] = files[index];
      files[index] = tmp;
      $current.insertAfter($current.next());
      updateArrowVisibility();
    }
  });

  $(document).on('ajax_before_post' + selectorNamespace, function(e, formData, form) {
    if (form !== $root[0]) {
      return;
    }

    for (var i = 0; i < max_images; i++) {
      var key = 'file';
      if (i > 0) key += i + 1;
      if (typeof files[i] === 'undefined') break;
      formData.append(key, files[i]);
    }
  });

  $(document).on('ajax_after_post' + selectorNamespace, function(e, response, form) {
    if (form !== $root[0]) {
      return;
    }

    files = [];
    $root.find('.file-thumbs').empty();
  });

  $(document).on('click' + selectorNamespace, '.strip-fn-btn', function(e) {
    if (!$.contains($root[0], this)) {
      return;
    }

    e.stopPropagation();
    var $container = $(this).closest('.tmb-container');
    var index = $container.parent().children('.tmb-container').index($container);
    var file = files[index] || $container.data('file-ref');

    if (!file || !file.name) {
      return;
    }

    var extension = file.name.indexOf('.') !== -1 ? file.name.split('.').pop() : '';
    var newName = extension ? (Date.now() + '.' + extension) : String(Date.now());
    var newFile = new File([file.slice(0, file.size, file.type)], newName, { type: file.type });

    files[index] = newFile;
    $container.data('file-ref', newFile);
    $container.find('.tmb-filename').text(newName);
  });

  var dragCounter = 0;
  var $dropzone = $root.find('.dropzone').first();

  $dropzone.on('dragenter dragover dragleave drop', function(e) {
    e.stopPropagation();
    e.preventDefault();
  });

  $dropzone.on('dragenter', function() {
    if (dragCounter === 0) {
      $dropzone.addClass('dragover');
    }
    dragCounter++;
  });

  $dropzone.on('dragleave', function() {
    dragCounter--;
    if (dragCounter <= 0) {
      dragCounter = 0;
      $dropzone.removeClass('dragover');
    }
  });

  $dropzone.on('drop', function(e) {
    $dropzone.removeClass('dragover');
    dragCounter = 0;

    var fileList = e.originalEvent.dataTransfer.files;
    for (var i = 0; i < fileList.length; i++) {
      addFile(fileList[i]);
    }
  });

  $root.on('click', '.remove-btn', function(e) {
    e.stopPropagation();
    var file = $(e.target).closest('.tmb-container').data('file-ref');
    getThumbElement(file).remove();
    removeFile(file);
    updateArrowVisibility();
  });

  $dropzone.on('keypress click', function(e) {
    e.stopPropagation();

    if ((e.which !== 1 || e.target.className !== 'file-hint') && e.which !== 13) {
      return;
    }

    var $selector = $('<input type="file" multiple>');

    $selector.on('change', function() {
      if (this.files.length > 0) {
        for (var i = 0; i < this.files.length; i++) {
          addFile(this.files[i]);
        }
      }
      $(this).remove();
    });

    $selector.trigger('click');
  });

  $(document).on('paste' + selectorNamespace, function(e) {
    if (!$.contains($root[0], document.activeElement) && document.activeElement !== $root[0]) {
      return;
    }

    var clipboard = e.originalEvent.clipboardData;
    if (typeof clipboard.items === 'undefined' || clipboard.items.length === 0) {
      return;
    }

    for (var i = 0; i < clipboard.items.length; i++) {
      if (clipboard.items[i].kind !== 'file') {
        continue;
      }

      var file = new File([clipboard.items[i].getAsFile()], 'file.png', { type: 'image/png' });
      addFile(file);
    }
  });
}

$(function() {
  $('form[data-post-form]').each(function() {
    var maxImages = parseInt($(this).attr('data-max-images') || '1', 10);
    if (isNaN(maxImages) || maxImages < 1) {
      maxImages = 1;
    }

    init_file_selector(maxImages, this);
  });
});
