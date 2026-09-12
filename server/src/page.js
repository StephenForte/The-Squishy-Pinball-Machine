const ESCAPE = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

/** Escape every interpolated value. Names are user input and may contain markup. */
export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (ch) => ESCAPE[ch]);
}

export function relativeTime(iso, now = Date.now()) {
  const then = Date.parse(iso);
  if (!Number.isFinite(then)) return 'just now';
  const seconds = Math.max(0, Math.floor((now - then) / 1000));
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return minutes === 1 ? '1 minute ago' : `${minutes} minutes ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return hours === 1 ? '1 hour ago' : `${hours} hours ago`;
  const days = Math.floor(hours / 24);
  return days === 1 ? '1 day ago' : `${days} days ago`;
}

function playerCountLabel(total) {
  const n = Number.isFinite(Number(total)) ? Number(total) : 0;
  return n === 1 ? '1 player' : `${n} players`;
}

function avatarImg(row) {
  const avatar = typeof row.avatar === 'string' ? row.avatar : '';
  if (!avatar) return '';
  const src = escapeHtml(`/avatars/${avatar}.png`);
  const alt = escapeHtml(row.name ?? '');
  return `<img src="${src}" alt="${alt}">`;
}

function rowsHtml(entries, now) {
  const rows = Array.isArray(entries) ? entries.slice(0, 10) : [];
  if (rows.length === 0) {
    return '<p class="empty">No scores yet</p>';
  }

  const body = rows
    .map((row) => {
      const rank = escapeHtml(row.rank ?? '');
      const name = escapeHtml(row.name ?? '');
      const score = escapeHtml(row.score ?? '');
      const when = escapeHtml(relativeTime(row.at, now));
      return `<tr><td class="rank">${rank}</td><td class="name">${avatarImg(row)}${name}</td><td class="score">${score}</td><td class="when">${when}</td></tr>`;
    })
    .join('');

  return `<table>
      <thead><tr><th>Rank</th><th>Name</th><th>Score</th><th>When</th></tr></thead>
      <tbody>${body}</tbody>
    </table>`;
}

/**
 * HTML board. Inline CSS, no scripts, no third-party assets (D-026 / D-037).
 * Same-origin /avatars/<id>.png images only, and only when avatar is set.
 * Colours are the neon_candy_baseline hex values, hard-coded.
 */
export function renderBoard({ entries = [], total_players = 0 } = {}, now = Date.now()) {
  const count = escapeHtml(playerCountLabel(total_players));
  const board = rowsHtml(entries, now);

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Squishy Leaderboard</title>
<style>
:root{--bg:#080B45;--panel:#19145E;--mid:#30207A;--cyan:#16CFE0;--pink:#FF5D73;--gold:#FFD21C;--text:#FFFFFF;--muted:#C5C0EE}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%;background:var(--bg);color:var(--text);font-family:ui-sans-serif,system-ui,sans-serif;font-size:16px;line-height:1.4}
main{max-width:40rem;margin:0 auto;padding:1.25rem 1rem 2rem}
h1{margin:0 0 .4rem;font-size:1.6rem;color:var(--gold)}
.meta{margin:0 0 1.1rem;color:var(--muted)}
.meta a{color:var(--cyan)}
table{width:100%;border-collapse:collapse;background:var(--panel);border-radius:.75rem;overflow:hidden}
th,td{padding:.65rem .55rem;text-align:left;vertical-align:top}
th{background:var(--mid);color:var(--cyan);font-size:.75rem;text-transform:uppercase;letter-spacing:.04em}
td.rank{width:3rem;font-weight:700;color:var(--pink)}
td.score{font-variant-numeric:tabular-nums;white-space:nowrap}
td.when{color:var(--muted);font-size:.85rem}
td.name{word-break:break-word}
td.name img{display:inline-block;width:1.75rem;height:1.3rem;object-fit:contain;vertical-align:middle;margin-right:.45rem}
tbody tr:nth-child(even) td{background:rgba(48,32,122,.4)}
.empty{margin:0;padding:1.4rem 1rem;background:var(--panel);border-radius:.75rem;color:var(--muted)}
</style>
</head>
<body>
<main>
<h1>Squishy Leaderboard</h1>
<p class="meta">${count} · <a href="/v1/leaderboard">JSON</a></p>
${board}
</main>
</body>
</html>
`;
}
