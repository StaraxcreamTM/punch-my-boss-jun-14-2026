"""Batch clip slicer — turns the whole signature-clip manifest into play_anim()
frame dirs in one run, the moment the mp4s land in Downloads.

Reads tools/anim_manifest.json. For each clip it resolves a source mp4 (explicit
'file', else a 'match' glob against the downloads dir), slices it through
extract_anim.extract() into game/assets/<slot>/, and reports what built, what
was skipped (already present), and what's still waiting on a file.

  python tools/build_anims.py                 # build everything resolvable
  python tools/build_anims.py --force         # rebuild even if frames exist
  python tools/build_anims.py --only boss3/anim/jab

Idempotent: a slot that already has f000.png is skipped unless --force. After a
build, run the Godot editor import pass so Godot imports the PNGs:
  Godot --headless --editor --path game --quit
"""
import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_anim  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def resolve_source(clip, downloads):
    """Return the source mp4 path for a clip, or None if not present yet."""
    f = str(clip.get("file", "")).strip()
    if f:
        p = f if os.path.isabs(f) else os.path.join(downloads, f)
        return p if os.path.exists(p) else None
    m = str(clip.get("match", "")).strip()
    if m:
        hits = sorted(glob.glob(os.path.join(downloads, m)), key=os.path.getmtime)
        if hits:
            idx = int(clip.get("variant", -1))          # -1 => newest match
            return hits[idx] if -len(hits) <= idx < len(hits) else hits[-1]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=os.path.join(HERE, "anim_manifest.json"))
    ap.add_argument("--force", action="store_true", help="rebuild slots that already have frames")
    ap.add_argument("--only", default="", help="build just this one slot")
    args = ap.parse_args()

    with open(args.manifest, encoding="utf-8") as fh:
        cfg = json.load(fh)
    downloads = cfg.get("downloads", "")
    game_root = os.path.join(REPO, cfg.get("game_root", "game/assets"))
    d_fps = float(cfg.get("default_fps", 12))
    d_h = int(cfg.get("default_height", 700))

    built, skipped, missing = [], [], []
    for clip in cfg.get("clips", []):
        slot = clip["slot"]
        if args.only and slot != args.only:
            continue
        out_dir = os.path.join(game_root, slot)
        if not args.force and os.path.exists(os.path.join(out_dir, "f000.png")):
            skipped.append(slot)
            continue
        src = resolve_source(clip, downloads)
        if src is None:
            missing.append(slot)
            continue
        print("building %s  <-  %s" % (slot, os.path.basename(src)))
        n = extract_anim.extract(
            src, out_dir,
            fps=float(clip.get("fps", d_fps)),
            height=int(clip.get("height", d_h)),
            key=int(clip.get("key", 14)),
            motion=float(clip.get("motion", 1.4)),
        )
        (built if n > 0 else missing).append(slot)

    print("\n== summary ==")
    print("built  :", ", ".join(built) or "(none)")
    print("skipped:", ", ".join(skipped) or "(none)", "(already present; --force to rebuild)")
    print("waiting:", ", ".join(missing) or "(none)", "(set 'file' in the manifest once the mp4 lands)")
    if built:
        print("\nNow run the import pass:  Godot --headless --editor --path game --quit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
