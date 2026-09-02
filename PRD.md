# The Squishy Pinball Machine — Mini PRD

## 1. The game

A single-player virtual pinball game made by Steve and Natasha for fun. But with a shared leaderboard (after Phase 1.)

We will build it in Godot, using GDScript, Godot's built-in programming language. AI coding agents will help us implement small, clearly defined features, while we make the creative and gameplay decisions.

## 2. Player experience

The player launches a ball, uses two flippers to keep it alive, hits targets, and tries to earn the highest score.

The game should feel:

* Fast and satisfying
* Easy to understand in 10 seconds
* Fun to replay
* A little challenging, but not frustrating

## 3. Theme and style

* Theme: Squishy themed
* Table name: The Squish Zone
* Visual style: Realistic, looks like a real pinball table
* What happens when the player gets a big score: fireworks, AI squishies dance party
* Favorite sound / music vibe: Squishy arcade music vibe with a little Ms. Pac-Man thrown in as a mash up

## 4. Version 1: required

* One playable table
* Ball, gravity, walls, launcher, and drain
* Left and right flippers
* At least three bumpers or targets
* Score display
* Three balls per game
* Game-over screen and restart button
* Local high score

## 5. Later ideas — not Version 1

* Ramps
* Multiball
* Missions or modes
* Unlockable table features
* Custom music
* More tables

## 6. Controls

* Left flipper: A or Left Arrow
* Right flipper: D or Right Arrow
* Launch ball: Space
* Restart: R or on-screen button

## 7. Development approach

We will use a phased approach. Each phase must be playable and tested before starting the next one. AI agents should receive one small task at a time, not a request to build the entire game.

### Phase 0 — Design

* Choose the theme and table name.
* Sketch the table on paper.
* Decide the bumpers, targets, and big-score moment.
* Create the Godot project and GitHub repository.

### Phase 1 — Playable physics prototype

* Create the playfield boundaries.
* Add a ball with gravity and collision.
* Add a launcher and drain.
* Confirm the ball moves and behaves reliably.

### Phase 2 — Core pinball controls

* Add left and right flippers.
* Add keyboard controls.
* Tune the flippers until the ball is reasonably controllable.
* Add three balls and a restart flow.

### Phase 3 — Score and gameplay

* Add bumpers and targets.
* Add score display and scoring values.
* Add a simple "hit all targets" reward or score multiplier.
* Add game over and local high score.

### Phase 4 — Theme and polish

* Add art, table labels, lights, and sound effects.
* Add a title screen and clear instructions.
* Add screen shake or other satisfying feedback for big hits.
* Playtest and tune anything that is confusing or not fun.

### Phase 5 — Optional upgrades

* Save user name across sessions
  * User selects & edits their own avatar
* Squishy inventory
  * Squishy awarded for level up
  * Special Squishy awarded for high score
* Centralized database to hold all users
* Ability to trade Squishies with other players

## 8. Working rules

* Make one small change at a time.
* Test after every change.
* Commit each working feature to GitHub.
* Keep Version 1 small.
* Put new ideas in "Later ideas" unless they are necessary to make Version 1 playable.
* Natasha decides whether a feature is fun; Steve decides whether it is ready to add safely.

## 9. Definition of done for Version 1

A player can start the game without instructions, launch and control three balls, hit targets to score points, see a final score and high score, restart immediately, and enjoy a complete short game.
