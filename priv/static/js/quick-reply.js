/*
 * quick-reply.js
 *
 * Server-rendered quick reply form. JS owns lifecycle only.
 */

(function() {
  var settings = new script_settings('quick-reply');

  var do_css = function() {
    $('#quick-reply-css').remove();

    var dummy_reply = $('<div class="post reply"></div>').appendTo($('body'));
    var reply_background = dummy_reply.css('backgroundColor');
    var reply_border_style = dummy_reply.css('borderStyle');
    var reply_border_color = dummy_reply.css('borderColor');
    var reply_border_width = dummy_reply.css('borderWidth');
    dummy_reply.remove();

    $('<style type="text/css" id="quick-reply-css">\
      #quick-reply {\
        position: fixed;\
        right: 5%;\
        top: 5%;\
        float: right;\
        display: block;\
        padding: 0;\
        width: 300px;\
        z-index: 100;\
      }\
      #quick-reply table {\
        border-collapse: collapse;\
        background: ' + reply_background + ';\
        border-style: ' + reply_border_style + ';\
        border-width: ' + reply_border_width + ';\
        border-color: ' + reply_border_color + ';\
        margin: 0;\
        width: 100%;\
      }\
      #quick-reply th, #quick-reply td {\
        margin: 0;\
        padding: 0;\
      }\
      #quick-reply th {\
        text-align: center;\
        padding: 2px 0;\
        border: 1px solid #222;\
      }\
      #quick-reply th .handle {\
        float: left;\
        width: 100%;\
        display: inline-block;\
      }\
      #quick-reply th .close-btn {\
        float: right;\
        padding: 0 5px;\
      }\
      #quick-reply input[type="text"], #quick-reply select {\
        width: 100%;\
        padding: 2px;\
        font-size: 10pt;\
        box-sizing: border-box;\
        -webkit-box-sizing: border-box;\
        -moz-box-sizing: border-box;\
      }\
      #quick-reply textarea {\
        width: 100%;\
        min-width: 100%;\
        box-sizing: border-box;\
        -webkit-box-sizing: border-box;\
        -moz-box-sizing: border-box;\
        font-size: 10pt;\
        resize: vertical horizontal;\
      }\
      #quick-reply input, #quick-reply select, #quick-reply textarea {\
        margin: 0 0 1px 0;\
      }\
      #quick-reply input[type="file"] {\
        padding: 5px 2px;\
      }\
      #quick-reply td.submit, #quick-reply td.spoiler {\
        width: 1%;\
        white-space: nowrap;\
        text-align: right;\
        padding-right: 4px;\
      }\
      #quick-reply .quick-reply-spoiler {\
        margin-left: 4px;\
        white-space: nowrap;\
      }\
      @media screen and (max-width: 400px) {\
        #quick-reply {\
          display: none !important;\
        }\
      }\
    </style>').appendTo($('head'));
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

  var show_quick_reply = function() {
    if ($('div.banner').length === 0) return;
    if ($('#quick-reply').length !== 0) return;

    var template = document.getElementById('quick-reply-template');
    if (!template) return;

    do_css();

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

    $postForm.show();
    $postForm.width($postForm.find('table').width());
    $postForm.hide();

    $(window).trigger('quick-reply');

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
        do_css();
      });
    });
  };

  $(window).on('cite', function(e, id, with_link) {
    if ($(this).width() <= 400) return;

    show_quick_reply();

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

    $('<a href="javascript:void(0)" class="quick-reply-btn">' + _('Quick Reply') + '</a>')
      .click(function() {
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

      $('<style type="text/css">\
        a.quick-reply-btn {\
          position: fixed;\
          right: 0;\
          bottom: 0;\
          display: block;\
          padding: 5px 13px;\
          text-decoration: none;\
        }\
      </style>').appendTo($('head'));

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
})();
