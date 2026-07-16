(function (window, document) {
  "use strict";

  var $ = window.jQuery;
  if (!$) return;

  var tabs = {};
  var currentTab = null;
  var handler;
  var panel;
  var tabList;
  var exitTab;

  function translate(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function safeIdentifier(value) {
    var identifier = String(value || "");
    return /^[A-Za-z0-9_-]+$/.test(identifier) ? identifier : null;
  }

  function iconElement(icon) {
    var normalized = safeIdentifier(icon);
    if (!normalized) return null;
    return $(document.createElement("i")).addClass("fa fa-" + normalized);
  }

  function appendContent(target, content) {
    if (!content) return;

    if (content.jquery) {
      content.appendTo(target);
    } else if (content.nodeType) {
      target.append(content);
    } else if (typeof content === "string") {
      $(document.createElement("div")).text(content).appendTo(target);
    }
  }

  function createButton(id, label) {
    return $(document.createElement("button"))
      .attr({id: id, type: "button", "aria-label": label})
      .addClass("js-link-button")
      .text(label);
  }

  function ensureShell() {
    handler = $("#options_handler");

    if (!handler.length) {
      handler = $(document.createElement("div")).attr("id", "options_handler").hide();
      $(document.createElement("div")).attr("id", "options_background").appendTo(handler);
      panel = $(document.createElement("div")).attr("id", "options_div").appendTo(handler);
      createButton("options_close", "×").appendTo(panel);
      tabList = $(document.createElement("div")).attr("id", "options_tablist").appendTo(panel);
      exitTab = $(document.createElement("div"))
        .attr("id", "options-exit-tab")
        .addClass("options_tab_icon options_exit_tab")
        .append($(document.createElement("div")).text(translate("Exit")))
        .appendTo(tabList);
    } else {
      panel = $("#options_div", handler);
      tabList = $("#options_tablist", handler);
      exitTab = $("#options-exit-tab", handler);
    }

    $("#options_background", handler).off("click.options").on("click.options", Options.hide);
    $("#options_close", handler).off("click.options").on("click.options", function (event) {
      event.preventDefault();
      Options.hide();
    });
    exitTab.off("click.options").on("click.options", function (event) {
      event.preventDefault();
      Options.hide();
    });
  }

  var Options = {};
  window.Options = Options;

  Options.show = function () {
    if (!currentTab) {
      var firstId = Object.keys(tabs)[0];
      if (firstId) Options.select_tab(firstId, true);
    }
    handler.fadeIn();
  };

  Options.hide = function () {
    handler.fadeOut();
  };

  Options.add_tab = function (id, icon, name, content) {
    var normalizedId = safeIdentifier(id);
    if (!normalizedId) throw new Error("invalid options tab id");

    var tab = {id: normalizedId, name: String(name || normalizedId)};
    var iconSelector = "#options-tab-icon-" + normalizedId;
    var contentSelector = "#options-tab-" + normalizedId;

    tab.icon = $(iconSelector);
    tab.content = $(contentSelector);

    if (!tab.icon.length) {
      tab.icon = $(document.createElement("div"))
        .attr("id", "options-tab-icon-" + normalizedId)
        .addClass("options_tab_icon");
      var iconNode = iconElement(icon);
      if (iconNode) tab.icon.append(iconNode);
      tab.icon.append($(document.createElement("div")).text(tab.name));
      tab.icon.appendTo(tabList);
    }

    if (!tab.content.length) {
      tab.content = $(document.createElement("div"))
        .attr("id", "options-tab-" + normalizedId)
        .addClass("options_tab")
        .hide();
      $(document.createElement("h2")).text(tab.name).appendTo(tab.content);
      tab.content.appendTo(panel);
    } else {
      if (!tab.content.children("h2").length) {
        $(document.createElement("h2")).text(tab.name).prependTo(tab.content);
      }
      if (!tab.icon.find("i").length) {
        var existingIcon = iconElement(icon);
        if (existingIcon) tab.icon.prepend(existingIcon);
      }
      if (!tab.icon.find("div").length) {
        tab.icon.append($(document.createElement("div")).text(tab.name));
      }
    }

    tab.icon.off("click.optionsTab").on("click.optionsTab", function () {
      Options.select_tab(normalizedId);
    });

    if (exitTab && exitTab.length) exitTab.detach().appendTo(tabList);
    appendContent(tab.content, content);
    tabs[normalizedId] = tab;
    return tab;
  };

  Options.get_tab = function (id) {
    return tabs[id];
  };

  Options.extend_tab = function (id, content) {
    var tab = tabs[id];
    if (!tab) return null;
    appendContent(tab.content, content);
    return tab;
  };

  Options.select_tab = function (id, immediate) {
    var nextTab = tabs[id];
    if (!nextTab) return false;
    if (currentTab && currentTab.id === nextTab.id) return false;

    if (currentTab) {
      currentTab.content.stop(true, true).fadeOut();
      currentTab.icon.removeClass("active");
    }

    currentTab = nextTab;
    currentTab.icon.addClass("active");
    currentTab.content.stop(true, true)[immediate ? "show" : "fadeIn"]();
    return currentTab;
  };

  ensureShell();

  $(function () {
    var mobile = document.body && document.body.dataset.mobileClient === "true";
    var adminOptions = $("#admin_options_links");
    var optionsLink = $("#options-link");
    var watcherLink = $("#watcher-link");

    if (!adminOptions.length) {
      adminOptions = $(document.createElement("span"))
        .attr("id", "admin_options_links")
        .css("float", "right");
    }

    if (!optionsLink.length) {
      optionsLink = $(document.createElement("a"))
        .attr({id: "options-link", href: "#", title: translate("Options")})
        .text("[" + translate("Options") + "]");
      adminOptions.append(optionsLink);
    }

    if (!$("#admin-link").length) {
      $(document.createElement("a"))
        .attr({id: "admin-link", href: "/manage", title: translate("Admin")})
        .text("[" + translate("Admin") + "]")
        .prependTo(adminOptions);
    }

    if (!mobile && !watcherLink.length) {
      watcherLink = createButton("watcher-link", translate("Watcher")).text("👁");
      adminOptions.prepend(watcherLink);
    }

    var youCount = Number.parseInt(document.body && document.body.dataset.watcherYouCount, 10) || 0;
    watcherLink.toggleClass("replies-quoting-you", youCount > 0);

    if (!adminOptions.closest(".boardlist").length) adminOptions.prependTo(document.body);
    optionsLink.off("click.options").on("click.options", function (event) {
      event.preventDefault();
      Options.show();
    });
    if (!handler.parent().length) handler.appendTo(document.body);
  });
})(window, document);
