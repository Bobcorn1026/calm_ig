// calm_ig filter: injected at document start into instagram.com.
// Expects `window.__CALM_IG_CONFIG__` (see lib/filter/filter_config.dart).
(function () {
  'use strict';
  if (window.__calmIgInstalled) return;
  window.__calmIgInstalled = true;

  var cfg = window.__CALM_IG_CONFIG__ || {};
  var HOME = cfg.homePath || '/?variant=following';
  var SEARCH = cfg.searchPath || '/explore/search/';
  var BLOCKED = cfg.blockedPrefixes || ['/reels'];
  var TO_SEARCH = cfg.searchRedirectPrefixes || ['/explore'];
  var HIDDEN_LABELS = cfg.hiddenPostLabels || [];
  var END_LABELS = cfg.feedEndLabels || [];

  function hasPrefix(path, prefix) {
    var p = prefix.charAt(prefix.length - 1) === '/' ? prefix.slice(0, -1) : prefix;
    return path === p || path.indexOf(p + '/') === 0;
  }

  // Same rules as decideUrl() in lib/filter/url_rules.dart.
  // Returns null (allow) or {target, blocked}.
  function decide(path, search) {
    var i;
    for (i = 0; i < BLOCKED.length; i++) {
      if (hasPrefix(path, BLOCKED[i])) return { target: HOME, blocked: true };
    }
    if (!hasPrefix(path, SEARCH)) {
      for (i = 0; i < TO_SEARCH.length; i++) {
        if (hasPrefix(path, TO_SEARCH[i])) return { target: SEARCH, blocked: true };
      }
    }
    if (path === '/' && !/[?&]variant=following(&|$)/.test(search || '')) {
      return { target: HOME, blocked: false };
    }
    return null;
  }

  function notify(path) {
    try {
      window.flutter_inappwebview.callHandler('calmIg', { kind: 'blocked', path: path });
    } catch (e) { /* not inside the app (tests / desktop) */ }
  }

  function parse(href) {
    try { return new URL(href, location.href); } catch (e) { return null; }
  }

  function isInstagramPage(url) {
    return url && url.origin === location.origin;
  }

  // If Instagram itself keeps rewriting the home URL (e.g. it drops
  // ?variant=following), stop fighting it instead of looping forever.
  function homeRedirectAllowed() {
    try {
      var now = Date.now();
      var key = 'calmIgHomeRedirects';
      var recent = JSON.parse(sessionStorage.getItem(key) || '[]').filter(function (t) {
        return now - t < 10000;
      });
      if (recent.length >= 3) return false;
      recent.push(now);
      sessionStorage.setItem(key, JSON.stringify(recent));
    } catch (e) { /* storage unavailable: allow */ }
    return true;
  }

  function go(d, path, replace) {
    if (d.blocked) notify(path);
    if (d.target === location.pathname + location.search) {
      window.scrollTo(0, 0);
      return;
    }
    if (!d.blocked && !homeRedirectAllowed()) return;
    if (replace) location.replace(d.target); else location.assign(d.target);
  }

  // 1. Stop taps on blocked links before Instagram's router reacts.
  document.addEventListener('click', function (e) {
    var el = e.target;
    var a = el && el.closest ? el.closest('a[href]') : null;
    if (!a) return;
    var url = parse(a.getAttribute('href'));
    if (!isInstagramPage(url)) return;
    var d = decide(url.pathname, url.search);
    if (!d) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    go(d, url.pathname, false);
  }, true);

  // 2. Catch client-side route changes that did not come from a link.
  function enforce() {
    var d = decide(location.pathname, location.search);
    if (d) go(d, location.pathname, true);
  }
  ['pushState', 'replaceState'].forEach(function (name) {
    var original = history[name];
    history[name] = function () {
      var result = original.apply(this, arguments);
      enforce();
      return result;
    };
  });
  window.addEventListener('popstate', enforce);

  // 3. Hide entry points with CSS (works before the page renders).
  var css = BLOCKED.map(function (p) {
    return 'a[href="' + p + '"], a[href="' + p + '/"], a[href^="' + p + '/"]';
  }).join(',\n') + ' { display: none !important; }\n' +
    '[data-calm-hidden] { display: none !important; }';
  var style = document.createElement('style');
  style.id = 'calm-ig-style';
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  // 4. Hide suggested / sponsored posts and everything after the end of
  //    the Following feed.
  function textMatches(node, labels) {
    var text = (node.textContent || '').trim();
    if (!text || text.length > 60) return false;
    for (var i = 0; i < labels.length; i++) {
      if (text === labels[i]) return true;
    }
    return false;
  }

  function containsLabel(root, labels) {
    if (!labels.length) return false;
    var nodes = root.querySelectorAll('span, a, div, h2, h3, h4');
    for (var i = 0; i < nodes.length; i++) {
      // Only leaf-ish nodes: the label itself, not a big container.
      if (nodes[i].children.length <= 1 && textMatches(nodes[i], labels)) return true;
    }
    return false;
  }

  function sweep() {
    var articles = document.querySelectorAll('article');
    var pastEnd = false;
    var endMarker = null;
    if (END_LABELS.length) {
      var candidates = document.querySelectorAll('span, div, h2, h3');
      for (var i = 0; i < candidates.length; i++) {
        if (candidates[i].children.length <= 1 && textMatches(candidates[i], END_LABELS)) {
          endMarker = candidates[i];
          break;
        }
      }
    }
    for (var j = 0; j < articles.length; j++) {
      var article = articles[j];
      if (endMarker && !pastEnd &&
          (endMarker.compareDocumentPosition(article) & Node.DOCUMENT_POSITION_FOLLOWING)) {
        pastEnd = true;
      }
      if (pastEnd || containsLabel(article, HIDDEN_LABELS)) {
        article.setAttribute('data-calm-hidden', '');
      }
    }
  }

  var scheduled = false;
  function scheduleSweep() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(function () {
      scheduled = false;
      sweep();
    });
  }
  new MutationObserver(scheduleSweep).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });

  // Exposed for tests only.
  window.__calmIg = { decide: decide, sweep: sweep };

  enforce();
})();
