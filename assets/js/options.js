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
  var tabIconSelector = ".options_tab_icon[id^='options-tab-icon-']";

  var allowedContentElements = {
    A: true,
    BR: true,
    BUTTON: true,
    DIV: true,
    FIELDSET: true,
    INPUT: true,
    LABEL: true,
    LEGEND: true,
    OPTION: true,
    SELECT: true,
    SMALL: true,
    SPAN: true,
    TABLE: true,
    TBODY: true,
    TD: true,
    TEXTAREA: true,
    TH: true,
    THEAD: true,
    TR: true
  };

  var globalContentAttributes = {
    "aria-label": true,
    "aria-labelledby": true,
    "aria-describedby": true,
    "aria-expanded": true,
    class: true,
    hidden: true,
    id: true,
    title: true
  };

  var elementContentAttributes = {
    A: {href: true},
    BUTTON: {disabled: true, name: true, type: true, value: true},
    INPUT: {
      autocomplete: true,
      checked: true,
      disabled: true,
      max: true,
      maxlength: true,
      min: true,
      minlength: true,
      name: true,
      placeholder: true,
      size: true,
      step: true,
      type: true,
      value: true
    },
    LABEL: {for: true},
    OPTION: {disabled: true, selected: true, value: true},
    SELECT: {disabled: true, multiple: true, name: true, size: true},
    TEXTAREA: {cols: true, maxlength: true, name: true, placeholder: true, rows: true}
  };

  var blockedContentElements = {
    BASE: true,
    EMBED: true,
    IFRAME: true,
    LINK: true,
    MATH: true,
    META: true,
    OBJECT: true,
    SCRIPT: true,
    STYLE: true,
    SVG: true
  };

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

  function safeContentHref(value) {
    var href = String(value || "").trim();
    if (!href) return false;

    try {
      var url = new URL(href, window.location.href);
      return (
        url.origin === window.location.origin &&
        (url.protocol === "http:" || url.protocol === "https:")
      );
    } catch (_error) {
      return false;
    }
  }

  function allowedContentAttribute(element, attribute) {
    var name = attribute.name.toLowerCase();

    if (name.startsWith("on") || name === "style" || name === "src" || name === "srcdoc") {
      return false;
    }

    if (globalContentAttributes[name] || name.startsWith("aria-") || name.startsWith("data-")) {
      return true;
    }

    var elementAttributes = elementContentAttributes[element.tagName] || {};
    if (!elementAttributes[name]) return false;
    if (name === "href") return safeContentHref(attribute.value);
    return true;
  }

  function optionsContentFragment(markup) {
    var template = document.createElement("template");
    template.innerHTML = String(markup || "");

    Array.prototype.slice.call(template.content.querySelectorAll("*")).forEach(function (element) {
      if (blockedContentElements[element.tagName]) {
        element.remove();
        return;
      }

      if (!allowedContentElements[element.tagName]) {
        while (element.firstChild) element.parentNode.insertBefore(element.firstChild, element);
        element.remove();
        return;
      }

      Array.prototype.slice.call(element.attributes).forEach(function (attribute) {
        if (!allowedContentAttribute(element, attribute)) element.removeAttribute(attribute.name);
      });
    });

    return template.content;
  }

  function appendContent(target, content) {
    if (!content) return;

    if (content.jquery) {
      content.appendTo(target);
    } else if (content.nodeType) {
      target.append(content);
    } else if (typeof content === "string") {
      target.append(optionsContentFragment(content));
    }
  }

  function tabIdFromIcon(icon) {
    var prefix = "options-tab-icon-";
    var id = String(icon && icon.id ? icon.id : "");
    return id.startsWith(prefix) ? id.slice(prefix.length) : null;
  }

  function selectTabFromIcon(event) {
    var id = tabIdFromIcon(event.currentTarget);
    if (id) Options.select_tab(id);
  }

  function selectTabFromKeyboard(event) {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    selectTabFromIcon(event);
  }

  function refreshTabElements(tab) {
    if (!tab) return tab;

    var liveIcon = $("#options-tab-icon-" + tab.id);
    var liveContent = $("#options-tab-" + tab.id);
    if (liveIcon.length) tab.icon = liveIcon;
    if (liveContent.length) tab.content = liveContent;
    return tab;
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

    tabList
      .off("click.optionsTabs", tabIconSelector)
      .on("click.optionsTabs", tabIconSelector, selectTabFromIcon)
      .off("keydown.optionsTabs", tabIconSelector)
      .on("keydown.optionsTabs", tabIconSelector, selectTabFromKeyboard);

    tabList.find(tabIconSelector).attr({role: "button", tabindex: "0"});
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
        .attr({role: "button", tabindex: "0"})
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

    tab.icon.attr({role: "button", tabindex: "0"});

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
    var nextTab = refreshTabElements(tabs[id]);
    if (!nextTab) return false;
    currentTab = refreshTabElements(currentTab);
    if (currentTab && currentTab.id === nextTab.id) {
      currentTab.icon.addClass("active");
      return false;
    }

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
