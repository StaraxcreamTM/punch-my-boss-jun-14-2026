# Pending art wave — integration manifest

Everything here is **blocked on the Chrome download gate**. When the user
unblocks downloads and the files land in `C:\Users\bryon\Downloads`, integrate
per the notes below. Nothing is fabricated — only integrate files actually on disk.

## Signature-move videos — round 1 (manifest 2026-07-23)

Grok video posts on the user's account; download clicks made, presumed still
gated. Expect `Recording`-style / `grok-video-*.mp4` (~5–15MB each).

| Clip | Post ID | Wire to |
|---|---|---|
| **Terry TAUNT** (belly-laugh, pats belly ×2, 10s) | `36238605-0bd9-4800-8c2e-3ebaf0cffe1f` | Terry (boss3/`big`) taunt / signature during GUARD |
| **Terry JAB** (big wind-up right jab to camera, 10s) | `3a0d530c-dbc6-48be-bc08-7c1cc6b0aa6e` | Terry attack tell / signature strike |
| **Terry HURT** (reel-back, belly jiggle, arm windmill, dizzy wobble, 10s) | `306ec948-cb15-4cd0-a52f-c63e837bee2a` | Terry crit reaction / enrage-threshold stagger (`boss3/anim/hurt`) |
| **Main boss HURT** (comic reel-back, head snap, dizzy wobble, 10s, **2 variants** on the post) | `a7f84641-7dbe-4377-97e8-d7c2d5a8974e` | Main boss (boss2/`suit`) big-hit reaction or enrage-threshold stagger |
| **Main boss TAUNT** (finger-wag + laugh, 10s) | `97ad24f4-a6ee-4a6a-bfb8-3ddd261ae7b2` | Main boss (boss2) GUARD-phase signature (`boss2/anim/taunt`) |
| **Main boss JAB** (wind-up jab to camera, 10s) | `02a71d4f-aae1-4f2d-a49f-8fe8b76ac67d` | Main boss attack tell / signature strike (`boss2/anim/jab`) — supersedes the older `52c33b12` take |
| ~~junk~~ | `1b7b12d1-6cfa-4805-8d7d-f8cbfef00885` | **IGNORE** — wrong reference (desktop screenshot) |

### How to integrate (proven pipeline)
1. `python tools/extract_anim.py IN.mp4 game/assets/boss<N>/anim/<slot>/ --fps 12 --height 700`
   - `--fps 8 --height 560` if a clip runs heavy; target **<7MB/anim**.
   - Tool keys the green, auto-trims neutral padding to bookend frames, crops the
     transparent margins, downscales. **Validated** on the boss green clip
     (`52c33b12`) — keying is clean, per-frame ~144KB@560h.
2. Editor import pass: `Godot --headless --editor --path game --quit`.
3. Wire with a guarded call so it's inert until frames exist:
   `if has_anim("<slot>"): play_anim("<slot>", 12.0, <callback>)`
   - HURT: trigger from `_react_hit` on a crit (or at the 50% enrage threshold).
   - JAB / TAUNT: from the windup/attack path, or `play_signature` during GUARD.
4. Filmstrip-verify (`--shots --nomenu --level=N`) — confirm a SINGLE boss (the
   v0.74 mutex fix keeps rig/overlay exclusive) and a clean fade handoff (v0.75).

## Older Jul-21 grok-video batch — already on disk, NOT in the round-1 manifest
Present in Downloads but unaddressed; flagged, untouched:
- `grok-video-52c33b12…mp4` — main boss on green, a JAB/attack move. **Usable** —
  used only to validate the extraction tool (frames in scratch, not integrated).
- `grok-video-05e1e933…mp4` (×4) — green-screen cartoon women (bikini/gag). Could
  be women-boss KO/reaction clips; **await the user's word** before integrating.
- `grok-video-{b446c6ab,ba295b43,e6db6a13}…mp4` — **photorealistic videos of a
  real person (bed/balcony). NOT game assets, look personal. Do not process,
  integrate, or view. Left entirely untouched.**

## Still-image backlog (from earlier)
Correct Bev/Nina/Marcus/Sandra/Terry expression sets, 11 backgrounds, 6 themed
boss bases. Harvest neutrals from each base body (the Terry method). See
`ART-INBOX-IGNORE.txt` for the Jul-22 duplicate set to skip.
