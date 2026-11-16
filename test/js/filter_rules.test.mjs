// Runs assets/filters/instagram.js in a tiny fake browser and checks its
// routing rules. Invoked from test/filter/filter_script_test.dart.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../assets/filters/instagram.js', import.meta.url), 'utf8');
const config = {
  homePath: '/',
  followingPath: '/?variant=following',
  feedVariants: ['following', 'favorites'],
  blockedPrefixes: ['/reels'],
  searchPath: '/explore/search/',
  searchRedirectPrefixes: ['/explore'],
  hiddenPostLabels: ['Sponsored'],
  feedEndLabels: [],
};

// Objects made inside the vm sandbox have foreign prototypes; compare as JSON.
const plain = (x) => JSON.parse(JSON.stringify(x));

// A fake element with just what checkHealth() reads.
const el = ({ href = null, label = null, text = '', visible = true } = {}) => ({
  getAttribute: (n) => (n === 'href' ? href : n === 'aria-label' ? label : null),
  textContent: text,
  getBoundingClientRect: () => (visible ? { width: 50, height: 50 } : { width: 0, height: 0 }),
});

function fakeBrowser(startHref, page = {}) {
  const { links = [], articles = [], story = null } = page;
  const calls = { replace: [], assign: [], notify: [], timers: [] };
  let href = new URL(startHref);
  const location = {
    get origin() { return href.origin; },
    get pathname() { return href.pathname; },
    get search() { return href.search; },
    get href() { return href.href; },
    replace(u) { calls.replace.push(u); },
    assign(u) { calls.assign.push(u); },
  };
  const history = {
    pushState(_s, _t, u) { href = new URL(u, href); },
    replaceState(_s, _t, u) { href = new URL(u, href); },
  };
  const store = new Map();
  const element = () => ({ appendChild() {}, setAttribute() {}, removeAttribute() {} });
  const window = {
    __CALM_IG_CONFIG__: config,
    flutter_inappwebview: { callHandler: (_n, e) => calls.notify.push(e) },
    addEventListener() {},
    scrollTo() {},
  };
  const context = {
    window,
    location,
    history,
    document: {
      head: element(),
      documentElement: element(),
      createElement: element,
      addEventListener() {},
      querySelectorAll: (sel) => (sel === 'a[href]' ? links : sel === 'article' ? articles : []),
      querySelector: (sel) => (sel.includes('Story by') ? story : null),
    },
    setTimeout: (fn) => calls.timers.push(fn),
    clearTimeout: () => {},
    sessionStorage: {
      getItem: (k) => store.get(k) ?? null,
      setItem: (k, v) => store.set(k, v),
    },
    MutationObserver: class { observe() {} },
    requestAnimationFrame: () => {},
    Node: { DOCUMENT_POSITION_FOLLOWING: 4 },
    URL,
    JSON,
    Date,
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return { window, history, calls };
}

test('decide() matches the Dart rules', () => {
  const { window } = fakeBrowser('https://www.instagram.com/');
  const d = (path) => plain(window.__calmIg.decide(path));
  assert.deepEqual(d('/reels/'), { target: '/' });
  assert.deepEqual(d('/reels/C9abc/'), { target: '/' });
  assert.deepEqual(d('/reels/audio/123/'), { target: '/' });
  assert.deepEqual(d('/explore/'), { target: '/explore/search/' });
  assert.deepEqual(d('/explore/tags/cats/'), { target: '/explore/search/' });
  for (const allowed of ['/', '/explore/search/', '/reel/Cxyz/', '/friend/reel/Cxyz/',
    '/friend/p/abc/', '/direct/inbox/', '/reelsfan/', '/p/abc/']) {
    assert.equal(d(allowed), null, allowed);
  }
});

test('isHomeFeed() tells home apart from the Following / Favorites feeds', () => {
  const { window } = fakeBrowser('https://www.instagram.com/');
  const h = window.__calmIg.isHomeFeed;
  assert.equal(h('/', ''), true);
  assert.equal(h('/', '?variant=home'), true);
  assert.equal(h('/', '?variant=following'), false);
  assert.equal(h('/', '?variant=favorites'), false);
  assert.equal(h('/direct/inbox/', ''), false);
});

test('a client-side jump to Reels is reverted and reported', () => {
  const { history, calls } = fakeBrowser('https://www.instagram.com/');
  history.pushState({}, '', '/reels/C9abc/');
  assert.deepEqual(calls.replace, ['/']);
  assert.deepEqual(plain(calls.notify), [{ kind: 'blocked', path: '/reels/C9abc/' }]);
});

test('DMs, stories and the Following feed are left alone', () => {
  const { history, calls } = fakeBrowser('https://www.instagram.com/');
  history.pushState({}, '', '/direct/inbox/');
  history.pushState({}, '', '/stories/friend/123/');
  history.pushState({}, '', '/?variant=following');
  history.pushState({}, '', '/');
  assert.deepEqual(calls.replace, []);
  assert.deepEqual(calls.notify, []);
});

test('health: a normal home page reports ok', () => {
  const { window, calls } = fakeBrowser('https://www.instagram.com/', {
    links: [el({ href: '/reels/', label: 'Reels', visible: false })],
    articles: [el({ visible: false })],
    story: el({ label: 'Story by friend, not seen' }),
  });
  assert.deepEqual(plain(window.__calmIg.checkHealth()), []);
  assert.deepEqual(plain(calls.notify.at(-1)), { kind: 'filter', ok: true, issues: [] });
});

test('health: Reels moved to a new path is caught', () => {
  const { window } = fakeBrowser('https://www.instagram.com/direct/inbox/', {
    links: [el({ href: '/clips/', label: 'Reels' })],
  });
  assert.deepEqual(plain(window.__calmIg.checkHealth()), ['reels-link-visible']);
});

test("health: a profile's own Reels tab is not a false alarm", () => {
  const { window } = fakeBrowser('https://www.instagram.com/someone/', {
    links: [el({ href: '/someone/reels/', label: 'Reels' })],
  });
  assert.deepEqual(plain(window.__calmIg.checkHealth()), []);
});

test('health: an absolute top-level Reels link is still caught', () => {
  const { window } = fakeBrowser('https://www.instagram.com/direct/inbox/', {
    links: [el({ href: 'https://www.instagram.com/clips/', text: 'Reels' })],
  });
  assert.deepEqual(plain(window.__calmIg.checkHealth()), ['reels-link-visible']);
});

test('health: home posts showing or no stories row is caught', () => {
  const { window } = fakeBrowser('https://www.instagram.com/', {
    articles: [el({ visible: true })],
    story: null,
  });
  assert.deepEqual(plain(window.__calmIg.checkHealth()), ['home-no-stories', 'home-feed-visible']);
});

test('health: the Following feed may show posts', () => {
  const { window } = fakeBrowser('https://www.instagram.com/?variant=following', {
    articles: [el({ visible: true })],
  });
  assert.deepEqual(plain(window.__calmIg.checkHealth()), []);
});

test('health: only reports when the result changes', () => {
  const { window, calls } = fakeBrowser('https://www.instagram.com/direct/inbox/');
  window.__calmIg.checkHealth();
  window.__calmIg.checkHealth();
  assert.equal(calls.notify.filter((e) => e.kind === 'filter').length, 1);
});

test('health check is scheduled after a page change, not run at once', () => {
  const { history, calls } = fakeBrowser('https://www.instagram.com/');
  const before = calls.timers.length;
  history.pushState({}, '', '/direct/inbox/');
  assert.equal(calls.timers.length, before + 1);
  assert.equal(calls.notify.filter((e) => e.kind === 'filter').length, 0);
});
