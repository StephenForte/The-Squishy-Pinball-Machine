import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { describe, it } from 'node:test';

const MINIMUM = [26, 12, 1];

function parts(text) {
  const match = String(text).trim().match(/^(\d+)\.(\d+)\.(\d+)$/);
  assert.ok(match, `expected a major.minor.patch pin, got ${JSON.stringify(text)}`);
  return match.slice(1, 4).map(Number);
}

function atLeast(version, minimum) {
  for (let i = 0; i < minimum.length; i += 1) {
    if (version[i] > minimum[i]) return true;
    if (version[i] < minimum[i]) return false;
  }
  return true;
}

describe('Node pin', () => {
  it('requires 26.12.1 or newer and stays on Node 26', () => {
    const root = readFileSync(new URL('../../.node-version', import.meta.url), 'utf8');
    const server = readFileSync(new URL('../.node-version', import.meta.url), 'utf8');
    assert.equal(server.trim(), root.trim());

    const pinned = parts(root);
    assert.equal(pinned[0], 26, `.node-version ${root.trim()} is not Node 26`);
    assert.ok(
      atLeast(pinned, MINIMUM),
      `.node-version ${root.trim()} is below 26.12.1`,
    );

    const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
    const lock = JSON.parse(readFileSync(new URL('../package-lock.json', import.meta.url), 'utf8'));
    const engines = `>=${root.trim()} <27`;
    assert.equal(pkg.engines.node, engines);
    assert.equal(lock.packages[''].engines.node, engines);
  });

  it('can still open a database with DatabaseSync', () => {
    const db = new DatabaseSync(':memory:');
    try {
      const row = db.prepare('SELECT 1 AS ok').get();
      assert.equal(row.ok, 1);
    } finally {
      db.close();
    }
  });
});
