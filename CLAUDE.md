# Punch My Boss — project guide

A 2D arcade **boxing / stress-relief game**: tap gamepad-style buttons to punch your
cartoon boss in an office. Inspired by Punch-Out!!, and art-directed toward the
**Cuphead / Thunder Ray / Big Boy Boxing** look (hand-drawn, inked, 1930s-cartoon).

## Where the project lives
- The **Godot 4.7 project** is in the [`game/`](game/) folder (open `game/project.godot`).
- `punch-my-boss-1.html` at the repo root is an older standalone HTML prototype (not the
  active game — the Godot version supersedes it).

## Key files
- `game/scenes/main.tscn` — the single main scene (boss, office background, UI, buttons).
- `game/scripts/main.gd` — **all game logic** (GDScript): input, fight state machine,
  juice/effects, procedural audio, meters, layout. Start here.
- `game/assets/boss/` — boss sprites: `body.png`, `fist.png`, head expressions
  (`neutral`, `talk`, `react0`–`react14`), and `boss_frames.tres` (an empty
  SpriteFrames slot wired to a hidden `BossAnim` node, ready for hand-drawn frames).
- `game/assets/bg/office.jpg` — the (currently photographic) office background.
- `game/shaders/` — `toon_bg` (posterize + inked edges), `outline` (boss outline),
  `vignette`. Applied to nodes in `main.gd`'s `_ready()`.

## How it plays
- **Landscape.** Controls: on-screen **A / B / X / Y** buttons, also keyboard A/B/X/Y and
  gamepad face buttons. A = left hand→body, B = right hand→body, X = left side of head,
  Y = right side of head. Each throws the fist from the correct side.
- Boss fight loop: **guard → wind-up "tell" (leans back, glows orange) → vulnerable
  window (flashes yellow, "HIT HIM!")**. Punches during the vulnerable window are
  **critical** (big damage). Fill the K.O. meter to launch the boss; it then resets.

## Running / testing
- **Locally:** `Godot_v4.7 --path game` runs it; `Godot_v4.7 -e --path game` opens the editor.
- **Headless syntax/scene check** (no GUI, good for CI or cloud):
  `Godot_v4.7 --headless --path game --quit-after 120` — parse/scene errors print to stdout.
- **Cloud/web note:** a headless environment can't open the Godot GUI or "play" the game
  visually. Work on code, run the headless check above, and commit — someone with the
  editor can verify visuals.

## Conventions
- Milestone commits are versioned: `vN.M: <summary>` (e.g. `v0.13: cartoon UI ...`).
- GDScript, tabs for indentation, snake_case. Keep new code in the style of `main.gd`.
- Art direction: prefer **hand-drawn / illustrated assets** over more photo filtering
  when improving the look — filtering the photo background has a hard ceiling.

## Auto-backup
A local watcher auto-commits & pushes to GitHub, so the `main` branch stays current.
When working from the web, branch/PR as usual; pull locally to stay in sync.
