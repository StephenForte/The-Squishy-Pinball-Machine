# Working rules for agents in this repository

Read PLAN.md (task ownership, merge contract) and DECISIONS.md (numbered contracts) first.

## The shared-checkout rule — read before any git command

Several agents work on this project at the same time. **Only one task may use this folder
(`Pinball/`) at a time.** If your brief's `Working directory` is a clone path
(e.g. `~/Library/CloudStorage/Dropbox-Personal/Dev/Pinball-T11`), you must work there:

1. First command of your session: `pwd`. If it does not end in the clone path your brief
   names, run the `git clone … <clone path>` command from the brief and `cd` into it.
   **Do not create your branch here.**
2. **Never** run `git stash`, `git switch`, `git checkout`, `git reset`, `git restore`,
   `git clean`, `git rebase` or `git merge` in a folder where you did not create the branch
   you are on. `git status` showing another task's branch or uncommitted files means
   someone else is working here — stop and report; do not stash their work.
3. When your PR is pushed, delete your clone and report `CLONE: deleted <path>`.

Why: on 2026-09-07 a worker skipped its clone, ran `git stash` in this folder and switched
branches while another task had uncommitted work here. The work survived only because the
other worker noticed. Stashing or resetting someone else's work is silent data loss.

## Tests

Run tests only via `./tests/run_all.sh` (D-025). Direct `godot -s tests/…` runs write to the
real save directory and wipe the player's high score.

## Code conventions that tests depend on

- Reference autoloads as `get_node("/root/Game")` / `get_node_or_null("/root/Theme")`, **not**
  the bare global (`Game.`, `Theme.`). Headless `-s` tests that `preload()` a scene compile
  its scripts before autoload globals exist; the bare global then fails to compile.
- Tests load scenes at runtime (`load(...)`), never `preload(...)`, for the same reason.
- A test script that hits a runtime error mid-coroutine never reaches `quit()` and hangs the
  runner; keep `_run()` defensive and print progress lines.

## Boot order (D-030)

- Autoloads must not depend on `node_added` to find scene nodes: in a real `godot --path .`
  boot the main scene is already in the tree when autoload `_ready()` runs. Apply to the
  existing tree (deferred `find_child`) *and* listen for later additions.
- Tests that instantiate `main.tscn` themselves do not exercise real boot order; the runner's
  real-boot step does. If you touch autoload wiring, run `godot --path . --headless --quit-after 300`
  and check the output, not just `-s` tests.

## Scope

Edit only the files your brief lists. If the task seems to need another file, stop and
report — do not widen scope. Never edit PLAN.md, DECISIONS.md or PRD.md (planner-owned).
