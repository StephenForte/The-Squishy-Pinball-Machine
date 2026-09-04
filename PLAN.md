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
| T7b | Title screen + instructions | 4 | approved 2026-09-03; PR #11 (759ca30) ready to merge | cheap | T7a |
| T7c | Sound effects | 4 | dispatched 2026-09-03 (start after T7a merges) | mid | T7a |
| T7d | Tuning: stronger shake, more flipper power (D-019) | 4 | dispatched 2026-09-03 | cheap | T7a |
| T8 | Squishy art + theme pass | 4 | not started (Natasha: later) | strong | T7a–c |

**Run order:** T1 → T2 → (T3, T4) → T5 ∥ T6 → T3.1 → T7a → T7b ∥ T7c → T8.
T5 and T6 are the only truly parallel pair; ownership below is drawn to keep them apart.

## Blockers / open items

- None. Godot 4.7.2.stable installed and verified 2026-09-02 (D-006); gate is D-007.

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

### T7 — Theme & polish (original note)
Art/sound/screen-shake vs. title screen can parallelize; ownership drawn when T5/T6 land.
Tuning backlog from reviews (Natasha decides): flippers cannot cradle a ball — T3 worker
suggests pivots ~270/450 (narrower gap) or a lower drain box; tip shots feel a bit strong.

## Commit-and-merge contract (referenced by every worker brief)

1. Branch from current `main`: `task/T<N>-<slug>`.
2. One task per branch; no drive-by edits outside the task's ownership list.
3. Gate before handoff: run the D-007 commands from repo root; both must pass clean.
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
