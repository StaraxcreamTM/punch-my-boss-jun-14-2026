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
