$(function () {
  var embedEnabled = $("#upload_embed").length > 0;
  var hasOekaki = window.oekaki !== undefined;

  function hideAllUploadModes() {
    $("#upload").hide();
    $(".file_separator").hide();
    $("#upload_url").hide();
    $("#upload_embed").hide();
    $(".add_image").hide();
    $(".dropzone-wrap").hide();

    if (hasOekaki && window.oekaki.initialized) {
      window.oekaki.deinit();
    }
  }

  window.enable_file = function () {
    hideAllUploadModes();
    $("#upload").show();
    $(".file_separator").show();
    $(".add_image").show();
    $(".dropzone-wrap").show();

    if (embedEnabled) {
      $("#upload_embed").show();
    }
  };

  window.enable_url = function () {
    hideAllUploadModes();
    $("#upload").show();
    $("#upload_url").show();
    $('label[for="file_url"]').html(_("URL"));
  };

  window.enable_embed = function () {
    window.enable_file();
    $("#upload_embed").show();
    $("#upload_embed").find('input[name="embed"]').focus();
  };

  window.enable_oekaki = function () {
    hideAllUploadModes();
    window.oekaki.init();
  };

  if (hasOekaki) {
    $("#confirm_oekaki_label").hide();
  }
});
