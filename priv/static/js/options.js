/*
 * options.js - allow users choose board options as they wish
 *
 * Copyright (c) 2014 Marcin Łabanowski <marcin@6irc.net>
 *
 * Usage:
 *   $config['additional_javascript'][] = 'js/jquery.min.js';
 *   $config['additional_javascript'][] = 'js/options.js';
 */

+function(){

var options_button, admin_button, watcher_button, options_links, options_handler, options_background, options_div
  , options_close, options_tablist, options_tabs, options_current_tab, options_exit;

var Options = {};
window.Options = Options;

var first_tab = function() {
  for (var i in options_tabs) {
    return i;
  }
  return false;
};

Options.show = function() {
  if (!options_current_tab) {
    Options.select_tab(first_tab(), true);
  }
  options_handler.fadeIn();
};
Options.hide = function() {
  options_handler.fadeOut();
};

options_tabs = {};

Options.add_tab = function(id, icon, name, content) {
  var tab = {};

  if (typeof content == "string") {
    content = $("<div>"+content+"</div>");
  }

  tab.id = id;
  tab.name = name;
  tab.icon = $("<div class='options_tab_icon'><i class='fa fa-"+icon+"'></i><div>"+name+"</div></div>");
  tab.content = $("<div class='options_tab'></div>").css("display", "none");

  tab.content.appendTo(options_div);

  tab.icon.on("click", function() {
    Options.select_tab(id);
  }).appendTo(options_tablist);

  if (options_exit) {
    options_exit.detach().appendTo(options_tablist);
  }

  $("<h2>"+name+"</h2>").appendTo(tab.content);

  if (content) {
    content.appendTo(tab.content);
  }
  
  options_tabs[id] = tab;

  return tab;
};

Options.get_tab = function(id) {
  return options_tabs[id];
};

Options.extend_tab = function(id, content) {
  if (typeof content == "string") {
    content = $("<div>"+content+"</div>");
  }

  content.appendTo(options_tabs[id].content);

  return options_tabs[id];
};

Options.select_tab = function(id, quick) {
  if (options_current_tab) {
    if (options_current_tab.id == id) {
      return false;
    }
    options_current_tab.content.fadeOut();
    options_current_tab.icon.removeClass("active");
  }
  var tab = options_tabs[id];
  options_current_tab = tab;
  options_current_tab.icon.addClass("active");
  tab.content[quick? "show" : "fadeIn"]();

  return tab;
};

options_handler = $("<div id='options_handler'></div>").css("display", "none");
options_background = $("<div id='options_background'></div>").on("click", Options.hide).appendTo(options_handler);
options_div = $("<div id='options_div'></div>").appendTo(options_handler);
options_close = $("<a id='options_close' href='javascript:void(0)'><i class='fa fa-times'></i></div>")
  .on("click", Options.hide).appendTo(options_div);
options_tablist = $("<div id='options_tablist'></div>").appendTo(options_div);
options_exit = $("<div class='options_tab_icon options_exit_tab'><div>"+_("Exit")+"</div></div>")
  .on("click", Options.hide)
  .appendTo(options_tablist);


$(function(){
  var mobileClient = document.body && document.body.dataset && document.body.dataset.mobileClient === 'true';
  options_links = $("#admin_options_links");
  if (!options_links.length) {
    options_links = $("<span id='admin_options_links'></span>").css({"float": "right"});
  }
  options_button = $("#options-link");
  if (!options_button.length) {
    options_button = $("<a id='options-link' href='javascript:void(0)' title='"+_("Options")+"'>["+_("Options")+"]</a>");
  }
  admin_button = $("#admin-link");
  if (!admin_button.length) {
    admin_button = $("<a id='admin-link' href='/manage' title='"+_("Admin")+"'>["+_("Admin")+"]</a>");
  }
  var watcherCount = parseInt(document.body && document.body.dataset ? document.body.dataset.watcherCount : '0', 10);
  if (isNaN(watcherCount)) watcherCount = 0;
  var watcherYouCount = parseInt(document.body && document.body.dataset ? document.body.dataset.watcherYouCount : '0', 10);
  if (isNaN(watcherYouCount)) watcherYouCount = 0;
  watcher_button = $("#watcher-link");
  if (!mobileClient && !watcher_button.length) {
    watcher_button = $("<a id='watcher-link' href='javascript:void(0)' title='"+_("Watcher")+"' aria-label='"+_("Watcher")+"'>👁</a>");
  }
  if (watcher_button.length) {
    watcher_button.toggleClass('replies-quoting-you', watcherYouCount > 0);
  }

  if (!options_links.closest('.boardlist').length) {
    options_links.prependTo($(document.body));
  }

  options_button.on("click", Options.show);

  options_handler.appendTo($(document.body));
});



}();
