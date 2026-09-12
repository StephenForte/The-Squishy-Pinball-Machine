import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
/** Repo root: server/src → server → checkout. D-028 ships the whole repo. */
export const DEFAULT_REPO_ROOT = resolve(MODULE_DIR, '..', '..');
export const DEFAULT_CATALOG_PATH = join(
  DEFAULT_REPO_ROOT,
  'assets',
  'design',
  'squishes',
  'squishies_catalog.json',
);
export const DEFAULT_ART_DIR = join(
  DEFAULT_REPO_ROOT,
  'assets',
  'design',
  'squishes',
  'art',
);

const logged = new Set();

function logOnce(message) {
  if (logged.has(message)) return;
  logged.add(message);
  console.error(message);
}

function insideRoot(resolved, root) {
  const base = resolve(root);
  if (resolved === base) return true;
  const prefix = base.endsWith(sep) ? base : base + sep;
  return resolved.startsWith(prefix);
}

/**
 * Build a filesystem path from the catalogued `assets.sprite` (res://…),
 * never from a URL segment. Returns null if the sprite is missing or escapes
 * the checkout.
 */
export function resolveSpritePath(entry, repoRoot = DEFAULT_REPO_ROOT) {
  const sprite = entry?.assets && typeof entry.assets.sprite === 'string' ? entry.assets.sprite : '';
  if (!sprite.startsWith('res://')) return null;
  const rel = sprite.slice('res://'.length);
  if (rel === '' || rel.startsWith('/') || rel.includes('\0')) return null;
  const resolved = resolve(repoRoot, rel);
  if (!insideRoot(resolved, repoRoot)) return null;
  return resolved;
}

/**
 * Load the D-020 squishy catalog. A missing file or art directory must not
 * throw — the server still boots (D-037).
 */
export function createCatalog(options = {}) {
  const repoRoot = resolve(options.repoRoot ?? DEFAULT_REPO_ROOT);
  const catalogPath = options.catalogPath ?? join(
    repoRoot,
    'assets',
    'design',
    'squishes',
    'squishies_catalog.json',
  );
  const artDir = join(repoRoot, 'assets', 'design', 'squishes', 'art');

  const byId = new Map();

  if (!existsSync(catalogPath)) {
    logOnce(
      `squish catalog not found at ${catalogPath}; non-empty avatars rejected, board serves without avatars`,
    );
  } else {
    try {
      const data = JSON.parse(readFileSync(catalogPath, 'utf8'));
      const list = Array.isArray(data.squishies) ? data.squishies : [];
      for (const entry of list) {
        if (!entry || typeof entry.id !== 'string' || entry.id === '') continue;
        byId.set(entry.id, {
          id: entry.id,
          path: resolveSpritePath(entry, repoRoot),
        });
      }
    } catch (err) {
      logOnce(
        `squish catalog unreadable at ${catalogPath}: ${err.message}; non-empty avatars rejected`,
      );
    }
  }

  if (!existsSync(artDir) || !statSync(artDir).isDirectory()) {
    logOnce(`squish art directory missing at ${artDir}; /avatars returns 404`);
  }

  return {
    has(id) {
      return typeof id === 'string' && byId.has(id);
    },
    ids() {
      return [...byId.keys()];
    },
    pathFor(id) {
      if (!byId.has(id)) return null;
      return byId.get(id).path;
    },
  };
}
