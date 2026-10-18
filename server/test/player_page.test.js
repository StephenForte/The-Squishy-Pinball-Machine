import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { describe, it } from 'node:test';
import { Script, createContext } from 'node:vm';
import { createRateLimiter } from '../src/index.js';
import { browserDateTime, renderPlayer } from '../src/page.js';
import { postScore, putProfile, request, uuid, withServer } from './helpers.js';

const KEY = 'devkey';
const DAD_A = 'b8aa808f-6d01-439e-87be-664baf0ead85';
const DAD_B = '86f2ea8f-40ab-4141-8411-0db7c837bc47';

const SCORES_SQL = `
  CREATE TABLE scores (
    id integer primary key,
    player_id text not null,
    name text not null,
    score integer not null,
    client text,
    created_at text not null
  )
`;

function playerPath(name) {
  return `/player?name=${encodeURIComponent(name)}`;
}

async function getHtml(port, path) {
  const res = await fetch(`http://127.0.0.1:${port}${path}`);
  const text = await res.text();
  return { status: res.status, headers: res.headers, text };
}

function gameRows(html) {
  return [...html.matchAll(/<tr( class="best")?><td class="date">(.*?)<\/td><td class="score">([^<]*)<\/td><td class="mark">([^<]*)<\/td><\/tr>/g)]
    .map((m) => {
      const time = m[2].match(/^<time datetime="([^"]*)">([^<]*)<\/time>$/);
      return {
        best: Boolean(m[1]),
        datetime: time ? time[1] : '',
        at: time ? time[2] : m[2],
        score: m[3],
        mark: m[4],
      };
    });
}

/** Run the page's own script against its `<time>` nodes and return the visible text. */
function applyBrowserTimes(html) {
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 1);
  const nodes = [...html.matchAll(/<time datetime="([^"]*)">([^<]*)<\/time>/g)].map((m) => ({
    datetime: m[1],
    textContent: m[2],
    getAttribute(name) {
      return name === 'datetime' ? this.datetime : null;
    },
  }));
  const sandbox = {
    document: {
      querySelectorAll(selector) {
        assert.equal(selector, 'time[datetime]');
        return nodes;
      },
    },
  };
  createContext(sandbox);
  new Script(scripts[0][1]).runInContext(sandbox);
  return nodes.map((node) => node.textContent);
}

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

function snapshot(path) {
  const db = new DatabaseSync(path, { readOnly: true });
  try {
    const profiles = db
      .prepare(
        'SELECT player_id, name, avatar, updated_at, name_key FROM profiles ORDER BY player_id',
      )
      .all();
    const scores = db
      .prepare(
        'SELECT id, player_id, name, score, client, created_at FROM scores ORDER BY id',
      )
      .all();
    const index = db
      .prepare(
        `SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'profiles_name_key'`,
      )
      .get();
    return { profiles, scores, indexSql: index ? index.sql : null };
  } finally {
    db.close();
  }
}

async function withFile(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'squish-player-'));
  const path = join(dir, 'squish.db');
  try {
    await fn(path);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function initEmpty(path) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(SCORES_SQL);
  db.exec(`
    CREATE TABLE profiles (
      player_id text primary key,
      name text not null,
      avatar text not null default '',
      updated_at text not null,
      name_key text not null default ''
    )
  `);
  db.close();
}

function seedAmbiguous(path) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(SCORES_SQL);
  db.exec(`
    CREATE TABLE profiles (
      player_id text primary key,
      name text not null,
      avatar text not null default '',
      updated_at text not null
    )
  `);
  const insert = db.prepare(
    'INSERT INTO profiles (player_id, name, avatar, updated_at) VALUES (?, ?, ?, ?)',
  );
  insert.run(DAD_A, 'Dad', '', '2026-01-01T00:00:00.000Z');
  insert.run(DAD_B, 'Dad', '', '2026-01-02T00:00:00.000Z');
  db.close();
}

const wideLimiter = {
  limiter: createRateLimiter({ windowMs: 60_000, max: 1000 }),
  ipLimiter: createRateLimiter({ windowMs: 60_000, max: 1000 }),
};

describe('GET /player', () => {
  it('lists one player newest first, with rank, best, and a single best mark', async () => {
    const ada = uuid();
    const bea = uuid();
    await withServer(async ({ port }) => {
      assert.equal((await postScore(port, { player_id: ada, name: 'Ada', score: 50 })).status, 201);
      assert.equal((await postScore(port, { player_id: bea, name: 'Bea', score: 10 })).status, 201);
      assert.equal((await postScore(port, { player_id: bea, name: 'Bea', score: 40 })).status, 201);

      const board = await request(port, 'GET', '/v1/leaderboard?limit=10');
      const beaEntry = board.json.entries.find((entry) => entry.name === 'Bea');
      assert.equal(beaEntry.player_id, bea);
      assert.equal(beaEntry.rank, 2);
      assert.equal(beaEntry.score, 40);

      const home = await getHtml(port, '/');
      assert.match(home.text, /href="\/player\?name=Ada"/);
      assert.match(home.text, /href="\/player\?name=Bea"/);
      assert.equal(home.text.includes(ada), false);
      assert.equal(home.text.includes(bea), false);

      const page = await getHtml(port, playerPath('bea'));
      assert.equal(page.status, 200);
      assert.match(page.headers.get('content-type') ?? '', /text\/html.*charset=utf-8/i);
      assert.equal(page.headers.get('cache-control'), 'no-store');
      assert.match(page.text, /<h1>Bea<\/h1>/);
      assert.doesNotMatch(page.text, /<img\b/);
      assert.match(page.text, new RegExp(`BEST ${beaEntry.score}`));
      assert.match(page.text, new RegExp(arcadeOrdinal(beaEntry.rank)));
      assert.match(page.text, /2 GAMES/);
      assert.match(page.text, /showing 2 of 2/);
      assert.match(page.text, /href="\/"/);
      assert.equal(page.text.includes(bea), false);
      assert.equal(page.text.includes(ada), false);
      assert.equal(page.text.includes('fonts.googleapis.com'), false);
      assert.equal(page.text.includes('fonts.gstatic.com'), false);

      const rows = gameRows(page.text);
      assert.deepEqual(rows.map((row) => row.score), ['40', '10']);
      assert.deepEqual(rows.map((row) => row.mark), ['BEST', '']);
      assert.equal(rows.filter((row) => row.best).length, 1);
      for (const row of rows) {
        assert.match(row.at, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC$/);
        assert.match(row.datetime, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
      }
      const stamps = rows.map((row) => row.at);
      assert.deepEqual(stamps, [...stamps].sort().reverse());
      const shown = applyBrowserTimes(page.text);
      assert.deepEqual(shown, rows.map((row) => browserDateTime(row.datetime)));
      assert.equal(shown.some((text) => text.includes('UTC')), false);

      const adaPage = await getHtml(port, playerPath('Ada'));
      assert.match(adaPage.text, /1 GAME/);
      assert.doesNotMatch(adaPage.text, /1 GAMES/);
      assert.deepEqual(gameRows(adaPage.text).map((row) => row.score), ['50']);
      assert.equal(adaPage.text.includes(ada), false);
    });
  });

  it('marks the earliest best once when two games tie', async () => {
    const id = uuid();
    await withServer(async ({ port }) => {
      assert.equal((await postScore(port, { player_id: id, name: 'Tie', score: 10 })).status, 201);
      assert.equal((await postScore(port, { player_id: id, name: 'Tie', score: 10 })).status, 201);
      assert.equal((await postScore(port, { player_id: id, name: 'Tie', score: 5 })).status, 201);

      const page = await getHtml(port, playerPath('Tie'));
      const rows = gameRows(page.text);
      assert.deepEqual(rows.map((row) => row.score), ['5', '10', '10']);
      const marked = rows.filter((row) => row.mark === 'BEST');
      assert.equal(marked.length, 1);
      assert.equal(marked[0].score, '10');
      const tens = rows.filter((row) => row.score === '10');
      assert.equal(tens[1].mark, 'BEST');
      assert.equal(tens[0].mark, '');
      assert.equal(marked[0].at <= tens[0].at, true);
      assert.equal(page.text.includes(id), false);
    });
  });

  it('shows at most 100 newest games and the real total', async () => {
    const id = uuid();
    await withServer(async ({ port }) => {
      for (let score = 1; score <= 105; score += 1) {
        const posted = await postScore(port, { player_id: id, name: 'Bulk', score });
        assert.equal(posted.status, 201, `score ${score}`);
      }

      const page = await getHtml(port, playerPath('Bulk'));
      assert.equal(page.status, 200);
      const rows = gameRows(page.text);
      assert.equal(rows.length, 100);
      assert.equal(rows[0].score, '105');
      assert.equal(rows[0].mark, 'BEST');
      assert.equal(rows[99].score, '6');
      assert.equal(rows.filter((row) => row.mark === 'BEST').length, 1);
      assert.equal(rows.some((row) => row.score === '5'), false);
      assert.equal(rows.some((row) => row.score === '1'), false);
      const scores = rows.map((row) => Number(row.score));
      assert.deepEqual(scores, [...scores].sort((a, b) => b - a));
      assert.match(page.text, /showing 100 of 105/);
      assert.match(page.text, /BEST 105/);
      assert.match(page.text, /105 GAMES/);
      assert.match(page.text, /1ST/);
      assert.equal(page.text.includes(id), false);
    }, wideLimiter);
  });

  it('keeps games posted under an earlier name on the current player page', async () => {
    const id = uuid();
    await withServer(async ({ port }) => {
      assert.equal((await postScore(port, { player_id: id, name: 'OldName', score: 500 })).status, 201);
      assert.equal((await postScore(port, { player_id: id, name: 'OldName', score: 100 })).status, 201);
      const profile = await putProfile(port, {
        player_id: id,
        name: 'NewName',
        avatar: 'bear_bounce',
      });
      assert.equal(profile.status, 200);
      assert.equal((await postScore(port, { player_id: id, name: 'NewName', score: 200 })).status, 201);

      const page = await getHtml(port, playerPath('NewName'));
      assert.equal(page.status, 200);
      assert.match(page.text, /<h1><img src="\/avatars\/bear_bounce\.png" alt="NewName">NewName<\/h1>/);
      assert.match(page.text, /BEST 500/);
      assert.match(page.text, /3 GAMES/);
      assert.match(page.text, /showing 3 of 3/);
      assert.deepEqual(gameRows(page.text).map((row) => row.score), ['200', '100', '500']);
      assert.deepEqual(gameRows(page.text).map((row) => row.mark), ['', '', 'BEST']);
      assert.equal(page.text.includes('OldName'), false);
      assert.equal(page.text.includes(id), false);
      assert.doesNotMatch(page.text, /src="https?:/);

      const viaOld = await getHtml(port, playerPath('OldName'));
      assert.equal(viaOld.status, 200);
      assert.match(viaOld.text, /<h1><img src="\/avatars\/bear_bounce\.png" alt="NewName">NewName<\/h1>/);
      assert.deepEqual(gameRows(viaOld.text).map((row) => row.score), ['200', '100', '500']);
      assert.equal(viaOld.text.includes(id), false);
    });
  });

  it('escapes a hostile name in the board link and on the player page', async () => {
    const id = uuid();
    const nasty = '<script> "&';
    const quoted = "O'Brien";
    await withServer(async ({ port }) => {
      assert.equal((await postScore(port, { player_id: id, name: nasty, score: 4800 })).status, 201);
      assert.equal((await postScore(port, { player_id: uuid(), name: quoted, score: 12 })).status, 201);

      const home = await getHtml(port, '/');
      assert.equal(home.text.includes(nasty), false);
      assert.equal(home.text.includes(id), false);
      assert.match(home.text, /&lt;script&gt; &quot;&amp;/);
      assert.match(home.text, new RegExp(`href="/player\\?name=${encodeURIComponent(nasty)}"`));
      assert.match(home.text, /href="\/player\?name=O&#39;Brien"/);
      assert.equal(home.text.includes(`href="/player?name=O'Brien"`), false);
      assert.doesNotMatch(home.text, /<script/i);

      const page = await getHtml(port, playerPath(nasty));
      assert.equal(page.status, 200);
      assert.equal(page.text.includes(nasty), false);
      assert.equal(page.text.includes(id), false);
      assert.match(page.text, /&lt;script&gt; &quot;&amp;/);
      assert.match(page.text, /<title>&lt;script&gt; &quot;&amp; - Squishy Leaderboard<\/title>/);
      const scripts = [...page.text.matchAll(/<script>([\s\S]*?)<\/script>/g)];
      assert.equal(scripts.length, 1);
      assert.equal(scripts[0][1].includes(nasty), false);
      assert.equal(scripts[0][1].includes('alert'), false);
      assert.match(scripts[0][1], /querySelectorAll\("time\[datetime\]"\)/);
      assert.match(scripts[0][1], /textContent/);

      const quotePage = await getHtml(port, playerPath(quoted));
      assert.equal(quotePage.status, 200);
      assert.match(quotePage.text, />O&#39;Brien</);
      assert.equal(quotePage.text.includes("O'Brien"), false);
      assert.equal(quotePage.text.includes(quoted), false);
    });
  });

  it('404s an unknown hostile name without writing, and escapes it', async () => {
    const nasty = '<bad> "&';
    await withFile(async (file) => {
      initEmpty(file);
      await withServer(async ({ port }) => {
        const installed = snapshot(file);
        assert.ok(installed.indexSql);
        const db = new DatabaseSync(file);
        db.exec('DROP INDEX profiles_name_key');
        db.close();
        const before = snapshot(file);
        assert.equal(before.indexSql, null);
        assert.equal(before.profiles.length, 0);
        assert.equal(before.scores.length, 0);

        const routes = ['/player', '/player?name=', '/player?name=%20%20', playerPath('Nobody')];
        for (const route of routes) {
          const res = await getHtml(port, route);
          assert.equal(res.status, 404, route);
          assert.match(res.text, /NO SUCH PLAYER/);
          assert.match(res.text, /href="\/"/);
          assert.match(res.headers.get('content-type') ?? '', /text\/html/i);
          assert.doesNotMatch(res.text, /<script/i);
        }

        const hostile = await getHtml(port, playerPath(nasty));
        assert.equal(hostile.status, 404);
        assert.equal(hostile.text.includes(nasty), false);
        assert.match(hostile.text, /&lt;bad&gt; &quot;&amp;/);
        assert.match(hostile.text, /href="\/"/);

        const bad = await getHtml(port, `/player?name=${encodeURIComponent('bad\nname')}`);
        assert.equal(bad.status, 400);
        assert.match(bad.text, /BAD NAME/);
        assert.match(bad.text, /href="\/"/);
        assert.equal(bad.text.includes('bad\nname'), false);
        assert.doesNotMatch(bad.text, /<script/i);

        assert.deepEqual(snapshot(file), before);
      }, { dbPath: file, key: KEY });
    });
  });

  it('404s an ambiguous name, writes nothing, and hides both player ids', async () => {
    await withFile(async (file) => {
      seedAmbiguous(file);
      await withServer(async ({ port }) => {
        const before = snapshot(file);
        assert.equal(before.profiles.length, 2);
        assert.equal(before.scores.length, 0);

        const res = await getHtml(port, playerPath('Dad'));
        assert.equal(res.status, 404);
        assert.match(res.text, /NO SUCH PLAYER/);
        assert.match(res.text, /href="\/"/);
        assert.equal(res.text.includes(DAD_A), false);
        assert.equal(res.text.includes(DAD_B), false);
        assert.deepEqual(snapshot(file), before);
      }, { dbPath: file, key: KEY });
    });
  });

  it('a held name that is only clamped, and an over-long unknown name, never 500', async () => {
    const id = uuid();
    const name16 = 'ABCDEFGHIJKLMNOP';
    await withServer(async ({ port }) => {
      assert.equal((await postScore(port, { player_id: id, name: name16, score: 7 })).status, 201);
      const found = await getHtml(port, playerPath(`${name16}ZZZZ`));
      assert.equal(found.status, 200);
      assert.match(found.text, new RegExp(`<h1>${name16}</h1>`));
      assert.equal(found.text.includes(id), false);

      const missing = await getHtml(port, playerPath('Z'.repeat(20)));
      assert.equal(missing.status, 404);
      assert.match(missing.text, /NO SUCH PLAYER/);
    });
  });

  it('a profile with no games is a page, not a new player, and omits the id', async () => {
    await withServer(async ({ port }) => {
      const claimed = await request(port, 'POST', '/v1/players/resolve', { body: { name: 'Ghost' } });
      assert.equal(claimed.status, 201);
      const page = await getHtml(port, playerPath('Ghost'));
      assert.equal(page.status, 200);
      assert.match(page.text, /<h1>Ghost<\/h1>/);
      assert.match(page.text, /BEST NONE/);
      assert.match(page.text, /UNRANKED/);
      assert.match(page.text, /0 GAMES/);
      assert.match(page.text, /showing 0 of 0/);
      assert.match(page.text, /No games yet/);
      assert.equal(page.text.includes(claimed.json.player_id), false);
      assert.doesNotMatch(page.text, /<img\b/);
      assert.doesNotMatch(page.text, /<script/i);
    });
  });

  it('shows the browser local date and time, and refuses a hostile timestamp', () => {
    const iso = '2026-01-15T20:05:06.000Z';
    const html = renderPlayer({
      name: 'Ada',
      best: 40,
      rank: 1,
      total: 1,
      games: [{ at: iso, score: 40, best: true }],
    });
    assert.match(html, /<time datetime="2026-01-15T20:05:06.000Z">2026-01-15 20:05:06 UTC<\/time>/);
    assert.deepEqual(applyBrowserTimes(html), [browserDateTime(iso)]);
    assert.equal(browserDateTime(iso, 'America/Los_Angeles').includes('UTC'), false);
    assert.notEqual(browserDateTime(iso, 'America/Los_Angeles'), browserDateTime(iso, 'UTC'));
    assert.notEqual(browserDateTime(iso, 'Asia/Tokyo'), browserDateTime(iso, 'UTC'));
    assert.notEqual(browserDateTime('2026-07-15T20:05:06.000Z', 'America/Los_Angeles'), browserDateTime('2026-07-15T20:05:06.000Z', 'UTC'));

    const winter = new Date(iso);
    const laHour = new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/Los_Angeles',
      hour: 'numeric',
      hourCycle: 'h23',
    }).format(winter);
    const tokyoDay = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Tokyo',
      day: 'numeric',
    }).format(winter);
    assert.equal(laHour, '12');
    assert.equal(tokyoDay, '16');
    assert.match(browserDateTime(iso, 'America/Los_Angeles'), /12:05:06/);
    assert.match(browserDateTime(iso, 'Asia/Tokyo'), /\b16\b/);

    const hostile = renderPlayer({
      name: 'Ada',
      best: 1,
      rank: 1,
      total: 1,
      games: [{ at: '"><script>alert(1)</script>', score: 1, best: false }],
    });
    assert.equal(hostile.includes('<script'), false);
    assert.equal(hostile.includes('<time'), false);
    assert.match(hostile, /&lt;script&gt;alert\(1\)&lt;\/script&gt; UTC/);
  });

  it('shares the lookup limiter; the 61st request from one IP is 429 HTML', async () => {
    await withServer(async ({ port }) => {
      const bad = await getHtml(port, `/player?name=${encodeURIComponent('a\nb')}`);
      const allowed = await getHtml(port, playerPath('Nope'));
      assert.equal(bad.status, 400);
      assert.equal(allowed.status, 404);
    }, { resolveLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }) });

    await withServer(async ({ port }) => {
      const first = await getHtml(port, playerPath('Nope'));
      const lookup = await request(port, 'GET', `/v1/players/lookup?name=${encodeURIComponent('Nope')}`);
      assert.equal(first.status, 404);
      assert.equal(lookup.status, 429);
      assert.equal(lookup.json.error, 'rate_limited');
    }, { resolveLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }) });

    await withServer(async ({ port }) => {
      for (let i = 0; i < 60; i += 1) {
        const res = await getHtml(port, playerPath('Nope'));
        assert.equal(res.status, 404, `request ${i + 1}`);
      }
      const blocked = await getHtml(port, playerPath('Nope'));
      assert.equal(blocked.status, 429);
      assert.match(blocked.headers.get('content-type') ?? '', /text\/html/i);
      assert.equal(blocked.headers.get('cache-control'), 'no-store');
      assert.match(blocked.text, /TOO MANY REQUESTS/);
      assert.match(blocked.text, /href="\/"/);
      assert.doesNotMatch(blocked.text, /<script/i);
      assert.equal(blocked.text.trimStart().startsWith('{'), false);
      assert.equal(blocked.text.includes('fonts.googleapis.com'), false);
    });
  });
});
