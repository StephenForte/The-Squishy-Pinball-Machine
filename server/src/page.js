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
 * HTML board. Inline CSS, no scripts, no third-party requests (D-026 / D-037).
 * Press Start 2P is embedded as the pixel face (D-061); a monospace stack is
 * the fallback. Same-origin /avatars/<id>.png images only, and only when
 * avatar is set. RANK / NAME / SCORE; no relative-time column.
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
<style>
/* Press Start 2P (c) 2012 Cody Boisclair, SIL Open Font License 1.1. Embedded so the page stays self-contained. */
@font-face{font-family:"Press Start 2P";font-style:normal;font-weight:400;font-display:swap;src:url(data:font/woff2;base64,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) format("woff2");unicode-range:U+0460-052F, U+1C80-1C8A, U+20B4, U+2DE0-2DFF, U+A640-A69F, U+FE2E-FE2F}
@font-face{font-family:"Press Start 2P";font-style:normal;font-weight:400;font-display:swap;src:url(data:font/woff2;base64,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) format("woff2");unicode-range:U+0301, U+0400-045F, U+0490-0491, U+04B0-04B1, U+2116}
@font-face{font-family:"Press Start 2P";font-style:normal;font-weight:400;font-display:swap;src:url(data:font/woff2;base64,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) format("woff2");unicode-range:U+0370-0377, U+037A-037F, U+0384-038A, U+038C, U+038E-03A1, U+03A3-03FF}
@font-face{font-family:"Press Start 2P";font-style:normal;font-weight:400;font-display:swap;src:url(data:font/woff2;base64,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) format("woff2");unicode-range:U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF}
@font-face{font-family:"Press Start 2P";font-style:normal;font-weight:400;font-display:swap;src:url(data:font/woff2;base64,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) format("woff2");unicode-range:U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD}
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
