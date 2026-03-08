/*
 * upload-selection.js - makes upload fields in post form more compact
 * https://github.com/vichan-devel/Tinyboard/blob/master/js/upload-selection.js
 *
 * Released under the MIT license
 * Copyright (c) 2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   //$config['additional_javascript'][] = 'js/wpaint.js';
 *   $config['additional_javascript'][] = 'js/upload-selection.js';
 *                                                  
 */

$(function(){
  var enabled_url = $("#upload_url").length > 0;
  var enabled_embed = $("#upload_embed").length > 0;
  var enabled_oekaki = typeof window.oekaki != "undefined";

  var disable_all = function() {
    $("#upload").hide();
    $("[id^=upload_file]").hide();
    $(".file_separator").hide();
    $("#upload_url").hide();
    $("#upload_embed").hide();
    $(".add_image").hide();
    $(".dropzone-wrap").hide();

    if (enabled_oekaki) {
      if (window.oekaki.initialized) {
        window.oekaki.deinit();
      }
    }
  };

  enable_file = function() {
    disable_all();
    $("#upload").show();
    $(".dropzone-wrap").show();
    $(".file_separator").show();
    $("[id^=upload_file]").show();
    $(".add_image").show();
    if (enabled_embed) {
      $("#upload_embed").show();
    }
  };

  enable_url = function() {
    disable_all();
    $("#upload").show();
    $("#upload_url").show();

    $('label[for="file_url"]').html(_("URL"));
  };

  enable_embed = function() {
    enable_file();
    $("#upload_embed").show();
    $("#upload_embed").find('input[name=\"embed\"]').focus();
  };

  enable_oekaki = function() {
    disable_all();

    window.oekaki.init();
  };

  if (enabled_oekaki) {
    $("#confirm_oekaki_label").hide();
  }

  if (enabled_url || enabled_embed || enabled_oekaki) {
    enable_file();
  }
});
