function banlist_init(url, my_boards) {
  var translate = window._ || function(value) { return value; };
  var deviceType = window.device_type || ($('html').hasClass('mobile-style') ? 'mobile' : 'desktop');
  var lt;
  var selected = {};

  function time() {
    return Date.now() / 1000 | 0;
  }

  function escapeHTML(value) {
    return $('<div>').text(value == null ? '' : String(value)).html();
  }

  function agoText(seconds) {
    var delta = Math.max(0, time() - (seconds | 0));

    if (delta < 60) return delta + 's';
    if (delta < 3600) return Math.floor(delta / 60) + 'm';
    if (delta < 86400) return Math.floor(delta / 3600) + 'h';
    if (delta < 604800) return Math.floor(delta / 86400) + 'd';
    if (delta < 2592000) return Math.floor(delta / 604800) + 'w';
    if (delta < 31536000) return Math.floor(delta / 2592000) + 'mo';
    return Math.floor(delta / 31536000) + 'y';
  }

  function untilText(seconds) {
    var delta = Math.max(0, (seconds | 0) - time());

    if (delta < 60) return delta + 's';
    if (delta < 3600) return Math.floor(delta / 60) + 'm';
    if (delta < 86400) return Math.floor(delta / 3600) + 'h';
    if (delta < 604800) return Math.floor(delta / 86400) + 'd';
    if (delta < 2592000) return Math.floor(delta / 604800) + 'w';
    if (delta < 31536000) return Math.floor(delta / 2592000) + 'mo';
    return Math.floor(delta / 31536000) + 'y';
  }

  $.getJSON(url, function(data) {
    $("#banlist").on("new-row", function(e, drow, el) {
      var sel = selected[drow.id];
      if (sel) {
        $(el).find('input.unban').prop("checked", true);
      }

      $(el).find('input.unban').on("click", function() {
        selected[drow.id] = $(this).prop("checked");
      });

      if (drow.active === false || (drow.expires && drow.expires !== 0 && drow.expires < time())) {
        $(el).find("td").css("text-decoration", "line-through");
      }
    });

    var selall = "<input type='checkbox' id='select-all' style='float: left;'>";

    lt = $("#banlist").longtable({
      mask: {
        name: selall + translate("IP address"),
        width: "220px",
        fmt: function(row) {
          var pre = row.access ? "<input type='checkbox' class='unban' name='ban_ids[]' value='" + escapeHTML(row.id) + "'>" : "";
          var label = escapeHTML(row.mask);

          if (row.history_url) {
            return pre + "<a href='" + escapeHTML(row.history_url) + "'>" + label + "</a>";
          }

          return pre + label;
        }
      },
      reason: {
        name: translate("Reason"),
        width: "calc(100% - 770px - 6 * 4px)",
        fmt: function(row) {
          var add = "";
          var suffix = "";

          if (row.seen === 1) {
            add += "<i class='fa fa-check' title='" + translate("Seen") + "'></i>";
          }

          if (row.message) {
            add += "<i class='fa fa-comment' title='" + translate("Message for which user was banned is included") + "'></i>";
            suffix = "<br /><br /><strong>" + translate("Message:") + "</strong><br />" + escapeHTML(row.message);
          }

          if (add) {
            add = "<div style='float: right;'>" + add + "</div>";
          }

          return add + (row.reason ? escapeHTML(row.reason) : "-") + suffix;
        }
      },
      board: {
        name: translate("Board"),
        width: "60px",
        fmt: function(row) {
          if (row.board) return "/" + escapeHTML(row.board) + "/";
          return "<em>" + translate("all") + "</em>";
        }
      },
      created: {
        name: translate("Set"),
        width: "100px",
        fmt: function(row) {
          return agoText(row.created) + translate(" ago");
        }
      },
      expires: {
        name: translate("Expires"),
        width: "235px",
        fmt: function(row) {
          if (!row.expires || row.expires === 0) {
            return "<em>" + translate("never") + "</em>";
          }

          var formattedDate = strftime("%m/%d/%Y (%a) %H:%M:%S", new Date((row.expires | 0) * 1000), datelocale);
          return formattedDate + ((row.expires < time()) ? "" : " <small>" + translate("in ") + untilText(row.expires | 0) + "</small>");
        }
      },
      username: {
        name: translate("Staff"),
        width: "100px",
        fmt: function(row) {
          if (!row.username) {
            return "<em>" + translate("system") + "</em>";
          }

          return escapeHTML(row.username);
        }
      },
      id: {
        name: translate("Edit"),
        width: "35px",
        fmt: function(row) {
          if (!row.edit_url) return "";
          return "<a href='" + escapeHTML(row.edit_url) + "'>Edit</a>";
        }
      }
    }, {}, data);

    $("#select-all").click(function(e) {
      var $this = $(this);
      $("input.unban").prop("checked", $this.prop("checked"));
      lt.get_data().forEach(function(row) {
        if (row.access) {
          selected[row.id] = $this.prop("checked");
        }
      });
      e.stopPropagation();
    });

    function filter(row) {
      if ($("#only_mine").prop("checked") && ($.inArray(row.board, my_boards) === -1)) return false;
      if ($("#only_not_expired").prop("checked")) {
        if (row.active === false) return false;
        if (row.expires && row.expires !== 0 && row.expires < time()) return false;
      }

      if ($("#search").val()) {
        var terms = $("#search").val().split(" ");
        var fields = ["mask", "reason", "board", "staff", "message"];
        var retFalse = false;

        terms.forEach(function(term) {
          var fs = fields;
          var match;

          match = term.match(/^(mask|reason|board|staff|message):/);
          if (match) {
            fs = [match[1]];
            term = term.replace(/^(mask|reason|board|staff|message):/, "");
          }

          var found = false;
          fs.forEach(function(field) {
            var value = row[field];
            if (value && String(value).toLowerCase().indexOf(term.toLowerCase()) !== -1) {
              found = true;
            }
          });

          if (!found) retFalse = true;
        });

        if (retFalse) return false;
      }

      return true;
    }

    $("#only_mine, #only_not_expired, #search").on("click input", function() {
      lt.set_filter(filter);
    });
    lt.set_filter(filter);

    $("#unban").on("click", function(e) {
      if (!confirm('Are you sure you want to unban the selected IPs?')) {
        e.preventDefault();
        return;
      }

      $form.find(".hiddens").remove();

      $.each(selected, function(id, enabled) {
        if (enabled && !$form.find("input.unban[value='" + id + "']").length) {
          $("<input type='hidden' name='ban_ids[]' class='hiddens'>").val(id).appendTo($form);
        }
      });

      if (
        !$form.find("input.unban:checked").length &&
        !$form.find("input.hiddens[name='ban_ids[]']").length
      ) {
        e.preventDefault();
        return;
      }
    });

    if (deviceType === 'desktop') {
      var stick_on = $(".banlist-opts").offset().top;
      var state = true;

      $(window).on("scroll resize", function() {
        if ($(window).scrollTop() > stick_on && state === true) {
          $("body").css("margin-top", $(".banlist-opts").height());
          $(".banlist-opts").addClass("boardlist top").detach().prependTo("body");
          $("#banlist tr:not(.row)").addClass("tblhead").detach().appendTo(".banlist-opts");
          state = !state;
        } else if ($(window).scrollTop() < stick_on && state === false) {
          $("body").css("margin-top", "auto");
          $(".banlist-opts").removeClass("boardlist top").detach().prependTo(".banform");
          $(".tblhead").detach().prependTo("#banlist");
          state = !state;
        }
      });
    }
  });
};

$(function() {
  var $form = $(".banform[data-banlist-url]").first();

  if (!$form.length) {
    return;
  }

  var url = $form.attr("data-banlist-url");
  var myBoards = [];

  try {
    myBoards = JSON.parse($form.attr("data-my-boards") || "[]");
  } catch (_error) {
    myBoards = [];
  }

  banlist_init(url, myBoards);
});
