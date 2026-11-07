/// A stripped-down page shaped like Instagram's mobile site (structure taken
/// from the real site, Nov 2026): a container holding the stories row and the
/// feed as siblings, a bottom nav with Reels / Explore links, and a feed with
/// normal, sponsored and "after the end" posts.
const fakeIgHtml = '''
<!doctype html>
<html>
<head><meta name="viewport" content="width=device-width"></head>
<body>
  <main>
    <div id="feed-column">
      <div id="stories-row">
        <div role="button" aria-label="Story by some.friend, not seen">some.friend</div>
      </div>
      <div id="feed">
        <article id="friend-post"><span>some.friend</span><p>Lunch!</p></article>
        <article id="sponsored-post"><span>brand</span><span>Sponsored</span></article>
        <article id="friend-post-2"><span>other.friend</span></article>
        <div><span>You're all caught up</span></div>
        <article id="after-end-post"><span>Suggested account</span></article>
      </div>
    </div>
  </main>
  <nav>
    <a id="home-link" href="/">Home</a>
    <a id="search-link" href="/explore/">Search</a>
    <a id="reels-link" href="/reels/">Reels</a>
    <a id="dm-link" href="/direct/inbox/">Messages</a>
    <a id="single-reel-link" href="/some.friend/reel/Cxyz123/">A reel from a friend</a>
  </nav>
</body>
</html>
''';
