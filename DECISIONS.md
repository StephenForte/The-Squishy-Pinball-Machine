# Decisions — The Squishy Pinball Machine

Numbered, append-only. Never renumber; supersede in place with date and reason.
Workers cite these instead of re-deciding. Next free number: **D-008**.

## D-001 — Engine: Godot 4.x, GDScript (2026-09-02)
Per PRD. Exact version to be pinned as D-006 once installed on the build machine.

## D-002 — 2D physics, not 3D (2026-09-02)
"Realistic" look comes from art in Phase 4, not a 3D engine. RigidBody2D ball,
StaticBody2D walls, AnimatableBody2D or joint-driven flippers (worker's choice in T3,
recorded here after review).

## D-003 — Display: 720×1280 portrait, `canvas_items` stretch, `keep` aspect (2026-09-02)
Pinball tables are vertical. Window resizable; base resolution fixed so physics tuning
is stable across machines.

## D-004 — Input map (pre-assigned action names) (2026-09-02)
Defined once in T1's `project.godot`; every later task uses these exact names, adds none:
- `flipper_left`: A, Left Arrow
- `flipper_right`: D, Right Arrow
- `launch_ball`: Space
- `restart`: R

## D-005 — Game contract: autoload, signals, scoring, save file (2026-09-02)
Autoload `Game` → `res://autoload/game.gd`.
- Signals: `score_changed(new_score: int)`, `ball_count_changed(balls_left: int)`,
  `game_over(final_score: int, is_high_score: bool)`, `game_restarted`
- Methods: `add_score(points: int)`, `on_ball_drained()`, `restart()`
- Scoring: bumper 100, target 500, all-targets bonus 2 500 (then targets reset)
- Big-score moment (fireworks + squishy dance party, Phase 4): score ≥ 10 000
- Balls per game: 3. High score: JSON at `user://highscore.save`
- Node groups: bumpers in `"bumpers"`, targets in `"targets"`

## D-006 — Godot version pin: 4.7.2.stable.official (2026-09-02)
Verified on the build machine: `godot --version` → `4.7.2.stable.official.ed1daf0bf`,
binary at `/usr/local/bin/godot` (Godot.app in /Applications). All workers use the
`godot` command; do not upgrade mid-project without a superseding decision here.

## D-007 — Verification gate commands (2026-09-02)
Run from repo root before every handoff:
1. `godot --headless --import` — must complete with zero script/parse errors
2. `timeout 30 godot --headless --quit-after 300` — main scene runs 300 frames, no errors

