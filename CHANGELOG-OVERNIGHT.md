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

---

## Decisions made without you (flagged per the brief)

1. **Blink is a fast vertical head-squash**, not closed-eye art — the pose set
   has no closed-eye frame. Reads as a blink on flat cartoon art. Real eyelid
   art would be better; noted as a follow-up.
2. **Boss loses the claymation head expressions.** The 17 old `react` faces are
   replaced by 9 cut from the new set. Style consistency beat variety.
3. **Committing straight to `main`**, matching the auto-backup watcher workflow
   documented in CLAUDE.md rather than branching.

## Known rough edges

- **Glove orientation is a guess** — rotated to thrust upward, but
  `_throw_fist`'s mirror logic may want the opposite sign. One-character fix.
- **Dizzy heads are drawn larger** than neutral, so swapping pops the head size.
  Probably reads as cartoon impact; worth a look.
- Old `Body`/`Head` nodes are hidden, not deleted; `assets/boss/` is now unused.
- Unused so far: the **punch**, **walking** and **KO'd-on-ground** poses. The KO
  pose especially would suit `_knockout()` better than launching the rigged
  figure offscreen.
