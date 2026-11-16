// calm_ig filter: injected at document start into instagram.com.
// Expects `window.__CALM_IG_CONFIG__` (see lib/filter/filter_config.dart).
(function () {
  'use strict';
  if (window.__calmIgInstalled) return;
  window.__calmIgInstalled = true;

  var cfg = window.__CALM_IG_CONFIG__ || {};
  var HOME = cfg.homePath || '/';
  var FOLLOWING = cfg.followingPath || '/?variant=following';
  var FEED_VARIANTS = cfg.feedVariants || ['following', 'favorites'];
  var SEARCH = cfg.searchPath || '/explore/search/';
  var BLOCKED = cfg.blockedPrefixes || ['/reels'];
  var TO_SEARCH = cfg.searchRedirectPrefixes || ['/explore'];
  var HIDDEN_LABELS = cfg.hiddenPostLabels || [];
  var END_LABELS = cfg.feedEndLabels || [];
  var FOLLOWING_LINK_TEXT = cfg.followingLinkText || 'Following →';
  var HEALTH_DELAY = cfg.healthCheckDelayMs || 5000;
  var STORY_SELECTOR = '[aria-label^="Story by"], [aria-label*="的限時動態"]';

  function hasPrefix(path, prefix) {
    var p = prefix.charAt(prefix.length - 1) === '/' ? prefix.slice(0, -1) : prefix;
    return path === p || path.indexOf(p + '/') === 0;
  }

  // Same rules as decideUrl() in lib/filter/url_rules.dart.
  // Returns null (allow) or {target}.
  function decide(path) {
    var i;
    for (i = 0; i < BLOCKED.length; i++) {
      if (hasPrefix(path, BLOCKED[i])) return { target: HOME };
    }
    if (!hasPrefix(path, SEARCH)) {
      for (i = 0; i < TO_SEARCH.length; i++) {
        if (hasPrefix(path, TO_SEARCH[i])) return { target: SEARCH };
      }
    }
    return null;
  }

  // The plain home page (stories row + algorithmic feed), as opposed to the
  // Following / Favorites feeds that share the "/" path.
  function isHomeFeed(path, search) {
    if (path !== '/') return false;
    var m = /[?&]variant=([^&]*)/.exec(search || '');
    return !m || FEED_VARIANTS.indexOf(m[1]) < 0;
  }

  function notify(path) {
    try {
      window.flutter_inappwebview.callHandler('calmIg', { kind: 'blocked', path: path });
    } catch (e) { /* not inside the app (tests / desktop) */ }
  }

  function parse(href) {
    try { return new URL(href, location.href); } catch (e) { return null; }
  }

  function go(d, path, replace) {
    notify(path);
    if (d.target === location.pathname + location.search) {
      window.scrollTo(0, 0);
      return;
    }
    if (replace) location.replace(d.target); else location.assign(d.target);
  }

  // 1. Stop taps on blocked links before Instagram's router reacts.
  document.addEventListener('click', function (e) {
    var el = e.target;
    var a = el && el.closest ? el.closest('a[href]') : null;
    if (!a) return;
    var url = parse(a.getAttribute('href'));
    if (!url || url.origin !== location.origin) return;
    var d = decide(url.pathname);
    if (!d) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    go(d, url.pathname, false);
  }, true);

  // 2. Catch client-side route changes that did not come from a link.
  function onRoute() {
    var d = decide(location.pathname);
    if (d) {
      go(d, location.pathname, true);
      return;
    }
    scheduleSweep();
    scheduleHealthCheck();
  }
  ['pushState', 'replaceState'].forEach(function (name) {
    var original = history[name];
    history[name] = function () {
      var result = original.apply(this, arguments);
      onRoute();
      return result;
    };
  });
  window.addEventListener('popstate', onRoute);

  // 3. CSS: hide entry points before the page renders. Home-feed hiding is
  //    switched by an attribute on <html> so the Following feed (same DOM,
  //    same path) is never affected.
  var css = BLOCKED.map(function (p) {
    return 'a[href="' + p + '"], a[href="' + p + '/"], a[href^="' + p + '/"]';
  }).join(',\n') + ' { display: none !important; }\n' +
    '[data-calm-hidden] { display: none !important; }\n' +
    'html[data-calm-home] [data-calm-home-hidden] { display: none !important; }\n' +
    'html:not([data-calm-home]) #calm-ig-following { display: none !important; }\n' +
    '#calm-ig-following { display: block; margin: 12px 16px; padding: 14px 16px;' +
    ' border-radius: 12px; background: rgba(127,127,127,0.14); color: inherit;' +
    ' font: 600 15px -apple-system, system-ui, sans-serif; text-align: center;' +
    ' text-decoration: none; }';
  var style = document.createElement('style');
  style.id = 'calm-ig-style';
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  function textMatches(node, labels) {
    var text = (node.textContent || '').trim();
    if (!text || text.length > 60) return false;
    for (var i = 0; i < labels.length; i++) {
      if (text === labels[i]) return true;
    }
    return false;
  }

  function findLeaf(root, selector, labels) {
    if (!labels.length) return null;
    var nodes = root.querySelectorAll(selector);
    for (var i = 0; i < nodes.length; i++) {
      // Only leaf-ish nodes: the label itself, not a big container.
      if (nodes[i].children.length <= 1 && textMatches(nodes[i], labels)) return nodes[i];
    }
    return null;
  }

  // 4a. Home: keep the stories row, hide the algorithmic feed next to it,
  //     and offer a link to the Following feed instead.
  function sweepHome() {
    var root = document.documentElement;
    if (!isHomeFeed(location.pathname, location.search)) {
      root.removeAttribute('data-calm-home');
      return;
    }
    root.setAttribute('data-calm-home', '');
    var story = document.querySelector(STORY_SELECTOR);
    var article = document.querySelector('article');
    if (!story || !article) {
      // Layout not recognised: at least hide the posts themselves.
      var posts = document.querySelectorAll('article');
      for (var k = 0; k < posts.length; k++) posts[k].setAttribute('data-calm-home-hidden', '');
      return;
    }
    // The closest container holding both: [stories row, feed, ...].
    var common = story.parentElement;
    while (common && !common.contains(article)) common = common.parentElement;
    if (!common) return;
    var storiesRow = null;
    for (var j = 0; j < common.children.length; j++) {
      var child = common.children[j];
      if (child.contains(story)) storiesRow = child;
      else if (child.id !== 'calm-ig-following') child.setAttribute('data-calm-home-hidden', '');
    }
    var link = document.getElementById('calm-ig-following');
    if (!link) {
      link = document.createElement('a');
      link.id = 'calm-ig-following';
      link.href = FOLLOWING;
      link.textContent = FOLLOWING_LINK_TEXT;
    }
    if (storiesRow && link.previousElementSibling !== storiesRow) storiesRow.after(link);
  }

  // 4b. Feeds: hide suggested / sponsored posts and everything after the
  //     end of the Following feed.
  function sweepPosts() {
    var articles = document.querySelectorAll('article');
    var endMarker = findLeaf(document, 'span, div, h2, h3', END_LABELS);
    var pastEnd = false;
    for (var j = 0; j < articles.length; j++) {
      var article = articles[j];
      if (endMarker && !pastEnd &&
          (endMarker.compareDocumentPosition(article) & Node.DOCUMENT_POSITION_FOLLOWING)) {
        pastEnd = true;
      }
      if (pastEnd || findLeaf(article, 'span, a, div, h2, h3, h4', HIDDEN_LABELS)) {
        article.setAttribute('data-calm-hidden', '');
      }
    }
  }

  function sweep() {
    sweepHome();
    sweepPosts();
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
  // 5. Tell the app when the page no longer looks like what these rules
  //    expect (Instagram changed its site), so it can show a warning.
  //    Checked a few seconds after each page change, once things settled.
  function isVisible(el) {
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  function isBlockedHref(href) {
    var url = parse(href);
    return !!(url && decide(url.pathname));
  }

  function checkHealth() {
    var issues = [];
    // A visible "Reels" entry that our rules don't block: the path changed.
    var links = document.querySelectorAll('a[href]');
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      var label = (a.getAttribute('aria-label') || a.textContent || '').trim();
      if (/^reels$/i.test(label) && isVisible(a) &&
          !isBlockedHref(a.getAttribute('href'))) {
        issues.push('reels-link-visible');
        break;
      }
    }
    if (isHomeFeed(location.pathname, location.search)) {
      var articles = document.querySelectorAll('article');
      // Posts loaded but no stories row to anchor on: the layout changed.
      if (articles.length && !document.querySelector(STORY_SELECTOR)) {
        issues.push('home-no-stories');
      }
      for (var j = 0; j < articles.length; j++) {
        if (isVisible(articles[j])) {
          issues.push('home-feed-visible');
          break;
        }
      }
    }
    report(issues);
    return issues;
  }

  var lastHealth = null;
  function report(issues) {
    var key = issues.join(',');
    if (key === lastHealth) return; // only when it changes
    lastHealth = key;
    try {
      window.flutter_inappwebview.callHandler('calmIg', {
        kind: 'filter', ok: issues.length === 0, issues: issues,
      });
    } catch (e) { /* not inside the app */ }
  }

  var healthTimer = null;
  function scheduleHealthCheck() {
    clearTimeout(healthTimer);
    healthTimer = setTimeout(function () {
      sweep(); // make sure hiding ran before judging it
      checkHealth();
    }, HEALTH_DELAY);
  }

  window.__calmIg = {
    decide: decide, isHomeFeed: isHomeFeed, sweep: sweep, checkHealth: checkHealth,
  };

  onRoute();
})();
