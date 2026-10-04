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

/**
 * Relative-time labels. The arcade board no longer shows them (D-061); the
 * helper stays so existing callers and tests keep a stable result.
 */
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

/** Arcade ordinal. Ties keep the rank the data already assigned. */
function ordinalRank(rank) {
  if (rank === null || rank === undefined || rank === '') return '';
  const n = typeof rank === 'number' ? rank : Number(String(rank).trim());
  if (!Number.isInteger(n)) return String(rank);
  const abs = Math.abs(n);
  const mod100 = abs % 100;
  let suffix = 'TH';
  if (mod100 < 11 || mod100 > 13) {
    const mod10 = abs % 10;
    if (mod10 === 1) suffix = 'ST';
    else if (mod10 === 2) suffix = 'ND';
    else if (mod10 === 3) suffix = 'RD';
  }
  return `${n}${suffix}`;
}

function avatarImg(row) {
  const avatar = typeof row.avatar === 'string' ? row.avatar : '';
  if (!avatar) return '';
  const src = escapeHtml(`/avatars/${avatar}.png`);
  const alt = escapeHtml(row.name ?? '');
  return `<img src="${src}" alt="${alt}">`;
}

function rowsHtml(entries) {
  const rows = Array.isArray(entries) ? entries.slice(0, 10) : [];
  if (rows.length === 0) {
    return '<p class="empty">No scores yet</p>';
  }

  const body = rows
    .map((row) => {
      const rank = escapeHtml(ordinalRank(row.rank));
      const name = escapeHtml(row.name ?? '');
      const score = escapeHtml(row.score ?? '');
      return `<tr><td class="rank">${rank}</td><td class="name">${avatarImg(row)}${name}</td><td class="score">${score}</td></tr>`;
    })
    .join('');

  return `<table>
      <thead><tr><th class="rank">RANK</th><th class="name">NAME</th><th class="score">SCORE</th></tr></thead>
      <tbody>${body}</tbody>
    </table>`;
}

/**
 * HTML board. Inline CSS, no scripts (D-026 / D-037).
 * Press Start 2P is the pixel face (D-061); a monospace stack is the fallback
 * when that stylesheet is blocked. Same-origin /avatars/<id>.png images only,
 * and only when avatar is set. RANK / NAME / SCORE; no relative-time column.
 */
export function renderBoard({ entries = [], total_players = 0 } = {}) {
  const count = escapeHtml(playerCountLabel(total_players));
  const board = rowsHtml(entries);

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Squishy Leaderboard</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Press+Start+2P&amp;display=swap">
<style>
:root{--bg:#000000;--cyan:#16CFE0;--pink:#FF2BD6;--gold:#FFD21C;--text:#F4FFF8;--muted:#8DFFE0}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%;background:var(--bg);color:var(--text);font-family:"Press Start 2P",ui-monospace,"Courier New",monospace;font-size:8px;line-height:1.7}
body{background-image:repeating-linear-gradient(to bottom,rgba(255,255,255,.035),rgba(255,255,255,.035) 1px,transparent 1px,transparent 3px)}
main{max-width:48rem;margin:0 auto;padding:1.5rem .75rem 2.5rem}
h1{margin:0 0 1.1rem;font-size:16px;line-height:1.6;text-align:center;color:var(--gold);text-shadow:0 0 10px var(--gold);animation:arcade-blink 1.2s steps(2,end) infinite}
@keyframes arcade-blink{0%,49%{opacity:1}50%,100%{opacity:.4}}
.meta{margin:0 0 1.4rem;text-align:center;color:var(--cyan)}
.meta a{color:var(--pink)}
table{width:100%;border-collapse:collapse;table-layout:fixed;border:2px solid var(--cyan);box-shadow:0 0 12px rgba(22,207,224,.4)}
th,td{padding:.7rem .35rem;text-align:left;vertical-align:middle}
th{color:var(--cyan);font-size:.85rem;border-bottom:2px solid var(--pink)}
td.rank,th.rank{width:6rem;color:var(--gold);white-space:nowrap}
td.score,th.score{width:9rem;text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap;color:var(--text)}
td.name{overflow-wrap:anywhere}
td.name img{display:inline-block;width:1.75rem;height:1.3rem;max-width:100%;object-fit:contain;vertical-align:middle;margin-right:.4rem}
tbody tr:nth-child(even) td{background:rgba(22,207,224,.06)}
.empty{margin:0;padding:1.4rem 1rem;text-align:center;color:var(--muted);border:2px solid var(--pink);box-shadow:0 0 12px rgba(255,43,214,.35)}
@media (min-width:480px){
  html,body{font-size:12px}
  h1{font-size:28px}
  main{padding:2.2rem 1.25rem 3rem}
}
@media (prefers-reduced-motion: reduce){
  *,*::before,*::after{animation:none !important}
}
</style>
</head>
<body>
<main>
<h1>HIGH SCORES</h1>
<p class="meta">${count} · <a href="/v1/leaderboard">JSON</a></p>
${board}
</main>
</body>
</html>
`;
}
