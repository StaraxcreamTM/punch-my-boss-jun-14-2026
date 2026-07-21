# Scene backdrops

Drop background art here and point a level at it — no code changes needed.

In `main.gd`, each entry in `LEVELS` accepts:

| key | meaning |
|---|---|
| `bg` | `res://assets/scenes/<file>.png` — omit for the default office |
| `bg_toon` | run the posterise/ink shader over it. Default **false**. Set true only for photographic art; it muddies flat colour. |
| `bg_fit` | `TextureRect.stretch_mode` override, if a piece needs a different fit |

Example:

    {"name": "Boardroom", "hp": 260.0, "pace": 1.0, "dmg": 12.0,
     "gimmick": "punch", "bg": "res://assets/scenes/boardroom.png",
     "line": "Take a seat. Not that one."}

Art notes:
- Design for **1920x1080**. The background is overscanned by 90px on every side
  so screen shake never reveals an edge, so keep anything important away from
  the extreme border.
- A missing file falls back to the office with a warning rather than a black
  screen, so a typo can't break a level.
