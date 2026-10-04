import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { escapeHtml, relativeTime, renderBoard } from '../src/page.js';
import { postScore, request, uuid, withServer } from './helpers.js';

const NATASHA = '11111111-1111-4111-8111-111111111111';

async function getHome(port) {
  const res = await fetch(`http://127.0.0.1:${port}/`);
  const text = await res.text();
  return { status: res.status, headers: res.headers, text };
}

function namedRows(html) {
  return [...html.matchAll(/<td class="name">([\s\S]*?)<\/td>/g)].map((m) => m[1]);
}

function rankRows(html) {
  return [...html.matchAll(/<td class="rank">([\s\S]*?)<\/td>/g)].map((m) => m[1]);
}

/** Expected arcade ordinal for a numeric rank the board already assigned. */
function arcadeOrdinal(rank) {
  const n = Number(rank);
  const mod100 = Math.abs(n) % 100;
  let suffix = 'TH';
  if (mod100 < 11 || mod100 > 13) {
    const mod10 = Math.abs(n) % 10;
    if (mod10 === 1) suffix = 'ST';
    else if (mod10 === 2) suffix = 'ND';
    else if (mod10 === 3) suffix = 'RD';
  }
  return `${n}${suffix}`;
}

describe('escapeHtml', () => {
  it('escapes &, <, >, ", and \'', () => {
    assert.equal(escapeHtml(`<script>&"'`), '&lt;script&gt;&amp;&quot;&#39;');
  });
});

describe('relativeTime', () => {
  const now = Date.parse('2026-09-08T18:00:00.000Z');

  it('uses minutes, hours, and days', () => {
    assert.equal(relativeTime('2026-09-08T17:59:30.000Z', now), 'just now');
    assert.equal(relativeTime('2026-09-08T17:59:00.000Z', now), '1 minute ago');
    assert.equal(relativeTime('2026-09-08T17:40:00.000Z', now), '20 minutes ago');
    assert.equal(relativeTime('2026-09-08T17:00:00.000Z', now), '1 hour ago');
    assert.equal(relativeTime('2026-09-08T16:00:00.000Z', now), '2 hours ago');
    assert.equal(relativeTime('2026-09-07T18:00:00.000Z', now), '1 day ago');
    assert.equal(relativeTime('2026-09-06T18:00:00.000Z', now), '2 days ago');
  });

  it('treats an unparseable or future timestamp as just now', () => {
    assert.equal(relativeTime('not-a-date', now), 'just now');
    assert.equal(relativeTime('2026-09-08T19:00:00.000Z', now), 'just now');
  });
});

describe('renderBoard', () => {
  it('renders No scores yet on an empty board', () => {
    const html = renderBoard({ entries: [], total_players: 0 });
    assert.match(html, /No scores yet/);
    assert.match(html, /0 players/);
    assert.equal(namedRows(html).length, 0);
  });

  it('does not throw when entries is missing', () => {
    const html = renderBoard({});
    assert.match(html, /No scores yet/);
  });

  it('uses the singular player label when total_players is 1', () => {
    const html = renderBoard({
      entries: [{
        rank: 1,
        player_id: NATASHA,
        name: 'Natasha',
        score: 100,
        at: '2026-09-08T18:00:00.000Z',
        avatar: '',
      }],
      total_players: 1,
    });
    assert.match(html, /1 player · /);
    assert.doesNotMatch(html, /1 players/);
  });

  it('emits one same-origin img when avatar is set, and none when empty', () => {
    const withAvatar = renderBoard({
      entries: [{
        rank: 1,
        player_id: NATASHA,
        name: 'Natasha',
        score: 100,
        at: '2026-09-08T18:00:00.000Z',
        avatar: 'bear_bounce',
      }],
      total_players: 1,
    });
    const imgs = [...withAvatar.matchAll(/<img\b[^>]*>/g)].map((m) => m[0]);
    assert.equal(imgs.length, 1);
    assert.match(imgs[0], /src="\/avatars\/bear_bounce\.png"/);
    assert.doesNotMatch(imgs[0], /src="https?:/);

    const without = renderBoard({
      entries: [{
        rank: 1,
        player_id: NATASHA,
        name: 'Natasha',
        score: 100,
        at: '2026-09-08T18:00:00.000Z',
        avatar: '',
      }],
      total_players: 1,
    });
    assert.doesNotMatch(without, /<img\b/);
  });

  it('escapes a <script> name everywhere including the img alt text', () => {
    const nasty = `<script>alert(1)</script>`;
    const html = renderBoard({
      entries: [{
        rank: 1,
        player_id: NATASHA,
        name: nasty,
        score: 100,
        at: '2026-09-08T18:00:00.000Z',
        avatar: 'bear_bounce',
      }],
      total_players: 1,
    });
    assert.match(html, /alt="&lt;script&gt;alert\(1\)&lt;\/script&gt;"/);
    assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
    assert.doesNotMatch(html, /<script/i);
    assert.doesNotMatch(html, new RegExp(nasty));
    assert.equal(html.includes(nasty), false);
  });

  it('renders arcade ordinals, including the 11–13 exception', () => {
    const ranks = [1, 2, 3, 4, 11, 12, 13, 21, 22, 23];
    const expected = ['1ST', '2ND', '3RD', '4TH', '11TH', '12TH', '13TH', '21ST', '22ND', '23RD'];
    const html = renderBoard({
      entries: ranks.map((rank, i) => ({
        rank,
        name: `P${i}`,
        score: 1000 - i,
        avatar: '',
      })),
      total_players: ranks.length,
    });
    assert.deepEqual(rankRows(html), expected);
  });

  it('keeps a shared rank as two 1STs', () => {
    const html = renderBoard({
      entries: [
        { rank: 1, name: 'Ada', score: 50, avatar: '' },
        { rank: 1, name: 'Bea', score: 50, avatar: '' },
      ],
      total_players: 2,
    });
    assert.deepEqual(rankRows(html), ['1ST', '1ST']);
  });

  it('escapes an img-payload name in the cell and the avatar alt, and nowhere else', () => {
    const nasty = '<img src=x onerror=alert(1)>';
    const escaped = '&lt;img src=x onerror=alert(1)&gt;';
    const html = renderBoard({
      entries: [{
        rank: 1,
        name: nasty,
        score: 10,
        avatar: 'bear_bounce',
      }],
      total_players: 1,
    });
    assert.equal(html.split(escaped).length - 1, 2);
    assert.ok(html.includes(`alt="${escaped}"`));
    assert.ok(html.includes(`<td class="name"><img src="/avatars/bear_bounce.png" alt="${escaped}">${escaped}</td>`));
    assert.equal(html.includes(nasty), false);
    const imgs = [...html.matchAll(/<img\b[^>]*>/g)].map((m) => m[0]);
    assert.equal(imgs.length, 1);
    assert.match(imgs[0], /src="\/avatars\/bear_bounce\.png"/);
    assert.doesNotMatch(imgs[0], /src="https?:/);
  });

  it('escapes a non-numeric rank and a markup score in their cells', () => {
    const nasty = '<img src=x onerror=alert(1)>';
    const html = renderBoard({
      entries: [{ rank: nasty, name: 'Ada', score: nasty, avatar: '' }],
      total_players: 1,
    });
    const escaped = '&lt;img src=x onerror=alert(1)&gt;';
    assert.deepEqual(rankRows(html), [escaped]);
    assert.ok(html.includes(`<td class="score">${escaped}</td>`));
    assert.equal(html.includes('<img'), false);
    assert.equal(html.includes(nasty), false);
  });

  it('drops the when column and keeps the empty state, player count, and JSON link', () => {
    const empty = renderBoard({ entries: [], total_players: 0 });
    assert.match(empty, /No scores yet/);
    assert.match(empty, /0 players/);
    assert.match(empty, /href="\/v1\/leaderboard"/);
    assert.match(empty, /HIGH SCORES/);
    assert.doesNotMatch(empty, /class="when"/);
    assert.doesNotMatch(empty, />When</);
    assert.doesNotMatch(empty, /just now|minute ago|hour ago|day ago/);

    const full = renderBoard({
      entries: [{
        rank: 1,
        name: 'Ada',
        score: 10,
        at: '2026-09-08T18:00:00.000Z',
        avatar: '',
      }],
      total_players: 4,
    });
    assert.match(full, /<th class="rank">RANK<\/th><th class="name">NAME<\/th><th class="score">SCORE<\/th>/);
    assert.doesNotMatch(full, /class="when"/);
    assert.doesNotMatch(full, />When</);
    assert.doesNotMatch(full, /just now|minute ago|hour ago|day ago/);
    assert.match(full, /4 players/);
    assert.match(full, /href="\/v1\/leaderboard"/);
  });

  it('switches off every animation under prefers-reduced-motion', () => {
    const html = renderBoard({ entries: [], total_players: 0 });
    const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
    const keyframes = [...style.matchAll(/@keyframes\s+([\w-]+)/g)].map((m) => m[1]);
    assert.ok(keyframes.length >= 1);
    const mediaAt = style.indexOf('@media (prefers-reduced-motion: reduce)');
    assert.ok(mediaAt >= 0);
    const media = style.slice(mediaAt);
    assert.match(media, /animation:\s*none/);
    for (const name of keyframes) {
      const at = style.indexOf(`@keyframes ${name}`);
      assert.ok(at >= 0 && at < mediaAt, `${name} is declared before the reduced-motion rule`);
      assert.match(style.slice(0, mediaAt), new RegExp(`animation:\\s*${name}\\b`));
    }
    assert.doesNotMatch(media.slice(media.lastIndexOf('}') + 1), /animation\s*:/);
    assert.match(style, /Press Start 2P/);
    assert.match(style, /monospace/);
    assert.match(style, /@font-face\{font-family:"Press Start 2P"/);
    assert.match(html, /data:font\/woff2;base64,/);
    assert.equal(html.includes('fonts.googleapis.com'), false);
    assert.equal(html.includes('fonts.gstatic.com'), false);
  });
});

describe('GET /', () => {
  it('returns 200 with text/html and Cache-Control: no-store', async () => {
    await withServer(async ({ port }) => {
      const res = await getHome(port);
      assert.equal(res.status, 200);
      assert.match(res.headers.get('content-type') ?? '', /text\/html.*charset=utf-8/i);
      assert.equal(res.headers.get('cache-control'), 'no-store');
      assert.match(res.text, /Squishy Leaderboard/);
      assert.match(res.text, /href="\/v1\/leaderboard"/);
      assert.doesNotMatch(res.text, /<script/i);
    });
  });

  it('empty board renders No scores yet', async () => {
    await withServer(async ({ port }) => {
      const res = await getHome(port);
      assert.equal(res.status, 200);
      assert.match(res.text, /No scores yet/);
      assert.match(res.text, /0 players/);
    });
  });

  it('lists at most 10 rows in rank order with the latest name', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'OldName', score: 9000 });
      await postScore(port, { player_id: NATASHA, name: 'Latest', score: 100 });
      for (let i = 0; i < 10; i += 1) {
        await postScore(port, {
          player_id: uuid(),
          name: `P${i}`,
          score: 8000 - i * 100,
        });
      }

      const json = await request(port, 'GET', '/v1/leaderboard?limit=10');
      assert.equal(json.status, 200);
      assert.equal(json.json.entries.length, 10);
      assert.equal(json.json.total_players, 11);

      const res = await getHome(port);
      const names = namedRows(res.text);
      const ranks = rankRows(res.text);
      assert.equal(names.length, 10);
      assert.equal(names[0], 'Latest');
      assert.doesNotMatch(res.text, /OldName/);
      assert.equal(ranks[0], '1ST');
      assert.match(res.text, /11 players/);
      assert.match(res.text, />9000</);
      for (let i = 0; i < 10; i += 1) {
        assert.equal(names[i], json.json.entries[i].name);
        assert.equal(ranks[i], arcadeOrdinal(json.json.entries[i].rank));
      }
    });
  });

  it('HTML-escapes a name that contains <script> and &', async () => {
    await withServer(async ({ port }) => {
      const nasty = `<script>&"'`;
      const posted = await postScore(port, {
        player_id: NATASHA,
        name: nasty,
        score: 4800,
      });
      assert.equal(posted.status, 201);

      const res = await getHome(port);
      assert.equal(res.status, 200);
      assert.match(res.text, /&lt;script&gt;&amp;&quot;&#39;/);
      assert.equal((res.text.match(/&lt;script&gt;/g) ?? []).length, 1);
      assert.doesNotMatch(res.text, /<script/i);
      assert.doesNotMatch(res.text, new RegExp(nasty));
      assert.equal(res.text.includes(nasty), false);
    });
  });
});
