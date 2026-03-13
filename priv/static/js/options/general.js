/*
 * options/general.js - general settings tab for options panel
 *
 * Copyright (c) 2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/options.js';
 *   $config['additional_javascript'][] = 'js/style-select.js';
 *   $config['additional_javascript'][] = 'js/options/general.js';
 */

+function(){

var tab = Options.add_tab("general", "home", _("General"));

$(function(){
  var prefBox = $("#general-preferences");
  if (!prefBox.length) {
    prefBox = $("<div id='general-preferences'></div>").appendTo(tab.content);
  }

  var stor = $("#options-storage-controls");
  if (!stor.length) {
    stor = $("<div id='options-storage-controls'><span>"+_("Storage: ")+"</span></div>").appendTo(tab.content);
    $("<button id='options-storage-export' type='button'>"+_("Export")+"</button>").appendTo(stor);
    $("<button id='options-storage-import' type='button'>"+_("Import")+"</button>").appendTo(stor);
    $("<button id='options-storage-erase' type='button'>"+_("Erase")+"</button>").appendTo(stor);
    $("<input type='text' id='options-storage-output' class='output' hidden>").appendTo(stor);
  }

  $("#options-storage-export").off("click.optionsGeneral").on("click.optionsGeneral", function() {
    var str = JSON.stringify(localStorage);
    var output = $("#options-storage-output");
    output.val(str).prop("hidden", false);
  });

  $("#options-storage-import").off("click.optionsGeneral").on("click.optionsGeneral", function() {
    var str = prompt(_("Paste your storage data"));
    if (!str) return false;
    var obj = JSON.parse(str);
    if (!obj) return false;

    localStorage.clear();
    for (var i in obj) {
      localStorage[i] = obj[i];
    }

    document.location.reload();
  });

  $("#options-storage-erase").off("click.optionsGeneral").on("click.optionsGeneral", function() {
    if (confirm(_("Are you sure you want to erase your storage? This involves your hidden threads, watched threads, post password and many more."))) {
      localStorage.clear();
      document.cookie = "theme=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT";
      document.cookie = "board_themes=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT";
      document.location.reload();
    }
  });

  $("#style-select").css({display:"block",float:"none","margin-bottom":0}).appendTo(prefBox);
  $(document).trigger("general_preferences_ready");
});

}();
