(function (window, document) {
  "use strict";

  var HISTORY_LIMIT = 8;
  var HASH_FILE_LIMIT = 64 * 1024 * 1024;

  function md5Base64(buffer) {
    var bytes = new Uint8Array(buffer);
    var paddedLength = Math.ceil((bytes.length + 9) / 64) * 64;
    var padded = new Uint8Array(paddedLength);
    var view = new DataView(padded.buffer);
    padded.set(bytes);
    padded[bytes.length] = 0x80;
    var bitLength = bytes.length * 8;
    view.setUint32(paddedLength - 8, bitLength >>> 0, true);
    view.setUint32(paddedLength - 4, Math.floor(bitLength / 0x100000000), true);

    var shifts = [
      7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
      5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ];
    var constants = [];
    for (var index = 0; index < 64; index += 1) {
      constants[index] = Math.floor(Math.abs(Math.sin(index + 1)) * 0x100000000) >>> 0;
    }

    var a0 = 0x67452301;
    var b0 = 0xefcdab89;
    var c0 = 0x98badcfe;
    var d0 = 0x10325476;

    function add(left, right) {
      return (left + right) >>> 0;
    }

    function rotateLeft(value, count) {
      return ((value << count) | (value >>> (32 - count))) >>> 0;
    }

    for (var offset = 0; offset < paddedLength; offset += 64) {
      var words = [];
      for (var word = 0; word < 16; word += 1) {
        words[word] = view.getUint32(offset + word * 4, true);
      }

      var a = a0;
      var b = b0;
      var c = c0;
      var d = d0;

      for (var round = 0; round < 64; round += 1) {
        var f;
        var g;
        if (round < 16) {
          f = (b & c) | (~b & d);
          g = round;
        } else if (round < 32) {
          f = (d & b) | (~d & c);
          g = (5 * round + 1) % 16;
        } else if (round < 48) {
          f = b ^ c ^ d;
          g = (3 * round + 5) % 16;
        } else {
          f = c ^ (b | ~d);
          g = (7 * round) % 16;
        }

        var previousD = d;
        d = c;
        c = b;
        var sum = add(add(a, f >>> 0), add(constants[round], words[g]));
        b = add(b, rotateLeft(sum, shifts[round]));
        a = previousD;
      }

      a0 = add(a0, a);
      b0 = add(b0, b);
      c0 = add(c0, c);
      d0 = add(d0, d);
    }

    var digest = new Uint8Array(16);
    var digestView = new DataView(digest.buffer);
    digestView.setUint32(0, a0, true);
    digestView.setUint32(4, b0, true);
    digestView.setUint32(8, c0, true);
    digestView.setUint32(12, d0, true);

    var binary = "";
    for (var byte = 0; byte < digest.length; byte += 1) {
      binary += String.fromCharCode(digest[byte]);
    }
    return window.btoa(binary);
  }

  function readHistory(key) {
    try {
      var parsed = JSON.parse(window.localStorage.getItem(key) || "[]");
      return Array.isArray(parsed) ? parsed.slice(0, HISTORY_LIMIT) : [];
    } catch (_error) {
      return [];
    }
  }

  function writeHistory(key, entries) {
    try {
      window.localStorage.setItem(key, JSON.stringify(entries.slice(0, HISTORY_LIMIT)));
    } catch (_error) {
      // Search remains fully functional when local storage is unavailable.
    }
  }

  function historyLabel(params) {
    var text = (params.get("text") || "").trim();
    var boards = params.getAll("boards[]");
    var scope = params.get("scope") === "all" ? "all boards" : boards.map(function (board) {
      return "/" + board + "/";
    }).join(", ");
    return (text || "Filtered search") + (scope ? " — " + scope : "");
  }

  function renderHistory(key, list) {
    if (!list) return;
    var entries = readHistory(key);
    list.replaceChildren();
    if (!entries.length) {
      var empty = document.createElement("li");
      empty.className = "unimportant";
      empty.textContent = "Stored only in this browser.";
      list.appendChild(empty);
      return;
    }

    entries.forEach(function (entry) {
      var item = document.createElement("li");
      var link = document.createElement("a");
      link.href = entry.url;
      link.textContent = entry.label;
      item.appendChild(link);
      list.appendChild(item);
    });
  }

  function storeSubmittedSearch(form, submitter) {
    var key = form.dataset.searchHistoryKey;
    if (!key) return;
    var params = new URLSearchParams(new FormData(form));
    params.set("scope", submitter && submitter.value === "all" ? "all" : "selected");
    params.delete("page");
    var entry = {url: "/search.php?" + params.toString(), label: historyLabel(params)};
    var entries = readHistory(key).filter(function (existing) {
      return existing.url !== entry.url;
    });
    writeHistory(key, [entry].concat(entries));
  }

  function hashFile(file, hashInput, button) {
    if (!file || !hashInput || !button) return;
    if (file.size > HASH_FILE_LIMIT) {
      button.textContent = "File too large to hash";
      return;
    }

    button.disabled = true;
    button.textContent = "Hashing…";
    file.arrayBuffer().then(function (buffer) {
      hashInput.value = md5Base64(buffer);
      button.textContent = "Image hash ready";
    }).catch(function () {
      button.textContent = "Could not hash image";
    }).finally(function () {
      button.disabled = false;
    });
  }

  function highlightTerms(container, rawQuery) {
    if (!container || !rawQuery) return;
    var terms = [];
    var matcher = /"([^"]+)"|(\S+)/g;
    var match;
    while ((match = matcher.exec(rawQuery)) && terms.length < 12) {
      var term = (match[1] || match[2] || "").replace(/^[a-z_]+:/i, "").replace(/[?*]+/g, "");
      if (term.length > 1 && terms.indexOf(term) === -1) terms.push(term);
    }
    if (!terms.length) return;

    terms.sort(function (left, right) { return right.length - left.length; });
    var expression = new RegExp("(" + terms.map(function (term) {
      return term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }).join("|") + ")", "gi");
    var walker = document.createTreeWalker(container, window.NodeFilter.SHOW_TEXT);
    var nodes = [];
    var node;
    while ((node = walker.nextNode()) && nodes.length < 500) {
      var parent = node.parentElement;
      if (parent && !parent.closest("script, style, mark") && expression.test(node.nodeValue)) {
        nodes.push(node);
      }
      expression.lastIndex = 0;
    }

    nodes.forEach(function (textNode) {
      var fragment = document.createDocumentFragment();
      var cursor = 0;
      textNode.nodeValue.replace(expression, function (found, _capture, offset) {
        fragment.appendChild(document.createTextNode(textNode.nodeValue.slice(cursor, offset)));
        var mark = document.createElement("mark");
        mark.textContent = found;
        fragment.appendChild(mark);
        cursor = offset + found.length;
        return found;
      });
      fragment.appendChild(document.createTextNode(textNode.nodeValue.slice(cursor)));
      textNode.replaceWith(fragment);
    });
  }

  function init() {
    var form = document.getElementById("advanced-search");
    if (!form) return;
    var historyKey = form.dataset.searchHistoryKey;
    var historyList = document.getElementById("search-history-list");
    renderHistory(historyKey, historyList);

    form.addEventListener("submit", function (event) {
      storeSubmittedSearch(form, event.submitter);
    });

    document.querySelectorAll("[data-uncheck]").forEach(function (button) {
      button.addEventListener("click", function () {
        var group = document.getElementById(button.dataset.uncheck);
        if (group) group.querySelectorAll('input[type="checkbox"]').forEach(function (input) {
          input.checked = false;
        });
      });
    });

    var historyClear = document.getElementById("search-history-clear");
    if (historyClear) historyClear.addEventListener("click", function () {
      writeHistory(historyKey, []);
      renderHistory(historyKey, historyList);
    });

    var hashInput = document.getElementById("search-image-hash");
    var fileInput = document.getElementById("search-image-file");
    var dropButton = document.getElementById("search-image-drop");
    if (dropButton && fileInput) {
      dropButton.addEventListener("click", function () { fileInput.click(); });
      fileInput.addEventListener("change", function () {
        hashFile(fileInput.files && fileInput.files[0], hashInput, dropButton);
      });
      ["dragenter", "dragover"].forEach(function (eventName) {
        dropButton.addEventListener(eventName, function (event) {
          event.preventDefault();
          dropButton.classList.add("dragover");
        });
      });
      ["dragleave", "drop"].forEach(function (eventName) {
        dropButton.addEventListener(eventName, function (event) {
          event.preventDefault();
          dropButton.classList.remove("dragover");
        });
      });
      dropButton.addEventListener("drop", function (event) {
        hashFile(event.dataTransfer && event.dataTransfer.files[0], hashInput, dropButton);
      });
    }

    var results = document.querySelector(".search-results[data-highlight]");
    if (results) highlightTerms(results, results.dataset.highlight);
  }

  window.EirinchanSearch = {md5Base64: md5Base64};
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})(window, document);
