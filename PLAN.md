# The Squishy Pinball Machine — Build Plan

Source of truth for task breakdown, ownership, and status. Planner updates this file;
workers never edit it. Companion: [DECISIONS.md](DECISIONS.md) (numbered, append-only).

**Engine:** Godot 4.x / GDScript / 2D physics (see D-001, D-002).
**Repo:** https://github.com/StephenForte/The-Squishy-Pinball-Machine

## Status

| ID | Task | Phase | Status | Model tier | Depends on |
|----|------|-------|--------|------------|------------|
| T1 | Project scaffold | 0/1 | dispatched 2026-09-02 | cheap (Sonnet) | — |
| T2 | Table, ball, launcher, drain | 1 | not started | strong (Opus+) | T1 |
| T3 | Flippers + controls | 2 | not started | strong (Opus+) | T2 |
| T4 | Game flow: 3 balls, restart | 2 | not started | mid | T2 (not T3) |
| T5 | Bumpers, targets, scoring | 3 | not started | mid | T3, T4 |
| T6 | HUD, game over, high score | 3 | not started | mid | T4 |
| T7 | Theme & polish | 4 | not started | split at dispatch | T5, T6 |

**Run order:** T1 → T2 → (T3, then T4 — T4 may start once T2 merges) → T5 ∥ T6 → T7.
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

### T4 — Game flow
Owns: `autoload/game.gd` (autoload name `Game`), edits `scripts/main.gd`.
Implements the D-005 contract: 3 balls per game, ball-drained → respawn or game over,
restart on R. Must not touch table.tscn or any T3/T5 file.

### T5 — Bumpers, targets, scoring
Owns: `scenes/bumper.tscn`, `scenes/target.tscn`, `scripts/bumper.gd`,
`scripts/target.gd`; edits `scenes/table.tscn` to place ≥3 bumpers + 3 targets.
Scoring values and all-targets bonus per D-005. **Must not edit `scenes/main.tscn`
or anything under `scenes/ui/`** — that is T6's territory.

### T6 — HUD, game over, high score
Owns: `scenes/ui/` (all), `scripts/ui/` (all); edits `scenes/main.tscn` to add the UI
layer. Score/balls display driven only by `Game` signals (D-005) — no references into
table or gameplay scenes. High score persisted at `user://highscore.save` (D-005).

### T7 — Theme & polish (split into sub-briefs at dispatch time)
Art/sound/screen-shake vs. title screen can parallelize; ownership drawn when T5/T6 land.

## Commit-and-merge contract (referenced by every worker brief)

1. Branch from current `main`: `task/T<N>-<slug>`.
2. One task per branch; no drive-by edits outside the task's ownership list.
3. Gate before handoff: run the D-007 commands from repo root; both must pass clean.
4. Open a PR to `main`; hand off in the dispatch-worker format. Planner reviews
   (review-handoff), Steve merges. Natasha play-tests before a phase is called done.
5. Workers never edit PLAN.md, DECISIONS.md, or PRD.md.

## Predicted conflict points

- `scenes/table.tscn`: touched by T2, T3, T5 — strictly sequenced for this reason.
- `scenes/main.tscn`: T2 and T6 both edit it; T4 edits `main.gd`. Sequenced (T2 → T4 → T6).
- Godot .tscn files merge badly in general: never run two tasks that touch the same
  scene file, even "append-only" edits.

## Verification log

(what was checked and how, as tasks land — planner appends)

- 2026-09-02: Repo state verified: `main` at 45ebf1f, only PRD.md + README.md. Godot
  absence verified via `which godot` + /Applications scan.
