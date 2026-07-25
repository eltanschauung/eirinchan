(function (window, document) {
  "use strict";

  var $ = window.jQuery;
  var supportedPages = {thread: true, index: true, catalog: true, ukko: true};
  if (!$ || !supportedPages[window.active_page]) return;

  var storageKey = "postFilter";
  var filterTypes = {name: true, trip: true, sub: true, com: true, flag: true};
  var filterLabels = {
    name: "name",
    trip: "tripcode",
    sub: "subject",
    com: "comment",
    flag: "flag"
  };
  var reasonKeys = {
    name: "hiddenByName",
    trip: "hiddenByTrip",
    sub: "hiddenBySubject",
    com: "hiddenByComment",
    flag: "hiddenByFlag"
  };
  var stateRepairNotice = false;
  var memoryState = defaultState();
  var initialized = false;
  var eventsBound = false;
  var optionsInitialized = false;
  var runtime = {
    boardId: String(window.board_name || ""),
    forcedAnon: false,
    hasUID: false
  };

  function translate(value) {
    return typeof window._ === "function" ? window._(value) : value;
  }

  function now() {
    return Math.floor(Date.now() / 1000);
  }

  function defaultState() {
    return {
      generalFilter: [],
      postFilter: {},
      nextPurge: {},
      lastPurge: now()
    };
  }

  function plainObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
  }

  function ownKeys(value) {
    return plainObject(value) ? Object.keys(value) : [];
  }

  function validRegex(value) {
    try {
      return new RegExp(value);
    } catch (_error) {
      return null;
    }
  }

  function normalizedRule(rule) {
    if (!plainObject(rule) || !filterTypes[rule.type] || typeof rule.value !== "string") {
      return null;
    }

    var value = rule.value.trim();
    if (!value) return null;
    var regex = rule.regex === true;
    if (regex && !validRegex(value)) return null;
    return {type: rule.type, value: value, regex: regex};
  }

  function normalizedPostEntry(entry) {
    if (!plainObject(entry)) return null;

    var normalized = {hideReplies: entry.hideReplies === true};
    if (entry.post !== undefined && entry.post !== null && String(entry.post) !== "") {
      normalized.post = String(entry.post);
    }
    if (entry.uid !== undefined && entry.uid !== null && String(entry.uid) !== "") {
      normalized.uid = String(entry.uid);
    }

    return normalized.post !== undefined || normalized.uid !== undefined ? normalized : null;
  }

  function normalizePostFilters(value) {
    var result = {};

    ownKeys(value).forEach(function (board) {
      var threads = value[board];
      var normalizedThreads = {};

      ownKeys(threads).forEach(function (thread) {
        if (!Array.isArray(threads[thread])) return;
        var entries = threads[thread].map(normalizedPostEntry).filter(Boolean);
        if (entries.length) normalizedThreads[String(thread)] = entries;
      });

      if (Object.keys(normalizedThreads).length) result[String(board)] = normalizedThreads;
    });

    return result;
  }

  function normalizePurgeState(value, postFilters) {
    var result = {};

    ownKeys(postFilters).forEach(function (board) {
      var boardPurge = plainObject(value && value[board]) ? value[board] : {};
      var normalizedThreads = {};

      ownKeys(postFilters[board]).forEach(function (thread) {
        var purge = plainObject(boardPurge[thread]) ? boardPurge[thread] : {};
        var timestamp = Number(purge.timestamp);
        var interval = Number(purge.interval);
        normalizedThreads[thread] = {
          timestamp: isFinite(timestamp) && timestamp > 0 ? Math.floor(timestamp) : now(),
          interval: isFinite(interval) && interval > 0 ? Math.floor(interval) : 86400
        };
      });

      if (Object.keys(normalizedThreads).length) result[board] = normalizedThreads;
    });

    return result;
  }

  function normalizeState(value) {
    var input = plainObject(value) ? value : {};
    var general = Array.isArray(input.generalFilter)
      ? input.generalFilter.map(normalizedRule).filter(Boolean)
      : [];
    var postFilters = normalizePostFilters(input.postFilter);
    var lastPurge = Number(input.lastPurge);

    return {
      generalFilter: general,
      postFilter: postFilters,
      nextPurge: normalizePurgeState(input.nextPurge, postFilters),
      lastPurge: isFinite(lastPurge) && lastPurge > 0 ? Math.floor(lastPurge) : now()
    };
  }

  function statesEqual(left, right) {
    try {
      return JSON.stringify(left) === JSON.stringify(right);
    } catch (_error) {
      return false;
    }
  }

  function storeState(state) {
    memoryState = normalizeState(state);

    try {
      window.localStorage.setItem(storageKey, JSON.stringify(memoryState));
    } catch (_error) {}

    return memoryState;
  }

  function readState() {
    var parsed = null;
    var raw = null;

    try {
      raw = window.localStorage.getItem(storageKey);
      parsed = raw === null ? null : JSON.parse(raw);
    } catch (_error) {
      stateRepairNotice = true;
      return memoryState;
    }

    var normalized = normalizeState(parsed);
    if (raw === null || !statesEqual(parsed, normalized)) {
      stateRepairNotice = raw !== null;
      storeState(normalized);
    } else {
      memoryState = normalized;
    }

    return memoryState;
  }

  function writeState(state) {
    storeState(state);
    $(document).trigger("filter_page");
  }

  function ensureThreadState(state, board, thread) {
    board = String(board || "");
    thread = String(thread || "");
    if (!state.postFilter[board]) state.postFilter[board] = {};
    if (!state.nextPurge[board]) state.nextPurge[board] = {};
    if (!state.postFilter[board][thread]) state.postFilter[board][thread] = [];
    state.nextPurge[board][thread] = {timestamp: now(), interval: 86400};
    return state.postFilter[board][thread];
  }

  function removeEmptyThreadState(state, board, thread) {
    if (!state.postFilter[board] || !state.postFilter[board][thread]) return;
    if (state.postFilter[board][thread].length) return;

    delete state.postFilter[board][thread];
    if (state.nextPurge[board]) delete state.nextPurge[board][thread];

    if (!Object.keys(state.postFilter[board]).length) {
      delete state.postFilter[board];
      delete state.nextPurge[board];
    }
  }

  function addPostFilter(board, thread, field, value, hideReplies) {
    var state = readState();
    var entries = ensureThreadState(state, board, thread);
    var stringValue = String(value);
    var duplicate = entries.some(function (entry) {
      return String(entry[field]) === stringValue;
    });

    if (!duplicate) {
      var entry = {hideReplies: hideReplies === true};
      entry[field] = stringValue;
      entries.push(entry);
      writeState(state);
    }
  }

  function removePostFilter(board, thread, field, value) {
    var state = readState();
    board = String(board || "");
    thread = String(thread || "");
    var entries = state.postFilter[board] && state.postFilter[board][thread];
    if (!entries) return;

    var stringValue = String(value);
    state.postFilter[board][thread] = entries.filter(function (entry) {
      return String(entry[field]) !== stringValue;
    });
    removeEmptyThreadState(state, board, thread);
    writeState(state);
  }

  function sameGeneralRule(left, right) {
    return (
      left.type === right.type &&
      left.value === right.value &&
      left.regex === right.regex
    );
  }

  function addGeneralFilter(type, value, useRegex) {
    var candidateValue = typeof value === "string" ? value.trim() : "";
    if (useRegex === true && candidateValue && !validRegex(candidateValue)) {
      return {ok: false, error: translate("Enter a valid regular expression.")};
    }

    var rule = normalizedRule({type: type, value: value, regex: useRegex === true});
    if (!rule) return {ok: false, error: translate("Enter a valid filter value.")};

    var state = readState();
    if (state.generalFilter.some(function (current) { return sameGeneralRule(current, rule); })) {
      return {ok: true, duplicate: true};
    }

    state.generalFilter.push(rule);
    writeState(state);
    renderFilterList();
    return {ok: true};
  }

  function removeGeneralFilter(type, value, useRegex) {
    var target = {type: type, value: value, regex: useRegex === true};
    var state = readState();
    state.generalFilter = state.generalFilter.filter(function (rule) {
      return !sameGeneralRule(rule, target);
    });
    writeState(state);
    renderFilterList();
  }

  function clearAll() {
    writeState(defaultState());
    $(document).trigger("clear_hidden_threads");
    renderFilterList();
  }

  function extractName(element) {
    var value = "";

    $(element)
      .contents()
      .each(function () {
        if (this.nodeName === "IMG") value += $(this).attr("alt") || "";
        if (this.nodeName === "#text") value += this.nodeValue || "";
      });

    return value.trim();
  }

  function textValue(node) {
    return node && node.length ? node.first().text().trim() : "";
  }

  function flagValues(scope) {
    var values = [];

    scope.find(".flag").each(function () {
      var flag = $(this);
      [flag.attr("data-flag-code"), flag.attr("title"), flag.attr("alt")].forEach(function (value) {
        var normalized = String(value || "").trim();
        if (normalized && values.indexOf(normalized) === -1) values.push(normalized);
      });
    });

    return values;
  }

  function flagEntries(scope) {
    var result = [];

    scope.find(".flag").each(function () {
      var flag = $(this);
      var code = String(flag.attr("data-flag-code") || "").trim();
      var label = String(flag.attr("title") || flag.attr("alt") || code).trim();
      var value = label || code;
      if (!value) return;

      if (!result.some(function (entry) { return entry.value === value; })) {
        result.push({code: code, label: label || code, value: value});
      }
    });

    return result;
  }

  function wordCharacter(character) {
    if (!character) return false;
    try {
      return /[\p{L}\p{N}_]/u.test(character);
    } catch (_error) {
      return /[A-Za-z0-9_]/.test(character);
    }
  }

  function literalTextMatch(text, value) {
    if (!value) return false;
    var offset = 0;

    while (offset <= text.length) {
      var index = text.indexOf(value, offset);
      if (index === -1) return false;

      var before = index > 0 ? text.charAt(index - 1) : "";
      var afterIndex = index + value.length;
      var after = afterIndex < text.length ? text.charAt(afterIndex) : "";
      var startIsWord = wordCharacter(value.charAt(0));
      var endIsWord = wordCharacter(value.charAt(value.length - 1));
      var startBoundary = !startIsWord || !wordCharacter(before);
      var endBoundary = !endIsWord || !wordCharacter(after);

      if (startBoundary && endBoundary) return true;
      offset = index + Math.max(value.length, 1);
    }

    return false;
  }

  function generalRuleMatches(rule, values) {
    if (rule.regex) {
      var expression = validRegex(rule.value);
      return !!expression && values.some(function (value) { return expression.test(value); });
    }

    if (rule.type === "name" || rule.type === "trip") {
      return values.some(function (value) { return value === rule.value; });
    }

    if (rule.type === "flag") {
      var expected = rule.value.toLocaleLowerCase();
      return values.some(function (value) {
        return value.toLocaleLowerCase() === expected;
      });
    }

    return values.some(function (value) {
      return literalTextMatch(value, rule.value);
    });
  }

  function postId(scope) {
    if (scope.hasClass("mix")) return String(scope.attr("data-id") || "");
    return scope.find(".post_no").not("[id]").first().text().trim();
  }

  function boardId(scope) {
    return String(
      scope.attr("data-board") ||
        scope.closest(".thread").attr("data-board") ||
        runtime.boardId ||
        ""
    );
  }

  function threadId(scope) {
    if (scope.hasClass("mix")) return String(scope.attr("data-id") || "");
    return String((scope.closest(".thread").attr("id") || "").replace(/^thread_/, ""));
  }

  function threadEntries(state, board, thread) {
    return (state.postFilter[board] && state.postFilter[board][thread]) || [];
  }

  function resetReasons(scope) {
    [
      "hidden",
      "hiddenByUid",
      "hiddenByPost",
      "hiddenByName",
      "hiddenByTrip",
      "hiddenBySubject",
      "hiddenByComment",
      "hiddenByFlag",
      "hiddenByReply"
    ].forEach(function (key) {
      scope.data(key, false);
    });
  }

  function evaluateRecord(element, state) {
    var scope = $(element);
    var board = boardId(scope);
    var thread = threadId(scope);
    var id = postId(scope);
    var record = {
      element: element,
      scope: scope,
      board: board,
      thread: thread,
      post: id,
      hidden: false,
      hideReplies: false
    };

    resetReasons(scope);

    threadEntries(state, board, thread).forEach(function (entry) {
      if (entry.post !== undefined && String(entry.post) === id) {
        scope.data("hiddenByPost", true);
        record.hidden = true;
        record.hideReplies = record.hideReplies || entry.hideReplies === true;
      }

      if (
        entry.uid !== undefined &&
        runtime.hasUID &&
        scope.find(".poster_id").first().text() === String(entry.uid)
      ) {
        scope.data("hiddenByUid", true);
        record.hidden = true;
        record.hideReplies = record.hideReplies || entry.hideReplies === true;
      }
    });

    var values = {
      name: runtime.forcedAnon
        ? []
        : [extractName(scope.find(".name").first()[0])],
      trip: runtime.forcedAnon ? [] : [textValue(scope.find(".trip"))],
      sub: [textValue(scope.find(".subject"))],
      com: [textValue(scope.find(".body"))],
      flag: flagValues(scope)
    };

    state.generalFilter.forEach(function (rule) {
      var candidates = values[rule.type].filter(function (value) { return value !== ""; });
      if (generalRuleMatches(rule, candidates)) {
        scope.data(reasonKeys[rule.type], true);
        record.hidden = true;
      }
    });

    return record;
  }

  function quotesHiddenPost(scope, hiddenReplyIds) {
    var found = false;

    scope.find(".body a").not('[rel="nofollow"]').each(function () {
      var match = $(this).text().match(/^>>(\d+)$/);
      if (match && hiddenReplyIds.indexOf(match[1]) !== -1) found = true;
    });

    return found;
  }

  function setPostVisibility(record) {
    var scope = record.scope;
    var hidden = record.hidden === true;
    scope.data("hidden", hidden);
    scope.toggleClass("post-filter-hidden", hidden);

    if (scope.hasClass("mix")) return;

    if (scope.hasClass("op")) {
      var thread = scope.closest(".thread");
      thread.toggleClass("thread-filter-hidden", hidden);
      thread.toggleClass(
        "post-filter-collapse-thread",
        hidden && (window.active_page === "index" || window.active_page === "ukko")
      );

      var hideLink = scope.find("p.intro .hide-thread-link").first();
      if (hideLink.length) hideLink.html("[" + (hidden ? "+" : "&ndash;") + "]");
    }
  }

  function pageElements() {
    if (window.active_page === "catalog") return $(".mix").toArray();

    var result = [];
    $(".thread").each(function () {
      var op = $(this).children(".op")[0];
      if (op) result.push(op);
      $(this).find(".reply").not(".hidden").each(function () { result.push(this); });
    });
    return result;
  }

  function applyPage() {
    var state = readState();
    var records = pageElements().map(function (element) {
      return evaluateRecord(element, state);
    });
    var hiddenReplyIds = records
      .filter(function (record) { return record.hidden && record.hideReplies; })
      .map(function (record) { return record.post; });

    records.forEach(function (record) {
      if (quotesHiddenPost(record.scope, hiddenReplyIds)) {
        record.scope.data("hiddenByReply", true);
        record.hidden = true;
      }
      setPostVisibility(record);
    });
  }

  function installStyles() {
    if (document.getElementById("post-filter-styles")) return;
    var style = document.createElement("style");
    style.id = "post-filter-styles";
    style.textContent =
      "#filter-control{display:flex;align-items:center;gap:4px;flex-wrap:wrap}" +
      "#filter-control input[type=text]{width:130px}" +
      "#filter-control input[type=checkbox]{vertical-align:middle}" +
      "#filter-control #clear{margin-left:auto}" +
      "#filter-confirm,#filter-status{text-align:right;padding-top:4px;font-size:14px}" +
      "#filter-confirm,#filter-status.filter-error{color:#c00}" +
      "#filter-container{margin-top:12px;border:1px solid;height:270px;overflow:auto}" +
      "#filter-list{width:100%;border-collapse:collapse}" +
      "#filter-list th{text-align:center;height:20px;font-size:14px;border-bottom:1px solid}" +
      "#filter-list th:nth-child(1),#filter-list td:nth-child(1){text-align:center;width:70px}" +
      "#filter-list th:nth-child(2),#filter-list td:nth-child(2){text-align:left}" +
      "#filter-list th:nth-child(3),#filter-list td:nth-child(3){text-align:center;width:58px}" +
      "#filter-list tr:not(#filter-header){height:22px}" +
      "#filter-list tr:nth-child(even){background-color:rgba(255,255,255,.5)}" +
      ".mix.post-filter-hidden{display:none!important}" +
      ".post.post-filter-hidden>.body,.post.post-filter-hidden>.files," +
      ".post.post-filter-hidden>.video-container{display:none!important}" +
      ".thread.post-filter-collapse-thread>.omitted," +
      ".thread.post-filter-collapse-thread>.reply:not(.hidden)," +
      ".thread.post-filter-collapse-thread>br.clear{display:none!important}";
    document.head.appendChild(style);
  }

  function showStatus(message, error) {
    var status = $("#filter-status");
    if (!status.length) return;
    status.text(message || "").toggleClass("hidden", !message).toggleClass("filter-error", !!error);
  }

  function renderFilterList() {
    var list = $("#filter-list");
    if (!list.length) return;
    list.empty();

    var header = $("<tr>").attr("id", "filter-header");
    [translate("Type"), translate("Content"), translate("Remove")].forEach(function (label) {
      header.append($("<th>").text(label));
    });
    list.append(header);

    readState().generalFilter.forEach(function (rule) {
      var row = $("<tr>");
      var renderedValue = rule.regex ? "/" + rule.value + "/" : rule.value;
      var remove = $("<button>")
        .attr({type: "button", "aria-label": translate("Remove filter")})
        .addClass("del-btn js-link-button")
        .text("X")
        .data({type: rule.type, val: rule.value, useRegex: rule.regex});

      row.append($("<td>").text(filterLabels[rule.type]));
      row.append($("<td>").text(renderedValue));
      row.append($("<td>").append(remove));
      list.append(row);
    });
  }

  function filterControls() {
    var root = $("<div>");
    var control = $("<div>").attr("id", "filter-control");
    var select = $("<select>").attr("aria-label", translate("Filter type"));

    [
      ["name", translate("Name")],
      ["trip", translate("Tripcode")],
      ["sub", translate("Subject")],
      ["com", translate("Comment")],
      ["flag", translate("Flag")]
    ].forEach(function (option) {
      select.append($("<option>").attr("value", option[0]).text(option[1]));
    });

    var value = $("<input>").attr({
      type: "text",
      "aria-label": translate("Filter value"),
      autocomplete: "off"
    });
    var regex = $("<input>").attr({type: "checkbox", id: "filter-use-regex"});
    var regexLabel = $("<label>").attr("for", "filter-use-regex").append(regex, " regex");
    var add = $("<button>").attr({id: "set-filter", type: "button"}).text(translate("Add"));
    var clear = $("<button>")
      .attr({id: "clear", type: "button"})
      .text(translate("Clear all filters"));

    control.append(select, value, regexLabel, add, clear);

    var confirm = $("<div>").attr("id", "filter-confirm").addClass("hidden");
    confirm.append(
      document.createTextNode(
        translate("This will clear all filtering rules including hidden posts.") + " "
      ),
      $("<button>").attr({id: "confirm-y", type: "button"}).addClass("js-link-button").text(translate("yes")),
      document.createTextNode(" | "),
      $("<button>").attr({id: "confirm-n", type: "button"}).addClass("js-link-button").text(translate("no"))
    );

    root.append(
      control,
      confirm,
      $("<div>").attr({id: "filter-status", role: "status"}).addClass("hidden"),
      $("<div>").attr("id", "filter-container").append($("<table>").attr("id", "filter-list"))
    );
    return root;
  }

  function initializeOptions() {
    if (
      optionsInitialized ||
      !window.Options ||
      typeof window.Options.add_tab !== "function"
    ) {
      return;
    }
    optionsInitialized = true;

    if (!window.Options.get_tab("filter")) {
      window.Options.add_tab("filter", "list", translate("Filters"));
      window.Options.extend_tab("filter", filterControls());
    }

    renderFilterList();

    $("#filter-control").on("click.postFilter", "#set-filter", function () {
      var control = $("#filter-control");
      var result = addGeneralFilter(
        control.find("select").val(),
        control.find('input[type="text"]').val(),
        control.find('input[type="checkbox"]').prop("checked")
      );

      if (!result.ok) {
        showStatus(result.error, true);
        return;
      }

      control.find('input[type="text"]').val("");
      showStatus(result.duplicate ? translate("That filter already exists.") : "", false);
    });

    $("#filter-control").on("keydown.postFilter", 'input[type="text"]', function (event) {
      if (event.key === "Enter") {
        event.preventDefault();
        $("#set-filter").trigger("click");
      }
    });

    $("#filter-control").on("click.postFilter", "#clear", function () {
      $("#clear").addClass("hidden");
      $("#filter-confirm").removeClass("hidden");
    });

    $("#filter-confirm").on("click.postFilter", "#confirm-y", function () {
      $("#clear").removeClass("hidden");
      $("#filter-confirm").addClass("hidden");
      clearAll();
      showStatus("", false);
    });

    $("#filter-confirm").on("click.postFilter", "#confirm-n", function () {
      $("#clear").removeClass("hidden");
      $("#filter-confirm").addClass("hidden");
    });

    $("#filter-list").on("click.postFilter", ".del-btn", function () {
      var button = $(this);
      removeGeneralFilter(
        button.data("type"),
        button.data("val"),
        button.data("useRegex")
      );
    });

    if (stateRepairNotice) {
      showStatus(translate("Invalid stored filters were repaired."), false);
    }
  }

  function generalFilterExists(type, value) {
    return readState().generalFilter.some(function (rule) {
      return sameGeneralRule(rule, {type: type, value: value, regex: false});
    });
  }

  function bindMenuClick(item, callback) {
    item.removeClass("hidden").off("click.postFilter").on("click.postFilter", function (event) {
      event.preventDefault();
      event.stopPropagation();
      callback();
    });
  }

  function configureFlagMenu(menu, scope) {
    var item = menu.find("#filter-add-flag");
    var flags = flagEntries(scope);
    if (!item.length || !flags.length) {
      item.addClass("hidden");
      return;
    }

    var list = $("<ul>");
    flags.forEach(function (flag) {
      var filtered = generalFilterExists("flag", flag.value);
      var action = $("<li>")
        .addClass("post-item")
        .text((filtered ? translate("Unfilter") : translate("Filter")) + " " + flag.label);

      action.on("click.postFilter", function (event) {
        event.preventDefault();
        event.stopPropagation();
        if (filtered) removeGeneralFilter("flag", flag.value, false);
        else addGeneralFilter("flag", flag.value, false);
      });
      list.append(action);
    });

    item
      .removeClass("hidden post-item")
      .addClass("post-submenu")
      .empty()
      .append(list, $("<span>").addClass("post-menu-arrow").text("»"));
  }

  function configurePostMenu(event, menu) {
    var post = $(event.target).closest(".post");
    if (!post.length) return;

    var thread = post.closest(".thread");
    var board = boardId(post);
    var threadValue = String((thread.attr("id") || "").replace(/^thread_/, ""));
    var postValue = postId(post);
    var uid = runtime.hasUID ? post.find(".poster_id").first().text() : "";
    var name = runtime.forcedAnon ? "" : extractName(post.find(".name").first()[0]);
    var trip = runtime.forcedAnon ? "" : post.find(".trip").first().text();

    menu.find(".post-item,.post-submenu").removeClass("hidden");

    var hiddenByStoredPost = post.data("hiddenByPost") === true;
    var hiddenByUid = post.data("hiddenByUid") === true;
    var hide = menu.find("#filter-menu-hide");
    var hidePlus = menu.find("#filter-menu-hide-plus");
    var unhide = menu.find("#filter-menu-unhide");

    if (hiddenByStoredPost || hiddenByUid) {
      hide.addClass("hidden");
      hidePlus.addClass("hidden");
      bindMenuClick(unhide, function () {
        if (hiddenByStoredPost) removePostFilter(board, threadValue, "post", postValue);
        if (hiddenByUid) removePostFilter(board, threadValue, "uid", uid);
      });
    } else {
      unhide.addClass("hidden");
      bindMenuClick(hide, function () {
        if (post.hasClass("op")) {
          var hideThread = post.find("p.intro .hide-thread-link").first();
          if (hideThread.length) return hideThread.trigger("click");
        }
        addPostFilter(board, threadValue, "post", postValue, false);
      });
      bindMenuClick(hidePlus, function () {
        if (post.hasClass("op")) {
          var hideThread = post.find("p.intro .hide-thread-link").first();
          if (hideThread.length) return hideThread.trigger("click");
        }
        addPostFilter(board, threadValue, "post", postValue, true);
      });
    }

    var addId = menu.find("#filter-add-id");
    var addIdPlus = menu.find("#filter-add-id-plus");
    var removeId = menu.find("#filter-remove-id");
    if (!uid) {
      addId.addClass("hidden");
      addIdPlus.addClass("hidden");
      removeId.addClass("hidden");
    } else if (hiddenByUid) {
      addId.addClass("hidden");
      addIdPlus.addClass("hidden");
      bindMenuClick(removeId, function () {
        removePostFilter(board, threadValue, "uid", uid);
      });
    } else {
      removeId.addClass("hidden");
      bindMenuClick(addId, function () {
        addPostFilter(board, threadValue, "uid", uid, false);
      });
      bindMenuClick(addIdPlus, function () {
        addPostFilter(board, threadValue, "uid", uid, true);
      });
    }

    [
      {type: "name", value: name, add: "#filter-add-name", remove: "#filter-remove-name"},
      {type: "trip", value: trip, add: "#filter-add-trip", remove: "#filter-remove-trip"}
    ].forEach(function (entry) {
      var add = menu.find(entry.add);
      var remove = menu.find(entry.remove);
      if (!entry.value) {
        add.addClass("hidden");
        remove.addClass("hidden");
      } else if (generalFilterExists(entry.type, entry.value)) {
        add.addClass("hidden");
        bindMenuClick(remove, function () {
          removeGeneralFilter(entry.type, entry.value, false);
        });
      } else {
        remove.addClass("hidden");
        bindMenuClick(add, function () {
          addGeneralFilter(entry.type, entry.value, false);
        });
      }
    });

    configureFlagMenu(menu, post);

    ["#filter-menu-remove", "#filter-menu-add"].forEach(function (selector) {
      var submenu = menu.find(selector);
      if (!submenu.find("> ul").children().not(".hidden").length) submenu.addClass("hidden");
    });
  }

  function attachMenu(menu) {
    if (!menu || menu.__postFilterMenuInstalled) return;

    menu.add_item("filter-menu-hide", translate("Hide post"));
    menu.add_item("filter-menu-hide-plus", translate("Hide post +"), translate("Hide post and all replies"));
    menu.add_item("filter-menu-unhide", translate("Unhide post"));

    var add = menu.add_submenu("filter-menu-add", translate("Add filter"));
    add.add_item("filter-add-id", translate("ID"));
    add.add_item("filter-add-id-plus", translate("ID +"), translate("Hide ID and all replies"));
    add.add_item("filter-add-name", translate("Name"));
    add.add_item("filter-add-trip", translate("Tripcode"));
    add.add_item("filter-add-flag", translate("Flag"));

    var remove = menu.add_submenu("filter-menu-remove", translate("Remove filter"));
    remove.add_item("filter-remove-id", translate("ID"));
    remove.add_item("filter-remove-name", translate("Name"));
    remove.add_item("filter-remove-trip", translate("Tripcode"));

    menu.onclick(configurePostMenu);
    menu.__postFilterMenuInstalled = true;
  }

  function purgeStoredPosts() {
    var state = readState();
    if (now() - state.lastPurge < 86400) return;
    var requests = [];

    ownKeys(state.nextPurge).forEach(function (board) {
      ownKeys(state.nextPurge[board]).forEach(function (thread) {
        var purge = state.nextPurge[board][thread];
        if (now() <= purge.timestamp + purge.interval) return;

        requests.push(
          $.ajax({
            cache: false,
            url: "/" + encodeURIComponent(board) + "/res/" + encodeURIComponent(thread) + ".json"
          })
            .done(function () {
              var current = readState();
              if (!current.nextPurge[board] || !current.nextPurge[board][thread]) return;
              current.nextPurge[board][thread].timestamp = now();
              current.nextPurge[board][thread].interval = Math.floor(
                current.nextPurge[board][thread].interval * 1.5
              );
              storeState(current);
            })
            .fail(function (request) {
              if (request.status !== 404) return;
              var current = readState();
              if (current.postFilter[board]) delete current.postFilter[board][thread];
              if (current.nextPurge[board]) delete current.nextPurge[board][thread];
              if (current.postFilter[board] && !Object.keys(current.postFilter[board]).length) {
                delete current.postFilter[board];
                delete current.nextPurge[board];
              }
              storeState(current);
            })
        );
      });
    });

    $.when.apply($, requests).always(function () {
      var current = readState();
      current.lastPurge = now();
      storeState(current);
    });
  }

  function bindEvents() {
    if (eventsBound) return;
    eventsBound = true;
    $(document).on("filter_page.postFilter", applyPage);
    $(document).on("new_post.postFilter", applyPage);
  }

  function initialize() {
    if (initialized) return;
    initialized = true;
    runtime.hasUID = document.getElementsByClassName("poster_id").length > 0;
    runtime.forcedAnon = $("th:contains(Name)").length === 0;
    installStyles();
    readState();
    initializeOptions();
    bindEvents();
    attachMenu(window.Menu);
    applyPage();
    purgeStoredPosts();
  }

  window.EirinchanPostFilter = {
    apply: applyPage,
    clearAll: clearAll,
    readState: readState
  };

  $(document).on("menu_ready.postFilterBootstrap", function () {
    attachMenu(window.Menu);
  });
  $(initialize);
  if (window.Menu) attachMenu(window.Menu);
})(window, document);
