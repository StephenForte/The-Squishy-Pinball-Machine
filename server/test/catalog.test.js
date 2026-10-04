import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import {
  createCatalog,
  DEFAULT_REPO_ROOT,
  resolveSpritePath,
} from '../src/catalog.js';

describe('resolveSpritePath', () => {
  it('maps a res:// sprite onto a path inside the checkout', () => {
    const resolved = resolveSpritePath({
      assets: { sprite: 'res://assets/design/squishes/art/bear_bounce.png' },
    });
    assert.ok(resolved);
    assert.ok(resolved.startsWith(DEFAULT_REPO_ROOT));
    assert.ok(resolved.endsWith('/assets/design/squishes/art/bear_bounce.png'));
  });

  it('rejects missing, empty, non-res, and escaping paths', () => {
    assert.equal(resolveSpritePath({}), null);
    assert.equal(resolveSpritePath({ assets: { sprite: '' } }), null);
    assert.equal(resolveSpritePath({ assets: { sprite: 'https://evil.example/x.png' } }), null);
    assert.equal(resolveSpritePath({ assets: { sprite: 'res://' } }), null);
    assert.equal(resolveSpritePath({ assets: { sprite: 'res:///etc/passwd' } }), null);
    assert.equal(
      resolveSpritePath({ assets: { sprite: 'res://../server/package.json' } }),
      null,
    );
    assert.equal(
      resolveSpritePath({ assets: { sprite: 'res://assets/design/squishes/art/\0x.png' } }),
      null,
    );
  });
});

describe('createCatalog', () => {
  it('loads the shipped catalog and answers has/pathFor for a real id', () => {
    const catalog = createCatalog();
    assert.ok(catalog.ids().includes('bear_bounce'));
    assert.equal(catalog.has('bear_bounce'), true);
    assert.equal(catalog.has('not_a_squishy'), false);
    assert.equal(catalog.has(''), false);
    const path = catalog.pathFor('bear_bounce');
    assert.ok(path);
    assert.ok(path.endsWith('/assets/design/squishes/art/bear_bounce.png'));
    assert.equal(catalog.pathFor('not_a_squishy'), null);
  });

  it('skips blank ids and still boots when the JSON is unreadable', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'squish-catalog-unit-'));
    try {
      const catalogPath = join(dir, 'catalog.json');
      await writeFile(
        catalogPath,
        JSON.stringify({
          squishies: [
            { id: '', assets: { sprite: 'res://assets/design/squishes/art/bear_bounce.png' } },
            { id: 'ok_id', assets: { sprite: 'res://assets/design/squishes/art/bear_bounce.png' } },
            null,
          ],
        }),
      );
      const catalog = createCatalog({ catalogPath, repoRoot: DEFAULT_REPO_ROOT });
      assert.deepEqual(catalog.ids(), ['ok_id']);
      assert.equal(catalog.has(''), false);

      const brokenPath = join(dir, 'broken.json');
      await writeFile(brokenPath, '{not json');
      const broken = createCatalog({ catalogPath: brokenPath, repoRoot: DEFAULT_REPO_ROOT });
      assert.deepEqual(broken.ids(), []);
      assert.equal(broken.has('bear_bounce'), false);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
