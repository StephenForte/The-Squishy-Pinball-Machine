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
    assert.equal(relativeTime('2026-09-08T16:00:00.000Z', now), '2 hours ago');
    assert.equal(relativeTime('2026-09-06T18:00:00.000Z', now), '2 days ago');
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
      assert.equal(ranks[0], '1');
      assert.match(res.text, /11 players/);
      assert.match(res.text, />9000</);
      for (let i = 0; i < 10; i += 1) {
        assert.equal(names[i], json.json.entries[i].name);
        assert.equal(Number(ranks[i]), json.json.entries[i].rank);
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
    });
  });
});
