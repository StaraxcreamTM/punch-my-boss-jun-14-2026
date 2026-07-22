# Making Punch My Boss a $2–3 paid Android game

Product plan, written as a plan — not a promise. Ordered by what actually moves
the needle on "would someone pay for this."

---

## 1. The honest read on where it stands

**What's genuinely good already:** the core loop is real (telegraph → dodge →
punish), the reactions are funny, the art has a strong identity, and the rig
supports far more animation than is currently used.

**What would stop someone paying today:**

| Gap | Why it matters |
|---|---|
| ~2 minutes of content | Paid casual games need 30–60 min minimum before "I'm done" |
| One background, one boss | Looks like a demo the moment you see the second fight |
| No progression you keep | Nothing to come back to tomorrow |
| No reason to replay a level | Score exists but nothing chases it |
| Untested on a real phone | **The single biggest unknown — see §6** |

The premise is the asset here. "Beat up your boss" sells itself in a screenshot;
the job is making the second five minutes as good as the first thirty seconds.

---

## 2. Content volume — the top priority

Comparable paid casual games ship **20–40 distinct encounters**. The level
framework exists; it needs filling.

- **8–12 bosses**, each with its own tell, rhythm and dialogue set. The rig
  makes this cheap: a boss is a look + a timing profile + lines, not new code.
- **3–4 environments** (cubicle farm, corner office, boardroom, parking garage).
  Backgrounds are the cheapest perceived-value win in the game.
- **The gimmick levels** from your list — strangle, throw-around, throw-things,
  bridge, car, moon. These are what makes it *memorable* rather than "a boxing
  game." They don't all need to be deep; they need to be surprising.
- **~150 lines of boss dialogue.** Cheap to write, enormously high value for a
  comedy game. This is where the personality lives.

## 3. Progression worth keeping

- **Career mode**: intern → manager → VP → CEO, unlocking bosses and arenas
- **Unlockable cosmetics** paid for with in-game currency: gloves, arenas, and
  more of the customisation layers that already exist
- **Daily "grievance"**: one generated challenge a day ("KO him without taking a
  hit"). Cheap retention, no server needed
- **Stat tracking**: total punches thrown, boss's worst day, longest combo. Feeds
  the stress-relief fantasy directly

## 4. Game feel (cheapest quality-per-hour in the whole list)

- **Haptics on every hit** — on mobile this is *half* the punch. Currently absent
  and it's the single biggest feel gap
- Hit-stop tuning pass, and a distinct sound per hit type
- Voice grunts (even a few) transform perceived production value
- More Looney Tunes reaction variety — the rig supports it, the library is
  written, it just needs more entries

## 5. Audio

Procedural chiptune is a great placeholder and ships zero assets, but for a paid
title: 3–4 real music tracks and ~20 sound effects. This is the most obvious
"outsource it" line item — a few hundred dollars of freelance audio would lift
the whole product.

## 6. Android reality check — do this before building more content

**Nothing has run on a phone yet.** Everything below is unverified and any of it
could force rework, so it should happen early:

- **Touch controls.** Dodging is on arrow keys. On a phone it needs swipe-left /
  swipe-right / swipe-down, and they must not conflict with tap-to-punch
- **Orientation.** Currently landscape. Landscape is right for a Punch-Out feel,
  but portrait is right for one-handed toilet-and-commute play, which is exactly
  when someone wants to punch their boss. **This is a real decision and I'd want
  your call.** My lean: portrait, because the use case beats the genre
  convention here
- **Safe areas** — already handled in code, unverified on a notched device
- **Performance target**: 60fps on a mid-range 2021 phone. The renderer is
  already Forward Mobile. The shaders (toon background, per-piece outline) are
  the most likely cost — the outline shader does 8 texture samples per pixel per
  piece, and there are 16 pieces
- **Build size** under 100MB. Currently trivial, but the raw source art in
  `assets/boss2/raw/` (~2.8MB of jpgs) should be excluded from export

## 7. Store listing

- Icon (the boss's face mid-punch — instantly communicates the game)
- 5–6 screenshots, each showing a *different* boss or gimmick
- A 15–30s trailer — this sells comedy games more than screenshots do
- The description writes itself; lean into the premise
- **Content rating**: cartoon violence is fine, but the toilet-humour levels
  (pee, poop) will push the rating up and may cost you some markets. Worth
  deciding deliberately rather than discovering at submission

## 8. Pricing

$2–3 is right for the premise. Two viable shapes:

1. **Paid up front** — clean, no dark patterns, fits "stress relief" (you don't
   want a paywall between someone and their catharsis)
2. **Free with a one-time unlock** after ~3 bosses — usually converts better on
   Android, where paid-up-front has a much weaker culture than iOS

I'd lean **free with one-time unlock**, purely because Android paid conversion
is hard and the first fight is a great advert for the rest.

---

## 9. AI in the game — options for your decision

Your message about "adding AI into the game" was garbled in transcription, so
here are the realistic readings. **Nothing has been integrated.**

### Option A — better scripted behaviour (no AI, honestly)
Weighted attack patterns, adaptive difficulty that reads the player's dodge
accuracy and adjusts. **This is what "smarter boss" actually means in practice**
and it needs no dependency, no size cost, no network.
*Cost: a few hours. Risk: none.* **Recommended starting point.**

### Option B — LLM-written dialogue, generated offline
Use a model *during development* to write 500+ boss lines, personality-tagged
per boss. You get the variety benefit with **zero runtime cost, zero app-size
cost, zero privacy surface**.
*Cost: cheap. Risk: none.* **Best value of the three — recommended.**

### Option C — on-device LLM for live trash-talk
A small model (~1–2GB quantised) generating dialogue reactive to the fight.

- **Against:** app size goes from ~50MB to well over 1GB, which is a serious
  install-conversion problem at a $2 price point; noticeable battery drain; slow
  on mid-range devices; and an unfiltered model saying something ugly in a
  comedy game about your boss is a real content-safety risk
- **For:** genuinely novel, and "the boss roasts *you* personally" is a great
  hook

**My recommendation: B now, A alongside it, and treat C as a post-launch
experiment** — possibly as a cloud call rather than on-device, if it's worth a
server bill at all. If you saw a specific Godot addon, point me at it and I'll
assess that one concretely rather than in the abstract.

---

## 10. Suggested order

1. **Android build on a real device** — touch controls + orientation decision
2. **Content volume** — bosses, arenas, gimmick levels, dialogue
3. **Haptics + audio pass**
4. **Progression + unlocks**
5. **Store assets**

Steps 1 and 2 are the difference between a demo and a product. Everything else
is polish on top of that.

## 11. Future combat mechanics (from the Big Boy Boxing study)

These raise the skill ceiling and give the high-risk/high-reward loop that
carries a paid boxing-like. Noted here for a later pass:

- **Parry** — a tight-timing tap (vs. the forgiving holdable dodge) that, hit on
  the strike frame, staggers the boss into an extended punish window instead of
  just avoiding damage. High risk (miss = you eat it), high reward. Slots into
  the existing `_resolve_attack` timing check.
- **Adrenaline / rush meter** — builds on parries and clean dodges, spends on a
  brief damage-and-speed surge (distinct from the current FRENZY, which builds
  on landing hits). Rewards aggressive precise play.
- **Per-boss secret mechanic** — one hidden interaction per boss for the
  community to discover (Big Boy Boxing shipped these per fight). Cheap to add
  one-off, strong word-of-mouth hook.

Already shipped from that study: cartoon snap-hold timing, impact smears/squash,
holdable dodges, and the 50%-HP enrage transformation (prototype on levels 3-4).
