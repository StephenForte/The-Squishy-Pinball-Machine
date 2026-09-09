# The Squishy Pinball Machine — Build Plan

Source of truth for task breakdown, ownership, and status. Planner updates this file;
workers never edit it. Companion: [DECISIONS.md](DECISIONS.md) (numbered, append-only).

**Engine:** Godot 4.x / GDScript / 2D physics (see D-001, D-002).
**Repo:** https://github.com/StephenForte/The-Squishy-Pinball-Machine

## Status

| ID | Task | Phase | Status | Model tier | Depends on |
|----|------|-------|--------|------------|------------|
| T1 | Project scaffold | 0/1 | merged 2026-09-02 (PR #1 → a9d3e35) | cheap (Sonnet) | — |
| T2 | Table, ball, launcher, drain | 1 | merged 2026-09-02 (PR #2 → 784740f); Steve play-tested ✓ | strong (Opus+) | T1 |
| T3 | Flippers + controls | 2 | merged 2026-09-03 (PR #5) | strong (Opus+) | T2 |
| T4 | Game flow: 3 balls, restart | 2 | merged 2026-09-02 (PR #3) | mid | T2 (not T3) |
| T5 | Bumpers, targets, scoring | 3 | merged 2026-09-03 (PR #8) | mid | T3, T4 |
| T6 | HUD, game over, high score | 3 | merged 2026-09-03 (PR #7); Steve play-tested ✓ | mid | T4 |
| T3.1 | Flipper-base trap pocket (V1 blocker) | 2 fix | merged 2026-09-03 (PR #9) | mid | T5 merged |
| T7a | Streak scoring, screen shake, big-score moment | 4 | merged 2026-09-03 (PR #10); play-tested ✓ streak works | mid-strong | T3.1 |
| T7b | Title screen + instructions | 4 | merged 2026-09-03 (PR #11) | cheap | T7a |
| T7c | Sound effects | 4 | merged 2026-09-03 (PR #13) | mid | T7a |
| T7d | Tuning: stronger shake, more flipper power (D-019) | 4 | merged 2026-09-03 (PR #12) | cheap | T7a |
| T8.0 | Commit design catalogs (assets/design) | 4 | merged 2026-09-04 (PR #14) | — | — |
| T8 | Squishy art + theme pass (data-driven, D-020) | 4 | merged 2026-09-04 (PR #15); Steve: art OK for now | strong | T8.0 |
| T10 | Hit-surface fix: 5 round targets under sprites + flipper +10% (D-022/D-023) | 4 fix | merged 2026-09-05 (PR #16) | mid-strong | T8 |
| T9 | Test isolation: tests must not touch the real user:// dir (D-025) | hygiene | merged 2026-09-06 (PR #17) | cheap | — |
| T11 | Leaderboard server (`server/`, Node 24 + SQLite via node:sqlite, D-026) | 5 | merged 2026-09-08 (PR #18) | mid | — |
| T11.1 | Deploy to Render (Supa Workspace): Starter web service + 1 GB disk; record D-028 | 5 | done 2026-09-08 — live at https://squish-leaderboard.onrender.com | — | T11 |
| T12 | Player profile: name entry + device id (D-027) | 5 | merged 2026-09-07 (PR #19) | cheap-mid | — |
| T14 | QA round (Natasha): Back-to-menu + squishy texture self-heal (D-029) | 5 | merged 2026-09-08 (PR #20) | mid | T12 |
| T15 | Squishies never set up on real boot (D-030) + real-boot regression check | 4 fix | merged 2026-09-08 (PR #21) | cheap-mid | T14 |
| T13 | Client leaderboard: post on game over, show on title + game over (D-026/D-027/D-028) | 5 | merged 2026-09-09 (PR #22); Steve: score posted, works | mid-strong | T11.1, T12, T14 |
| T13b | Backlog: submit retry with backoff to ~60 s (survive a deploy window) | 5 | not started — only if scores get lost during deploys | cheap | T13 |
| T13a | Server: friendly HTML board at `/` (D-026 amended) | 5 | merged + deployed 2026-09-09 (PR #23); live | cheap | T11.1 |
| T16 | Per-name identity + per-player high score (D-031; fixes "Dad's score gone") | 5 fix | dispatched 2026-09-09 | mid | T13 |

**Run order:** T1 → T2 → (T3, T4) → T5 ∥ T6 → T3.1 → T7a → T7b ∥ T7c → T8 → T10 → T9 →
**Phase 5:** T11 ∥ T12 → T11.1 (deploy) → T13.
T5 and T6 are the only truly parallel pair; ownership below is drawn to keep them apart.

## Running the game after a pull

    godot --headless --import && godot --path .

Running the tests (never invoke `godot -s tests/...` directly — it hits your real saves):

    ./tests/run_all.sh            # everything, isolated user dir (D-025)
    ./tests/run_all.sh game_flow  # one suite

The import step is required whenever a merge adds assets (WAVs, images); `.import`
metadata is gitignored (D-008) and `godot --path .` does not import on its own. Skipping
it prints `No loader found for resource` for each new asset (seen 2026-09-03 after T7c).
Opening the project in the editor imports implicitly.

## Blockers / open items

- **Render push-triggered deploys do not happen.** Verified 2026-09-09: `get_service` shows
  autoDeploy=yes, trigger=commit, repo set, build filter `server/**` (Steve added it), yet a probe
  commit touching `server/README.md` (08150a6) produced no deploy after 3+ minutes, and no push
  since creation ever has. Cause not confirmed from here (my token cannot list GitHub App
  installations; Render uses an App, not a repo webhook). Leading hypothesis: service created via
  API from a public repo URL → Render's "public repo, no account link" mode, which has no push
  deploys. Steve to check dashboard → service → Settings → Repository: if it offers "Connect
  GitHub account"/"Configure GitHub App", do that and include this repo. Until confirmed working,
  the planner triggers deploys after server merges (connector `trigger_deploy`).

### T16 — One device, several players (Natasha QA, 2026-09-09)
Symptom: Dad set a high score; Natasha renamed via N and played; Dad's entry disappeared from
the shared board and the local HIGH showed her score. Cause (planner design, D-027/D-005): one
`player_id` per device, name is a label, server shows an id's latest name; local high score is a
single device value. Fix per D-031: identity = (device, name) → a UUID per name; local high score
per player id. Owns: `autoload/profile.gd`, `autoload/game.gd` (high-score storage + `high_score`
semantics), `project.godot` (autoload order if needed), `tests/profile_test.gd`,
`tests/game_flow.gd`, `tests/leaderboard_test.gd` (+cases). UI reads `Game.high_score` unchanged.

## Task details

### T1 — Project scaffold
Owns: `project.godot`, `.gitignore`, `icon.svg`, `scenes/main.tscn`, `scripts/main.gd`.
Creates the Godot project: viewport 720×1280 portrait, `canvas_items` stretch (D-003);
input map actions exactly as in D-004; empty Main scene that loads. Nothing else.

### T2 — Table, ball, launcher, drain (Phase 1 gate: playable physics)
Owns: `scenes/table.tscn`, `scenes/ball.tscn`, `scripts/table.gd`, `scripts/ball.gd`,
`scripts/launcher.gd`. May edit `scenes/main.tscn` to instance the table.
Walls as StaticBody2D, ball as RigidBody2D, launcher lane with Space-key impulse,
drain Area2D that calls `Game.on_ball_drained()` (stub OK until T4; emit a signal and
leave a `# wired in T4` note). Ball must never escape the playfield or tunnel through
walls at launch speed — that is the acceptance test.

### T3 — Flippers + controls
Owns: `scenes/flipper.tscn`, `scripts/flipper.gd`. May edit `scenes/table.tscn` only to
place two flipper instances. Uses input actions from D-004 (already defined in T1 —
do not add new ones). Tuning target: player can trap and aim the ball at least crudely.

### T3.1 — Flipper-base trap pocket (found in T5 review, pre-existing since T3)
Owns: `scenes/table.tscn` (additive: base-fill geometry) and/or `scenes/flipper.tscn` /
`scripts/flipper.gd`; `tests/flipper_test.gd` (add the regression). A ball can rest at the
flipper base between hub and guide-wall end and no flipping frees it. Reproduction (idle
flippers, `launcher.launch(imp)` from the lane, `--fixed-fps 120`): on main pre-T5,
impulses 1600/1750/1800 → rest at (252, 1107); with T5, 1700 → rest at (467, 1106);
30 double-flips leave it at speed 0. Acceptance: every idle launch 1500–1850 step 50
either drains within 3000 frames or is freed by one flip; ball never rests within 30 px
of either pivot. Blocks Version 1 "definition of done".

### T4 — Game flow
Owns: `autoload/game.gd` (autoload name `Game`), edits `scripts/main.gd`.
Implements the D-005 contract per D-011 wiring: 3 balls per game, drain → respawn or
game over, restart on R, high-score persistence. May edit `scripts/table.gd` ONLY to delete
the `# TEMP` respawn block (D-009); may add `[autoload]` to `project.godot`. Must not
touch `scenes/table.tscn` (T3 is editing it) or any T3/T5 file.

### T5 — Bumpers, targets, scoring
Owns: `scenes/bumper.tscn`, `scenes/target.tscn`, `scripts/bumper.gd`,
`scripts/target.gd`; edits `scenes/table.tscn` to place ≥3 bumpers + 3 targets.
Scoring values and all-targets bonus per D-005. **Must not edit `scenes/main.tscn`
or anything under `scenes/ui/`** — that is T6's territory.

### T6 — HUD, game over, high score
Owns: `scenes/ui/` (all), `scripts/ui/` (all); edits `scenes/main.tscn` to add the UI
layer. Score/balls display driven only by `Game` signals (D-005) — no references into
table or gameplay scenes. High score persisted at `user://highscore.save` (D-005).

### Phase 3 play-test (2026-09-03)
Natasha scored 4 800. Flippers responsive ✓, bumper value OK but wants a streak bonus,
squishy art/theme deferred to T8. Steve's first game scored 0 (didn't flip into bumpers).

### T7a — Streak scoring, screen shake, big-score moment
Owns: `autoload/game.gd` (additive: streak state + signals, D-017/D-018), `scripts/bumper.gd`
(additive: `hit` signal, streak call), `scenes/ui/hud.tscn` + `scripts/ui/hud.gd` (additive:
`StreakLabel`), new `scenes/effects.tscn` + `scripts/effects.gd` instanced in `table.tscn`
(additive), `tests/streak_test.gd`. Must not touch `main.tscn`/`main.gd` (T7b) or add audio (T7c).

### T7d — Tuning from play-test (shake + flipper power)
Owns: `scripts/effects.gd` (shake constants), `scripts/flipper.gd` (`UP_SPEED_DEG`),
`tests/flipper_test.gd` only if a threshold must move (report before/after). Values in D-019.
Parallel-safe with T7b/T7c (no shared files) but not in the same checkout.

### T7b — Title screen + instructions
Owns: `scenes/ui/title.tscn`, `scripts/ui/title.gd`, `tests/title_test.gd`; additive edits to
`scenes/main.tscn` and `scripts/main.gd`. Nothing under table/gameplay/autoload.

### T7c — Sound effects
Owns: `assets/sfx/*`, `autoload/sfx.gd` (autoload `Sfx`, `[autoload]` line in project.godot),
`tests/sfx_test.gd`. Listens to signals only (D-018); edits no gameplay or UI file.

### T8 — Squishy art + theme pass (data-driven)
Owns: `scripts/theme.gd` (autoload `Theme`), `scripts/squishy_catalog.gd`, `scenes/squishy.tscn` +
`scripts/squishy.gd`, `scenes/ui/theme_picker.tscn` + `scripts/ui/theme_picker.gd`,
`tools/slice_squishies.gd` + generated `assets/design/squishes/art/*.png`, `tests/theme_test.gd`.
Additive: `project.godot` (autoload line), `scenes/table.tscn` (swap placeholder visuals for
Squishy instances at D-015 positions — collision shapes untouched), all `scenes/ui/*.tscn`
(colours from Theme), `scenes/effects.tscn` (fireworks colours), `scenes/main.tscn` (picker).
Input: assets/design catalogs per D-020. See Phase-3/4 feedback: vibrant, themed, squishy.

### T10 — Squishies must be hittable where they are drawn (found in play 2026-09-05)
Steve: "some squishies the ball glides straight through". Planner repro (drop a ball on each
sprite): puppy_jax/peanut_pip are decor with no collider (0 pts, pass-through); frog_gus /
cosmo / lion_rumpus sprites sit (25,26) / (-19,31) / (0,72) px away from their 70×12 target
bars, so aiming at the squishy misses. T8 review missed this because physics was unchanged.
Fix per D-023: decor → TargetLeft2/TargetRight2 in the bank; every target's collider becomes a
circle centred on its sprite. Plus D-022 flipper +10 %. Owns: `scenes/table.tscn`,
`scenes/target.tscn`, `scripts/target.gd` (shape only), `scripts/flipper.gd`,
`assets/design/squishes/squishies_catalog.json` (`first_table_slots`, `v1_role` for the two),
`tests/scoring_test.gd`, `tests/theme_test.gd` (+ alignment/hit cases), `tests/flipper_test.gd`
only if a threshold must move. D-013 drain invariant and the BASE/TIP tests are the guards.

## Phase 5 — Shared leaderboard (decisions 2026-09-07)
Hosting: Render, Supa Workspace (`tea-d98533l7vvec738vva90`), one web service with a persistent
disk holding a SQLite file (Steve chose SQLite over Postgres 2026-09-07; ~$7/mo Starter instance +
~$0.25/mo disk, prices to be confirmed at T11.1). Identity: name entered in-game,
saved locally, plus a random per-device id; no login (spoofable, accepted for family/friends).
Display: top 10 + own rank on the game-over panel, top 5 on the title. Server lives in `server/`
in this repo. Contracts: D-026 (API), D-027 (Profile), D-028 (deploy record, filled at T11.1).

### T11 — Leaderboard server
Owns: everything under `server/` (Node 24, `node:http` + `node:sqlite`, zero deps, `node --test`), plus
`.github/workflows/security-scans.yml` untouched (it already scans the repo). Nothing outside
`server/` except `.gitignore` (additive: `server/node_modules`, `server/.env`).

### T12 — Player profile
Owns: `autoload/profile.gd` (autoload `Profile`), `scenes/ui/name_entry.tscn` +
`scripts/ui/name_entry.gd`, `tests/profile_test.gd`; additive: `project.godot` (autoload line +
`change_name` action N, D-004 superseded), `scenes/ui/title.tscn`/`scripts/ui/title.gd`
(name line + entry), `.gitignore` none. Must not touch `server/`, game_over, HUD, gameplay.

### T14 — QA round 1 (Natasha, 2026-09-08)
1. No way back to the title: after a game (or mid-game) the player could not change the name
   from "Dad" to "Natasha" — only Restart existed. Fix per D-029: a Menu action (Escape) and a
   `MenuButton` on the game-over panel return to the title (title contract D-018 superseded).
2. "Squishies invisible on first load, appear after cycling themes." Not reproducible on a clean
   imported checkout (planner: windowed screenshots on fresh and saved profiles both show all 8).
   Most likely launched before the PNG import finished after a pull. Fix: `Squishy.setup()`
   retries a failed texture load on `palette_changed` and once per second until it succeeds,
   so the symptom self-heals; PLAN "Running the game" already says import first.
Owns: `scripts/main.gd`, `scripts/ui/title.gd` + `title.tscn`, `scripts/ui/game_over.gd` +
`game_over.tscn`, `scripts/squishy.gd`, `project.godot` (one action), `tests/title_test.gd`
(case 3 changes: title *does* return via Menu), `tests/menu_test.gd`, `tests/theme_test.gd` (+retry case).

### T15 — Squishies invisible on real boot (Natasha's bug, root-caused 2026-09-08)
Reproduced only with the literal `godot --path .` launch and an observer autoload injected via
`override.cfg`: all 8 squishies have `catalog_id=''`, no texture; table colours fine; score works.
`Theme._apply_slots()` runs only from `node_added(Table)`, which never fires because the main
scene is already in the tree when `Theme._ready()` connects. Every test/probe adds the scene
later, so all harnesses (and the T8 review) missed it. Fix proven in scratch: add
`call_deferred("_apply_slots_in_tree")` to `Theme._ready()`; plain launch → 8/8 textures;
suite green. Owns: `autoload/theme.gd` (that line), `tests/boot_check.gd` (new autoload-style
check), `tests/run_all.sh` (a real-boot step), `.gitignore` if needed.

### T13a — Friendly page at `/` (Steve, 2026-09-08)
Opening the service root in a browser returned `{"error":"not_found"}`. Add `GET /` → a small
self-contained HTML page (no external assets, no JS needed) showing the top 10 with rank, name,
score and relative time, plus total players and a link to `/v1/leaderboard`. Owns: `server/src/`
(one new handler + template string), `server/test/` (route test), `server/README.md`. Nothing
outside `server/`. Auto-deploys on merge (~30 s downtime).

### T13 — Client leaderboard integration
Owns: `autoload/leaderboard.gd` (autoload `Leaderboard`), `tests/leaderboard_test.gd`;
additive: `project.godot` (autoload line), `scenes/ui/game_over.tscn`/`scripts/ui/game_over.gd`
(`LeaderboardList`, `YourRankLabel`), `scenes/ui/title.tscn`/`scripts/ui/title.gd`
(`TopFiveLabel`), `tests/run_all.sh` (start/stop local server in memory mode). Nothing in
`server/` beyond reading its README for the run command.

### T9 — Test isolation (found in T8 review)
Every `-s tests/*.gd` run uses the app's real `user://` (macOS: ~/Library/Application
Support/Godot/app_userdata/The Squishy Pinball Machine/). `game_flow.gd` and `ui_test.gd`
delete `highscore.save`; `theme_test` writes `settings.save`. Test runs (workers, planner
reviews, CI-less local gates) have been wiping Steve's high score. Fix options: an
`override.cfg` (gitignored) written by a `tests/run_all.sh` that sets
`application/config/custom_user_dir_name` to a test dir; or tests back up and restore both
files. Owns: `tests/*.gd` (setup/teardown only), new `tests/run_all.sh`, `.gitignore`.

### T8 — inputs gathered (history)
Play-test feedback 2026-09-03 after T7b: colours should be more vibrant; the table and
title need visibly more "squishy" theme (PRD §3: realistic-looking table, squishy theme,
fireworks + squishy dance party at 10 000). Node names to theme are fixed in D-014/D-018
(HUD labels, GameOver labels, Title labels, Effects/Fireworks). Art assets must be
original or clearly licensed; no downloads of unknown provenance. Brief written when
T7c/T7d land.

### T7 — Theme & polish (original note)
Art/sound/screen-shake vs. title screen can parallelize; ownership drawn when T5/T6 land.
Tuning backlog from reviews (Natasha decides): flippers cannot cradle a ball — T3 worker
suggests pivots ~270/450 (narrower gap) or a lower drain box; tip shots feel a bit strong.

## Commit-and-merge contract (referenced by every worker brief)

1. Branch from current `main`: `task/T<N>-<slug>`.
2. One task per branch; no drive-by edits outside the task's ownership list.
3. Gate before handoff: `tests/run_all.sh` (D-025) — D-007 commands + every `tests/*_test.gd`
   under an isolated user dir; all must pass clean. Never run tests without the runner.
4. Open a PR to `main`; hand off in the dispatch-worker format. CI (Semgrep SAST + Trivy,
   `.github/workflows/security-scans.yml`, PR #4) must be green. Planner reviews
   (review-handoff), Steve merges. Natasha play-tests before a phase is called done.
5. Workers never edit PLAN.md, DECISIONS.md, or PRD.md.
6. A worker running in a separate clone (only when two tasks run at once) deletes that
   clone after its PR is pushed, and reports `CLONE: deleted <path>` in the handoff.
   The planner checks for leftover sibling folders at each review.

## Predicted conflict points

- `scenes/table.tscn`: touched by T2, T3, T5 — strictly sequenced for this reason.
- `scenes/main.tscn`: T2 and T6 both edit it; T4 edits `main.gd`. Sequenced (T2 → T4 → T6).
- Godot .tscn files merge badly in general: never run two tasks that touch the same
  scene file, even "append-only" edits.

## Verification log

(what was checked and how, as tasks land — planner appends)

- 2026-09-02: Repo state verified: `main` at 45ebf1f, only PRD.md + README.md. Godot
  absence verified via `which godot` + /Applications scan.
- 2026-09-02: T1 (PR #1, e5f0c87) reviewed in isolated scratch clone. Base = current
  main (merge-base 4e74259 ✓). Scope = exactly the 5 owned files ✓. Both D-007 gates
  re-run independently: import exit 0, 300-frame run exit 0. project.godot read line
  by line: D-003 display settings and all four D-004 action names verified with
  correct physical keycodes (65/4194319, 68/4194321, 32, 82). Findings: `timeout`
  absent on macOS (D-007 corrected — planner error, worker caught it);
  `scripts/main.gd.uid` untracked → D-008, worker asked to commit it in PR #1.
- 2026-09-02: T2 (PR #2, f1a6992) reviewed in scratch clone. Base ✓, scope ✓ (12 files;
  project.godot = [physics] only; main.tscn +3 lines). All 3 gates re-run: import 0,
  300-frame 0, SOAK PASS 20/12000/0. Planner probe (fixed-fps): 12 gameplay launches
  through real drain+respawn → 12 drained, 0 stuck, 0 OOB, 417 frames each; overdrive
  2600/4000/8000 all in bounds. DEFECT: weak launch falls back into lane with
  launched=true → Space dead forever (soft-lock; reachable once T3 flippers exist).
  Fix proven in scratch (drop `launched` gate in ball.gd): relaunch moved=true, soak
  still green. Changes requested on PR #2 with patch + regression property.
- 2026-09-02: T2 fix-up (c1a41b9) re-verified in scratch clone: diff = ball.gd 1 line +
  soak +55 lines only. Gates: import 0, 300-frame 0, SOAK PASS 20/12000/0 relaunch=1.
  Proved regression can fail by restoring old gate → SOAK FAIL relaunch=0 (0.87 px),
  exit 1. No check runs exist on the commit (repo has no CI). Approved; Phase 1 closes
  on merge. Natasha play-test still owed before Phase 2 is called done.
- 2026-09-02: T4 (PR #3, 669ee95) reviewed in scratch clone. Base ✓, scope ✓ (7 files;
  project.godot = [autoload] only; table.gd = TEMP block only). All 4 gates re-run:
  import 0, 300-frame 0, SOAK PASS relaunch=1, FLOW PASS cases=5 autoload_used=true.
  Planner integration probe on real main.tscn: 27 checks / 0 fails — 3 drains → no 4th
  ball, game_over ×1; restart via InputEventAction from GAME_OVER, mid-flight, during
  pending respawn timer (Bugbot race, fixed 48d7ac0), R×3 mash → always exactly 1 ball;
  second game + restart OK. Approved. D-011 superseded: restart emits only game_restarted.
- 2026-09-03: T3 (PR #5, d91e321) reviewed in scratch clone. Scope ✓ (6 files; table.tscn
  purely additive). All 4 gates re-run: import 0, 300-frame 0, SOAK PASS relaunch=1,
  REST PASS + FLIP PASS hits=2 hold=1 tip_flips=20. Planner probes on real main.tscn with
  Drain ON: tip shot at 0.95 lifts (vy -800) with no drain; hub pinch 10 flips 0 OOB;
  both-up centre gap drains; 9000-frame mashed game 0 OOB. Bugbot drain-overlap finding
  measured: balls at along 0.70–1.00 drain only at projected 0.99–1.02 (rounding the tip),
  0.70 survives 48 frames → fixed at 97eb9a1. Approved. Cradle/gap note → T7 backlog.
- 2026-09-03: T6 (PR #7, 41d1173) reviewed in scratch clone. Base ✓ (f187421), scope ✓
  (9 files; main.tscn additive). All 6 gates re-run green: UI PASS cases=7. UI scripts
  audited: only Game reads + restart(). Planner probe on real main.tscn, 10 checks / 0
  fails: real drain → BALLS 2; 3 successive games (300/500/100) → panel + HUD HIGH track
  correctly, NEW HIGH only when beaten; button restart leaves no focus owner; R works
  with panel showing; zero-score game over shows FINAL 0. Approved.
- 2026-09-03: T5 (PR #8, fa98729) reviewed in scratch clone. Scope ✓ (11 files; table.tscn
  additive). All 6 gates re-run green. Probes: bumper 17 score events / 0 within 12 frames;
  targets physical → 500×3 + 2500, reset 0.5 s, lit re-hit = 0, restart-race generation
  guard holds, 3 bonuses across restarts. Approved. FOUND (pre-existing): flipper-base
  pocket — idle 1600/1750/1800 rest at (252,1107) on main; 1700 → (467,1106) on branch;
  30 double-flips don't free it → task T3.1 (V1 blocker).
- 2026-09-03: T3.1 (PR #9, 4e023fb) reviewed in scratch clone. Scope ✓ (3 files; table.tscn
  additive). All 6 gates green incl. BASE. Probes: idle sweep step 25 → no rests/traps;
  20 slow drops around both pivots all drain; cradle on raised flipper held 600 frames
  (nudge does not fire on holds); mashed game → GAME_OVER 8016 frames, score 5700, nudge
  condition 1 frame. Approved; V1 blocker cleared.
- 2026-09-03: T7a (PR #10, e601255) reviewed in scratch clone. Scope ✓ (11 files; table.tscn
  + Effects only; game.gd additive). 7 gates green; scoring_test change = strengthening.
  Probes: camera centred (360,640) exactly; streak window 1.95 s continues / 2.05 s resets;
  physical drain clears streak + label; big score once per game, again after restart;
  shake moves no physics (0.000 drift, bumper fixed), offset returns to 0; mashed game
  deltas all valid, label consistent every frame. Approved.
- 2026-09-03: T7b (PR #11, 759ca30) reviewed in scratch clone. Scope ✓ (6 files; main.tscn
  additive; main.gd untouched). 9 gates green (TITLE PASS cases=4). Probe: layers 10<15<20;
  controls text complete; R on title OK; one Space hides title + launches same frame;
  title never returns after game over/restart. Approved.
- 2026-09-03: T7d (PR #12) reviewed. Diff = 3 D-019 constants only. Worker reported
  streak_test case 5 failing (30-frame wait < 0.26 s shake) and correctly stopped — the
  brief had scoped that test out (planner error). Reproduced, fixed wait 30→36 in scratch
  (STREAK PASS), pushed to the branch as 24f2d32 with attribution. Scratch-merged current
  main: all 7 suites PASS incl. TITLE; HIT vy −1157.9 → −1382.6, TIP 20/0, BASE 8. Approved.
- 2026-09-03: T7c (PR #13, 53ca139) reviewed in scratch clone + merge with current main.
  Scope ✓ (13 files, autoload line only in project.godot, no .import). WAVs valid mono
  22050/16-bit, regen byte-identical. 8 suites PASS incl. SFX events=7. Probes: no-table
  tree → unwired/silent; wiring on main.tscn add, listener detached; each bumper connected
  once; plays==hits (3/3), pitch 1.00→1.12 with streak; drain×3 + game_over×1; restart
  silent; flipper hold=1 play; big_score/all_targets once. Approved. D-018 amended.
- 2026-09-04: T8 (PR #15, 54f247a) reviewed in scratch clone. Scope ✓; project.godot autoload
  line only; catalogs untouched. Physics: tscn physics lines identical (+2 decor positions,
  no colliders); runtime 27 shapes same hash, drain 558×5 on branch and main. 9 suites PASS,
  slice tool reproducible. Probes: 16 RGBA sprites clean border; 4 palettes recolour live;
  settings persist; arrows cycle only on title; dance 8→0 on restart. Approved. Found T9
  (tests write real user://).
- 2026-09-05: T10 (PR #16, ab6afa8) reviewed in scratch clone. 7 files, scope ✓ (squishy.gd
  offset removal disclosed + required). 9 suites PASS. Probes: 8/8 sprites aligned ≤1 px,
  score on drop, no pass-through (main failed 5/8); idle sweep step 25 no rests; mashed game
  GAME_OVER 9182 frames / 20 200 pts / 0 OOB; 25 target-circle drops → 20 drain, 5 exact-apex
  zero-velocity drops balance (1 px or 3 px/s lateral → drain; measure-zero, D-024). HIT vy
  −1382.6 → −1557.8. Approved.
- 2026-09-06: T9 (PR #17) reviewed in scratch clone. Scope ✓. Worker flagged game_flow.gd
  skipped by the `*_test.gd` glob (D-025 wording — planner error); planner added it on the
  branch. Runner 12/12 PASS; real highscore/settings byte-identical before/after; override.cfg
  removed after run; bare isolation_test exit 1; SIGINT-to-bash-only delays cleanup until the
  Godot child exits (terminal Ctrl-C is immediate). Approved.
- 2026-09-07: T12 (PR #19, 2e0147c) reviewed in scratch clone under the isolated runner.
  Scope ✓ (10 files; project.godot = autoload + change_name). run_all 13/13 PASS. Planner
  probe with real key events, 17/17: typing keys never launch/flip/restart/cycle; visible-but-
  unfocused entry blocks Space; sanitising, persistence, N/Escape, no re-prompt after restart.
  Harness note: name_entry.gd uses the `Profile` global → scripts preloading main.tscn in -s
  tests fail to compile; tests must load() at runtime (CLAUDE.md convention added). Approved.
- 2026-09-08: T11 (PR #18, 45911b9) reviewed in scratch clone + merge with main. Scope ✓, 0 deps,
  npm test 24/24 memory and file DB, clear boot error on missing DB dir. Live probes via Node:
  latest-name/best-score rule, stable ties, limit clamp, /me, 401/400 matrix incl. 5 KB + bad JSON,
  17→16 chars, 30/min limiter (12×429 in 40), 404s. Approved. T11.1 deploy deferred by Steve
  pending QA fixes.
- 2026-09-08: T14 (PR #20, d1402c8) reviewed in scratch clone under the runner. Scope ✓ (11
  files; project.godot = menu action). 14/14 PASS. Probe with real keys 13/13: Esc mid-game →
  menu (READY/0/3/1 ball), rename from menu, Space relaunch, Esc-while-typing cancels only, R
  keeps title hidden, MenuButton, hint text, squishy bad-id → retry restores in 1 s. Approved.
- 2026-09-08: Invisible squishies ROOT-CAUSED. 5 harness attempts passed because they add the
  scene after autoloads; the real `godot --path .` boot (observer autoload via override.cfg)
  shows catalog_id='' on all 8. Theme relies on node_added(Table) → never fires at boot.
  One-line fix proven (plain launch 8/8 textures; suite green). Dispatched as T15 with a
  real-boot regression step in the runner. Planner miss at T8 review recorded.
- 2026-09-08: T15 (PR #21, 2916354) reviewed in scratch clone. Scope ✓ (3 files). Suite PASS
  incl. new boot-check. Falsified: removing the one-line fix → BOOT FAIL, exit 1; override.cfg
  cleaned up after failure. Windowed plain launch on the branch → 8/8 textures. Bugbot timer
  race fixed with a frame wait. Approved. Natasha's invisible-squishies item closes on merge.
- 2026-09-08: T11.1 deploy. Service created via Render connector (starter, Oregon); first deploy
  failed at boot with the server's own `DB_PATH directory does not exist` guard (expected, no
  disk yet); Steve added 1 GB disk at /var/data; NODE_VERSION=24 env set after logs showed
  Render defaulted to Node 26. Live smoke: healthz store=sqlite; 401 no/wrong key; 400 bad
  body; POST 201 rank 1 (76 ms); /me 200; board lists it. Triggered a redeploy: ~30 s 502
  (disk services have no zero-downtime), then 200, board still holds the entry (persistence
  proven). Build log: "Using Node.js version 24.20.0 via NODE_VERSION". D-028 complete.
- 2026-09-08: T13 (PR #22, 04d713d) reviewed in scratch clone merged with main. Scope ✓. Suite
  PASS incl. boot-check + LEADERBOARD 6/6 (runner runs a local memory server; other suites use a
  closed port). Probes on a file-backed server: offline in 21 ms, label shown, restart fine;
  single retry lands at 5.2 s (1 row); online submit once, rows +1 exactly after the retry
  window; zero score / empty name → no post; stale fetch dropped. Live board shows the worker's
  T13/1313 entry. Approved. Backlog T13b: retry cannot outlast a 30 s deploy.
- 2026-09-09: T13a (PR #23, c36aa9d) reviewed in scratch clone. server/ only, 0 deps, npm test
  32/32. GET / : correct headers, byte-accurate content-length with non-ASCII, empty-board text,
  10-row cap with latest names, XSS vectors escaped (no raw <script/<img), no external refs,
  JSON routes unchanged. Worker disclosed a brief checkout of the shared folder; verified clean.
  Approved. Phase 5 shared leaderboard complete once merged.
- 2026-09-09: T13a merged; `/` still 404 live → list_deploys showed no deploy since creation
  (auto-deploy never fired; GitHub App not connected). Manual trigger_deploy of 8e87f87 → live in
  ~70 s; `/` 200 text/html no-store, lists Dad / T13 / Smoke Test. D-028 corrected.
