// Runs assets/filters/instagram.js in a tiny fake browser and checks its
// routing rules. Invoked from test/filter/filter_script_test.dart.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../assets/filters/instagram.js', import.meta.url), 'utf8');
const config = {
  homePath: '/?variant=following',
  blockedPrefixes: ['/reels'],
  searchPath: '/explore/search/',
  searchRedirectPrefixes: ['/explore'],
  hiddenPostLabels: ['Sponsored'],
  feedEndLabels: [],
};

// Objects made inside the vm sandbox have foreign prototypes; compare as JSON.
const plain = (x) => JSON.parse(JSON.stringify(x));

function fakeBrowser(startHref) {
  const calls = { replace: [], assign: [], notify: [] };
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
  const element = () => ({ appendChild() {}, setAttribute() {} });
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
      querySelectorAll: () => [],
    },
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
  const { window } = fakeBrowser('https://www.instagram.com/?variant=following');
  const d = (path, search) => plain(window.__calmIg.decide(path, search));
  assert.deepEqual(d('/reels/', ''), { target: '/?variant=following', blocked: true });
  assert.deepEqual(d('/reels/C9abc/', ''), { target: '/?variant=following', blocked: true });
  assert.deepEqual(d('/explore/', ''), { target: '/explore/search/', blocked: true });
  assert.deepEqual(d('/explore/tags/cats/', ''), { target: '/explore/search/', blocked: true });
  assert.deepEqual(d('/', ''), { target: '/?variant=following', blocked: false });
  assert.deepEqual(d('/', '?variant=home'), { target: '/?variant=following', blocked: false });
  for (const allowed of ['/explore/search/', '/reel/Cxyz/', '/direct/inbox/', '/reelsfan/', '/p/abc/']) {
    assert.equal(d(allowed, ''), null, allowed);
  }
  assert.equal(d('/', '?variant=following'), null);
});

test('a client-side jump to Reels is reverted and reported', () => {
  const { history, calls } = fakeBrowser('https://www.instagram.com/?variant=following');
  history.pushState({}, '', '/reels/C9abc/');
  assert.deepEqual(calls.replace, ['/?variant=following']);
  assert.deepEqual(plain(calls.notify), [{ kind: 'blocked', path: '/reels/C9abc/' }]);
});

test('DMs and stories are left alone', () => {
  const { history, calls } = fakeBrowser('https://www.instagram.com/?variant=following');
  history.pushState({}, '', '/direct/inbox/');
  history.pushState({}, '', '/stories/friend/123/');
  assert.deepEqual(calls.replace, []);
  assert.deepEqual(calls.notify, []);
});

test('stops redirecting home if Instagram keeps dropping the variant', () => {
  const { history, calls } = fakeBrowser('https://www.instagram.com/?variant=following');
  for (let i = 0; i < 6; i++) history.replaceState({}, '', '/');
  assert.equal(calls.replace.length, 3);
});
