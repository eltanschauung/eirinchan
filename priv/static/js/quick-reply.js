/*
 * quick-reply.js
 *
 * Server-rendered quick reply form. JS owns lifecycle only.
 */

(function() {
  var settings = new script_settings('quick-reply');

  var get_live_quick_reply = function() {
    return $('form#quick-reply').filter(function() {
      return $(this).closest('template').length === 0;
    }).first();
  };

  var restore_body_owner = function($origPostForm, $postForm) {
    $postForm.find('textarea[name="body"]').removeAttr('id');
    $origPostForm.find('textarea[name="body"]').attr('id', 'body');
  };

  var activate_quick_reply_body = function($origPostForm, $postForm) {
    $origPostForm.find('textarea[name="body"]').removeAttr('id');
    $postForm.find('textarea[name="body"]').attr('id', 'body');
  };

  var sync_field_value = function($source, $target) {
    if (!$source.length || !$target.length) return;

    if ($source.is(':checkbox')) {
      $target.prop('checked', $source.prop('checked'));
    } else {
      $target.val($source.val());
    }
  };

  var bind_sync = function($origPostForm, $postForm) {
    var names = [
      'name',
      'email',
      'subject',
      'password',
      'user_flag',
      'tag',
      'embed',
      'captcha',
      'g-recaptcha-response',
      'h-captcha-response',
      'antispam_answer',
      'no_country',
      'spoiler'
    ];

    var selector = names.map(function(name) {
      return '[name="' + name + '"]';
    }).join(', ');

    $origPostForm.find(selector).each(function() {
      var $source = $(this);
      var $target = $postForm.find('[name="' + $source.attr('name') + '"]').first();
      sync_field_value($source, $target);
    });

    sync_field_value($origPostForm.find('textarea[name="body"]').first(), $postForm.find('textarea[name="body"]').first());

    $origPostForm.on('change input propertychange', selector, function() {
      var $source = $(this);
      var $target = $postForm.find('[name="' + $source.attr('name') + '"]').first();
      sync_field_value($source, $target);
    });

    $postForm.on('change input propertychange', selector, function() {
      var $source = $(this);
      var $target = $origPostForm.find('[name="' + $source.attr('name') + '"]').first();
      sync_field_value($source, $target);
    });

    $origPostForm.find('textarea[name="body"]').on('change input propertychange', function() {
      sync_field_value($(this), $postForm.find('textarea[name="body"]').first());
    });

    $postForm.find('textarea[name="body"]').on('change input propertychange', function() {
      sync_field_value($(this), $origPostForm.find('textarea[name="body"]').first());
    });
  };

  var init_drag = function($postForm) {
    if (typeof $postForm.draggable === 'undefined') return;

    if (localStorage.quickReplyPosition) {
      var offset = JSON.parse(localStorage.quickReplyPosition);
      if (offset.top < 0) offset.top = 0;
      if (offset.right > $(window).width() - $postForm.width()) {
        offset.right = $(window).width() - $postForm.width();
      }
      if (offset.top > $(window).height() - $postForm.height()) {
        offset.top = $(window).height() - $postForm.height();
      }
      $postForm.css('right', offset.right).css('top', offset.top);
    }

    $postForm.draggable({
      handle: 'th .handle',
      containment: 'window',
      distance: 10,
      scroll: false,
      stop: function() {
        var offset = {
          top: $(this).offset().top - $(window).scrollTop(),
          right: $(window).width() - $(this).offset().left - $(this).width()
        };

        localStorage.quickReplyPosition = JSON.stringify(offset);
        $postForm.css('right', offset.right).css('top', offset.top).css('left', 'auto');
      }
    });

    $postForm.find('th .handle').css('cursor', 'move');
  };

  var copy_styles = function($source, $target, properties) {
    if (!$source.length || !$target.length) return;

    var computed = window.getComputedStyle($source[0]);
    var css = {};

    properties.forEach(function(property) {
      css[property] = computed[property];
    });

    $target.css(css);
  };

  var sync_shell_theme = function($origPostForm, $postForm) {
    var $dummyReply = $('<div class="post reply"></div>').appendTo($('body'));
    var $table = $postForm.find('table.postForm').first();
    var $sourceTable = $origPostForm.find('table.postForm').first();
    var $sourceTh = $origPostForm.find('table.postForm th').first();
    var $sourceDropzone = $origPostForm.find('.dropzone').first();
    var $targetTh = $postForm.find('th');
    var $targetDropzone = $postForm.find('.dropzone');

    copy_styles($dummyReply, $table, [
      'backgroundColor',
      'borderStyle',
      'borderWidth',
      'borderColor',
      'borderRadius',
      'boxShadow'
    ]);

    copy_styles($dummyReply, $postForm, [
      'backgroundColor',
      'borderStyle',
      'borderWidth',
      'borderColor',
      'borderRadius',
      'boxShadow'
    ]);

    copy_styles($sourceTable, $table, [
      'background',
      'backgroundColor',
      'backgroundImage',
      'backgroundPosition',
      'backgroundRepeat',
      'backgroundSize',
      'backgroundAttachment',
      'borderStyle',
      'borderWidth',
      'borderColor',
      'borderRadius',
      'boxShadow',
      'color'
    ]);
    copy_styles($sourceTh, $targetTh, [
      'backgroundColor',
      'color',
      'borderColor',
      'borderStyle',
      'borderWidth'
    ]);
    copy_styles($sourceDropzone, $targetDropzone, [
      'backgroundColor',
      'borderColor',
      'borderStyle',
      'borderWidth',
      'color'
    ]);

    $dummyReply.remove();
  };

  var show_quick_reply = function() {
    if ($('div.banner').length === 0) return;

    var $existingPostForm = get_live_quick_reply();
    if ($existingPostForm.length) {
      return $existingPostForm;
    }

    var template = document.getElementById('quick-reply-template');
    if (!template) return;

    var html = template.innerHTML.trim();
    if (!html) return;

    var $postForm = $(html);
    var $origPostForm = $('form[name="post"]:first');

    bind_sync($origPostForm, $postForm);

    $postForm.find('textarea[name="body"]').on('focus', function() {
      activate_quick_reply_body($origPostForm, $postForm);
    });

    $origPostForm.find('textarea[name="body"]').on('focus.quick_reply', function() {
      restore_body_owner($origPostForm, $postForm);
    });

    $postForm.find('th .close-btn').click(function() {
      restore_body_owner($origPostForm, $postForm);
      $origPostForm.off('.quick_reply');
      $postForm.remove();
      floating_link();
    });

    $postForm.appendTo($('body')).hide();

    init_drag($postForm);
    if (typeof init_file_selector !== 'undefined') {
      var maxImages = parseInt($postForm.attr('data-max-images') || '1', 10);
      if (isNaN(maxImages) || maxImages < 1) {
        maxImages = 1;
      }
      init_file_selector(maxImages, $postForm);
    }
    sync_shell_theme($origPostForm, $postForm);

    $postForm.show();
    $postForm.width($postForm.find('table').width());
    $postForm.hide();

    $(window).trigger('quick-reply', [$postForm[0]]);

    $(window).ready(function() {
      if (settings.get('hide_at_top', true)) {
        $(window).scroll(function() {
          if ($(this).width() <= 400) return;
          if ($(this).scrollTop() < $origPostForm.offset().top + $origPostForm.height() - 100) {
            $postForm.fadeOut(100);
          } else {
            $postForm.fadeIn(100);
          }
        }).scroll();
      } else {
        $postForm.show();
      }

      $(window).on('stylesheet', function() {
        sync_shell_theme($origPostForm, $postForm);
      });
    });

    return $postForm;
  };

  $(window).on('cite', function(e, id, with_link) {
    if ($(this).width() <= 400) return;

    var $postForm = show_quick_reply();
    var $origPostForm = $('form[name="post"]:first');

    if ($postForm && $postForm.length) {
      activate_quick_reply_body($origPostForm, $postForm);

      if (settings.get('hide_at_top', true)) {
        $postForm.stop(true, true).fadeIn(100);
      } else {
        $postForm.show();
      }
    }

    if (with_link) {
      $(document).ready(function() {
        if ($('#' + id).length) {
          highlightReply(id);
          $(document).scrollTop($('#' + id).offset().top);
        }

        setTimeout(function() {
          var $textarea = $('#quick-reply textarea[name="body"]');
          var tmp = $textarea.val();
          $textarea.val('').focus().val(tmp);
        }, 1);
      });
    }
  });

  var floating_link = function() {
    if (!settings.get('floating_link', false)) return;

    $('<a href="#" class="quick-reply-btn">' + _('Quick Reply') + '</a>')
      .click(function(e) {
        e.preventDefault();
        show_quick_reply();
        $(this).remove();
      }).appendTo($('body'));

    $(window).on('quick-reply', function() {
      $('.quick-reply-btn').remove();
    });
  };

  if (settings.get('floating_link', false)) {
    $(window).ready(function() {
      if ($('div.banner').length === 0) return;

      floating_link();

      if (settings.get('hide_at_top', true)) {
        $('.quick-reply-btn').hide();
        $(window).scroll(function() {
          if ($(this).width() <= 400) return;
          if ($(this).scrollTop() < $('form[name="post"]:first').offset().top + $('form[name="post"]:first').height() - 100) {
            $('.quick-reply-btn').fadeOut(100);
          } else {
            $('.quick-reply-btn').fadeIn(100);
          }
        }).scroll();
      }
    });
  }

  $(document).on('click.quickReplyLink', '#link-quick-reply', function(e) {
    if ($(window).width() <= 400) {
      return;
    }

    e.preventDefault();
    var $postForm = show_quick_reply();
    var $origPostForm = $('form[name="post"]:first');

    if ($postForm && $postForm.length) {
      activate_quick_reply_body($origPostForm, $postForm);
      $postForm.stop(true, true).fadeIn(100);
      $postForm.find('textarea[name="body"]').trigger('focus');
    }
  });

  $(window).ready(function() {
    if ($(window).width() <= 400) return;
    if ($('div.banner').length === 0) return;

    show_quick_reply();
  });
})();
