$(function () {
  var embedEnabled = $("#upload_embed").length > 0;
  var hasOekaki = window.oekaki !== undefined;
  var nativeSelector = "[data-native-upload]";
  var enhancedFormSelector = 'form[data-file-selector-enhanced="true"]';

  function syncFileSelectorVisibility(scope) {
    var $scope = scope ? $(scope) : $(document);

    $scope.find(nativeSelector).show();

    $scope.find(".dropzone-wrap").each(function () {
      var $shell = $(this);
      var enhanced = $shell.closest(enhancedFormSelector).length > 0;
      $shell.toggle(enhanced);
      $shell.attr("hidden", !enhanced);
    });
  }

  function hideAllUploadModes() {
    $("#upload").hide();
    $(nativeSelector).hide();
    $(".file_separator").hide();
    $("#upload_url").hide();
    $("#upload_embed").hide();
    $(".add_image").hide();
    $(".dropzone-wrap").hide();

    if (hasOekaki && window.oekaki.initialized) {
      window.oekaki.deinit();
    }
  }

  window.syncFileSelectorVisibility = syncFileSelectorVisibility;

  window.enable_file = function () {
    hideAllUploadModes();
    $("#upload").show();
    $(".file_separator").show();
    $(".add_image").show();
    syncFileSelectorVisibility(document);

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
