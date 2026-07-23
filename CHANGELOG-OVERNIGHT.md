# Overnight build log

Running log of the autonomous session. Newest at the bottom. Every entry is a
commit that was headless-verified before landing.

---

## `718601e` — config fixes

- `config/features` said **"Forward Plus"** while the renderer was **mobile**;
  the engine reports `Forward Mobile` at runtime, so the tag was simply wrong.
- Removed the dead `[dotnet]` block (project is 100% GDScript, zero `.cs` files).

**Decision noted:** removing `[dotnet]` does **not** silence the editor's
".NET Sdk not found" error. Verified with a headless `--editor` pass — it comes
from `GodotSharpEditor._EnablePlugin()` in the mono editor build, independent of
project contents. To make it go away you'd install the .NET 8 SDK or switch to
the non-mono Godot build. **Nothing was installed.**

## `61f1807` — v0.15: cartoon boss replaces the claymation one

Your 20 uploads → 18 unique (two pairs were byte-identical).

| State | Count |
|---|---|
| Idle / neutral | 5 |
| Dizzy (spiral eyes) | 4 |
| Taking a hit | 6 |
| Throwing a punch | 1 |
| Walking | 1 |
| KO'd on ground | 1 |

- **Chroma key** on green *dominance* (`g - max(r,b)`), not colour distance —
  distance keying destroyed the character because khaki trousers sit within
  ~140 units of that green.
- **Sliced into 15 pieces** on a **16-bone** skeleton: hips, torso, head,
  upper arm / forearm / hand ×2, thigh / shin / foot ×2 — the full granularity
  you asked for.
- **9 head expressions** harvested from the pose set, all normalised to a shared
  neck anchor so texture swaps never jump.
- Player's fist is now the **red boxing glove** cut from a hit frame (the old
  claymation fist looked wrong against cartoon art).

## `26f3b2a` — v0.16: animation system

`scripts/boss_rig.gd`. Animations tween **additive offsets**, and one compose
pass per frame writes the bones. That's what lets a head-spin play on top of a
stagger on top of breathing without them fighting.

- **Offense:** tell, jab, hook, uppercut
- **Defense:** block, unblock, dodge (left / right / duck)
- **Reactions:** stagger, head_spin, neck_stretch, wobble_stun, knees_buckle,
  squash, ko_collapse
- **Flavour:** taunt, laugh, point_at_player
- **Lively idle:** blinking, random glances, shoulder-roll fidgets, on top of
  breathing and weight shift

Every critical hit now rolls a random cartoon gag — head spins 2–4 full turns,
neck stretches like rubber, or a dazed metronome wobble.

## `cc7c6d8` — v0.17: Punch-Out combat loop

`GUARD → WINDUP (tell) → ATTACK → RECOVER`. Dodge in time and he whiffs, which
*is* the punish window; miss and it costs you health. Timing, not mashing.

- Boss picks jab / hook / uppercut at wind-up so the tell matches the side
- Dodge on arrows / D-pad: left & right slip, down ducks. **The uppercut
  punishes ducking**, so direction matters rather than being one panic button
- Player health bar + "YOU'RE FIRED" game over, restarts the level
- Difficulty: **BAG** (never attacks) / **DEFENSIVE** (guards, won't swing) /
  **BRAWLER** (full exchange)
- Four levels with distinct pace, damage, HP and dialogue; later levels
  telegraph faster, tightening the dodge window

## v0.18 — self-serve visual verification + layout fixes

Run `Godot --path game -- --shots` and the game dumps a 48-frame filmstrip to
`user://shots` while a scripted demo punches, dodges and takes hits, then exits
on its own. Lets the build be checked visually with nobody watching the window.

**Four real bugs it caught immediately** — none of which were visible from
headless "exit 0":

1. **The boss's feet rendered 65px below the screen.** `offset_top 587 +
   1240×0.45 = 1145` on a 1080 viewport. He was also too small for a
   Punch-Out feel. Now 0.55 scale, 682px tall, feet at y≈1010 lining up with
   the existing shadow.
2. **"COMBO" ran off the right edge** — at font 96 the word is ~380px wide and
   was top-left anchored at x=1560. Now right-anchored in a sized, centred box,
   which also protects it from mobile safe-area insets.
3. **The player health bar was invisible and collided** with the hint text and
   punch counter. It was an unstyled `Panel` (renders near-black) pinned
   bottom-left. Now a third bar under FRENZY/BOSS, styled to match.
4. **The hint text ran off the left edge** — `grow_horizontal = BOTH` expanded
   the long string symmetrically around its anchor.

**And the cutout risk I'd flagged turned out to be real:** elbows and wrists
visibly came apart during big stagger rotations. Re-sliced so each child piece
extends well past its own joint (children draw on top, so the extra material
hides the seam instead of doubling). Verified on a cropped joint filmstrip —
limbs now read as continuous.

## `7a34789` — v0.19: both flagged unknowns resolved (not just re-flagged)

- **Glove orientation: confirmed correct.** Added `--shots-fast` (0.09s
  cadence) because the thrown glove is only on screen ~0.22s and the default
  0.30s sampling skipped every single one. Knuckles lead, wrist trails — right
  for a first-person thrust. No change needed.
- But the filmstrip showed the glove was **big enough to hide the boss's
  reaction**, which is the thing worth watching. 320px/1.4× → 250px/1.15×.
- **Dizzy-head scale pop: I was wrong.** I'd said they were drawn *larger*.
  Measured, most are **smaller** (235px skull vs neutral's 253) and only
  `dizzy1` was bigger. All nine now normalise to a 253px skull before
  anchoring. Verified across neutral and dizzy frames — no pop.
- Also fixed **elbows bending backwards** on stagger: forearms rotated the same
  direction as the upper arms. They counter-rotate now.

## v0.20 — arcade scoring, cooldown, music, saves

- **Score** replaces the punch counter, rolls up smoothly, with floating `+N`
  popups that read louder on big hits.
- **Punch cooldown (0.17s).** This was the open design question from the
  proposal — without it, mashing or an autoclicker farmed unlimited combo and
  made the whole guard/tell/dodge loop pointless.
- **Combo multiplier raised to 4×** (was 1.8×). It can go this high precisely
  *because* the cooldown means a long combo is earned on timing, not mashing.
- **Fight music**: procedural chiptune loop — square bass + triangle arpeggio
  over i–VI–III–VII in A minor, seamless. Still zero audio assets shipped.
- **Settings toggle**: MUSIC/MUTED button (also the **M** key), persisted.
- **Save file** at `user://punchmyboss.cfg` — best score, music, difficulty.
  Verified round-tripping by exercising the toggle inside the demo run rather
  than assuming it worked (`best=244, music=true, difficulty=2`).

## v0.21 — title, pre-fight, game over, victory

Proper game phases: **TITLE → PREFIGHT → FIGHT → GAMEOVER/VICTORY → TITLE**.
The fight loop and all player input are gated on `phase == FIGHT`, and the
fight HUD hides on menu screens.

- **Title**: best score, difficulty picker (**1/2/3**), tap to start
- **Pre-fight**: level name + the boss's opening line, using the existing
  typewriter — the "talk to him before you fight him" beat
- **Game over / victory**: score, best, max combo, crit count
- Victory advances the level; game over retries

**Fixed a real balance bug while here:** `_knockout()` used to loop straight
into another round at **1.4× HP**, which compounds to ~100k HP by round 20 and
means the player can never actually finish. Beating him now ends the level.

**Also fixed a memory leak I introduced.** The looping music stream survived
teardown — 2 leaked `ObjectDB` instances at exit. I confirmed causation by
disabling the music entirely (warning vanished) rather than guessing, then
released the stream on close. Clean exit now.

## `b49e6a5` — v0.22: customisation = the generic-character architecture

The boss is now **one rigged body + a swappable look**. Adding a character
means a new look (or a new art set in the same rig), not a new rig — which
answers your "one generic modifiable character vs. many bespoke ones" question
**in favour of generic**.

- **6 skin tones**, recoloured in-shader with shading preserved
- **4 hair** + **3 moustache** options, drawn on the same 460×500 canvas as the
  heads so they inherit the head's anchor exactly
- Cycle with **K** / **H** / **J**; saved to disk

Technical notes worth keeping: skin is matched by **hue/saturation/value**, not
RGB distance (the art has several skin shades; a distance test either misses
shadows or bleeds into the khaki). Only skin-bearing pieces get the recolour
enabled, each with its **own duplicated material** — uniforms live on the
material, so a shared one would have recoloured everything at once. And the
uniforms are deliberately **not** `source_color`, since that hint linearises
values the HSV maths treats as raw sRGB.

**Two false alarms worth recording**, because both were *my measurement* being
wrong rather than the code:
1. I measured "average skin-hued pixels" — but the brown office background
   passes the same hue filter and swamped the average.
2. I then sampled the **pre-fight screen**, which has a 45% dim overlay, so
   everything looked unchanged.
A side-by-side on an undimmed fight frame showed it working correctly all
along. Lesson: verify on a frame that isn't dimmed, and diff rather than average.

## `MAKE-IT-SELLABLE.md` — product plan

Written and committed. Covers the honest gap analysis, content volume targets,
progression, game feel (**haptics is the biggest single feel gap on mobile**),
audio, the **Android reality check** (nothing has run on a phone yet), store
listing, pricing, and a suggested order.

**Two things in it need your decision:**
- **Portrait vs landscape.** Landscape suits Punch-Out; portrait suits
  one-handed commute play, which is exactly when someone wants this. My lean is
  portrait — the use case beats the genre convention.
- **The AI question** (§9), with three concrete options since your message was
  garbled in transcription. Short version: use an LLM *offline* to write
  hundreds of boss lines (zero runtime cost), improve boss behaviour with plain
  weighted patterns, and treat on-device LLM as post-launch — a 1–2GB model is
  an install-conversion problem at a $2 price point.

## `a25af82` — v0.23: gimmick level framework + 2 gimmick levels

Levels plug in a mechanic **by name**. A gimmick replaces player input and boss
behaviour while reusing the same rig, damage funnel, scoring and reactions —
adding one is a couple of functions plus a `LEVELS` entry, and it doesn't touch
the fight code. That's the framework your level list needs.

- **Level 5 "Team Building" (throw)** — grab and fling him round the room.
  Gravity, damped bounces off floor/ceiling/walls, impact damage scaled by
  speed, and he spins with his own horizontal velocity.
- **Level 6 "Open Plan" (objects)** — hurl a stapler / mug / keyboard / potted
  plant. Arcs in from off-screen, detonates on arrival, checks head vs body,
  and routes through the same reaction code as a punch.

**Two bugs the filmstrip caught:** the throw had **no ceiling**, so he sailed
out of the top of the frame and vanished for seconds (5 of 12 sampled frames
had no boss on screen — now 42/42 keep him visible); and the objects level
scored zero with nothing visible because the prop PNGs **were never imported**,
so `ResourceLoader.exists()` was false and the throw bailed silently.

## v0.24 — audio polish + more Looney Tunes gags

- **Rising combo pitch** — punch pitch climbs with the combo and caps so it
  never squeaks. The classic arcade "you're on a run" cue.
- **Proper K.O. sting** — low impact boom with a noise transient under a rising
  five-note fanfare with vibrato and a ringing final note. (Was three plain
  sine notes.)
- **Six new reactions**: `spin_body`, `flatten`, `stretch_up`, `rubber_neck`
  (multi-hit head whip), `jelly_legs`, `shock_hop`.
- The reaction roll went from **3 head gags → 6**, and body criticals from one
  fixed response → **4**. Light head hits now sometimes rubber-neck too, so
  even chip damage varies.

## `a0a9268` — v0.25: 346-line dialogue bank

`scripts/dialogue.gd`. **Written offline, not generated at runtime** — that's
all the "AI in the game" idea actually needs for dialogue, at zero app size,
battery, latency or content-safety cost.

| Category | Lines |
|---|---|
| Pre-fight, per level theme | 57 |
| Taunts while guarding | 80 |
| Hit reactions | 46 |
| Miss taunts | 30 |
| Low-HP desperation | 20 |
| KO / player-down / level-win | 43 |
| Combo reactions | 15 |
| Gimmick-specific (thrown, pelted, bridge, car, moon) | 55 |

Selection is a **bag shuffle** — a category works through every line before any
repeat, so a 40-line pool never feels like five. Plain random clusters badly.

Banter is sparse and escalates: below **28% HP** he switches to the desperation
bank and starts offering raises; a 4+ combo gets its own reactions; otherwise
hits only speak ~22% of the time. Lines never interrupt one still being typed.

## `ad01f20` — v0.26: three more gimmick levels

- **Level 7 "The Offsite" (bridge)** — he teeters and constantly claws back
  toward upright; that restoring force *is* the tension. Shove from either side
  and tip him past the point of no return.
- **Level 8 "Company Car"** — tap to send the car across; impact lands partway
  through the pass, so it's a timing shot, not a free hit.
- **Level 9 "Moonshot"** — launch angle/power minigame on the existing throw
  physics. Sweeping meter picks angle, second tap sets power, distance scores.

All three plug into the v0.23 framework: a gimmick is a couple of functions
plus a `LEVELS` entry, touching none of the fight code. **Nine levels total.**

## v0.27 — portrait scaffolding (flag off by default)

`--portrait` swaps the viewport to 1080×1920, re-anchors the HUD rows, moves
the face buttons into a bottom thumb arc, re-centres the boss and repositions
the combo counter. **The default is unchanged** — this makes the orientation
call a toggle instead of a rework.

Verified in portrait: bars, bubble, boss, buttons and combo all lay out
correctly. **One gap it exposed:** `office.jpg` is landscape art, so portrait
shows dark bands top and bottom. Portrait needs either a taller background or
a cover-crop stretch — worth knowing before the orientation decision.

---

## Decisions made without you (flagged per the brief)

1. **Blink is a fast vertical head-squash**, not closed-eye art — the pose set
   has no closed-eye frame. Reads as a blink on flat cartoon art. Real eyelid
   art would be better; noted as a follow-up.
2. **Boss loses the claymation head expressions.** The 17 old `react` faces are
   replaced by 9 cut from the new set. Style consistency beat variety.
3. **Committing straight to `main`**, matching the auto-backup watcher workflow
   documented in CLAUDE.md rather than branching.

## Two decisions waiting for you

1. **Portrait vs landscape.** Scaffolding is in behind `--portrait`, so this is
   now a toggle. My lean is portrait — the use case (one-handed, commute,
   annoyed) beats the genre convention. Note that portrait needs a taller
   background; the current office art is landscape.
2. **The AI question** — `MAKE-IT-SELLABLE.md` §9, three concrete options.
   Short version: the dialogue bank shipped tonight *is* the recommended
   option, done offline at zero runtime cost. On-device LLM would add 1–2GB to
   a $2 app.

## Known rough edges

- **Glove orientation is a guess** — rotated to thrust upward, but
  `_throw_fist`'s mirror logic may want the opposite sign. One-character fix.
- **Dizzy heads are drawn larger** than neutral, so swapping pops the head size.
  Probably reads as cartoon impact; worth a look.
- Old `Body`/`Head` nodes are hidden, not deleted; `assets/boss/` is now unused.
- Unused so far: the **punch**, **walking** and **KO'd-on-ground** poses. The KO
  pose especially would suit `_knockout()` better than launching the rigged
  figure offscreen.

## v0.63 — daily grievance (retention)

A once-a-day challenge on the main menu (MAKE-IT-SELLABLE §3). The date seeds
which level and which flavour challenge ("Model Employee", "Performance review",
etc.) deterministically, so everyone gets the same one that day with no server.
Beating it grants **grievance points** (a currency) and builds a **daily
streak**; staying flawless doubles the reward. Streak only continues if the
previous claim was literally yesterday (unix-day math), else resets to 1.

Persisted under `[daily]` in the save file. Menu shows the live challenge in red,
or a greyed-out "DONE (streak N)" once claimed. A reward toast + floating
"+N GRIEVANCE" fires on completion. Points shown in the menu stats line.
Filmstrip-verified the menu button renders; headless parse clean.
