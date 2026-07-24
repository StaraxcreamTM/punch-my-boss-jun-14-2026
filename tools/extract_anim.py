"""Turn a Grok signature-move video into a keyed, trimmed, downscaled frame
sequence ready for main.gd's play_anim() slots (assets/bossN/anim/<name>/fNNN.png).

Pipeline (matches the spec the animation clips are generated to: fixed camera,
green screen, neutral start/end, full body in frame):

  1. Sample the mp4 at --fps (default 12 to keep the per-anim weight down;
     24 for hero moments where smoothness matters more than size).
  2. Chroma-key the green: border flood-fill removes the solid backdrop, a
     green-dominance test cleans stragglers, and green spill on edges is
     desaturated so there's no lime fringe under the outline shader.
  3. Trim the neutral padding: drop leading/trailing frames that barely move,
     keeping ONE neutral frame at each end as a blend bookend into the rig.
  4. Downscale to --height (default 700px tall) - the engine upscales to the
     boss render height anyway, and the toon/outline shaders hide the softness,
     so this roughly halves the ~7MB/anim budget concern.

Usage:
  python tools/extract_anim.py IN.mp4 OUT_DIR [--fps 12] [--height 700] [--key 14]
Then in Godot: an editor import pass, and call play_anim("<OUT_DIR name>", fps, cb).

Validated on the boss green-screen clip; run per clip when the mp4s land.
"""
import argparse
import os
import sys
from collections import deque

import cv2
import numpy as np


def key_green(bgr, k):
    """Return an RGBA image with the green backdrop removed."""
    h, w = bgr.shape[:2]
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB).astype(np.int16)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    is_green = (g > r + k) & (g > b + k)

    # Flood-fill the solid backdrop inward from the border so a green-ish part of
    # the character (rare) isn't punched out - only background-connected green goes.
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_green[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_green[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny, nx] and is_green[ny, nx]:
                seen[ny, nx] = True
                q.append((nx, ny))

    out = np.zeros((h, w, 4), np.uint8)
    out[:, :, 0] = rgb[:, :, 0]
    out[:, :, 1] = rgb[:, :, 1]
    out[:, :, 2] = rgb[:, :, 2]
    # Alpha: opaque unless background-connected green, or a strong green straggler.
    transparent = seen | (is_green & (g > r + k + 20) & (g > b + k + 20))
    out[:, :, 3] = np.where(transparent, 0, 255).astype(np.uint8)
    # Desaturate green spill on the kept edge pixels (lime fringe under outline).
    keep = ~transparent
    spill = keep & (g > r) & (g > b)
    cap = ((r + b) // 2 + 12).astype(np.int16)
    out[:, :, 1] = np.where(spill, np.minimum(g, cap), out[:, :, 1]).astype(np.uint8)
    return out


def content_bbox(rgba):
    a = rgba[:, :, 3]
    ys, xs = np.where(a > 20)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max(), ys.max()


def motion_diff(prev, cur):
    """Alpha-weighted mean colour difference between two RGBA frames."""
    if prev is None:
        return 1e9
    d = np.abs(cur[:, :, :3].astype(np.int16) - prev[:, :, :3].astype(np.int16)).mean()
    return float(d)


def extract(video, out_dir, fps=12.0, height=700, key=14, motion=1.4):
    """Slice one clip -> keyed/trimmed/cropped/downscaled fNNN.png. Returns the
    frame count written, or 0 on failure. Importable by the batch runner."""
    cap = cv2.VideoCapture(video)
    if not cap.isOpened():
        print("  cannot open", video)
        return 0
    src_fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    step = max(1, int(round(src_fps / fps)))
    os.makedirs(out_dir, exist_ok=True)

    frames = []
    i = 0
    while True:
        ok, f = cap.read()
        if not ok:
            break
        if i % step == 0:
            frames.append(key_green(f, key))
        i += 1
    cap.release()
    if not frames:
        print("  no frames decoded")
        return 0

    # Trim neutral padding: keep one still frame at each end as a bookend, drop
    # the rest of the dead run. Motion measured between consecutive kept frames.
    diffs = [motion_diff(frames[j - 1] if j else None, frames[j]) for j in range(len(frames))]
    active = [j for j, d in enumerate(diffs) if d >= motion]
    if active:
        lo = max(0, active[0] - 1)          # one neutral lead-in frame
        hi = min(len(frames) - 1, active[-1] + 1)
    else:
        lo, hi = 0, len(frames) - 1
    frames = frames[lo:hi + 1]

    # Crop every frame to the UNION content box across the whole clip: kills the
    # big transparent margins (most of a full-body-in-frame shot) - the single
    # biggest file-weight win - while preserving relative motion, since all
    # frames share one crop. The engine centres horizontally and floors
    # vertically, so a tight union box keeps the figure aligned.
    boxes = [content_bbox(f) for f in frames]
    boxes = [b for b in boxes if b is not None]
    if boxes:
        x0 = min(b[0] for b in boxes)
        y0 = min(b[1] for b in boxes)
        x1 = max(b[2] for b in boxes)
        y1 = max(b[3] for b in boxes)
        pad = 6
        H, W = frames[0].shape[:2]
        x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
        x1 = min(W - 1, x1 + pad); y1 = min(H - 1, y1 + pad)
        frames = [f[y0:y1 + 1, x0:x1 + 1] for f in frames]

    scale = height / frames[0].shape[0]
    n = 0
    for f in frames:
        fw = max(1, int(f.shape[1] * scale))
        fh = max(1, int(f.shape[0] * scale))
        small = cv2.resize(f, (fw, fh), interpolation=cv2.INTER_AREA)
        bgra = cv2.cvtColor(small, cv2.COLOR_RGBA2BGRA)
        cv2.imwrite(os.path.join(out_dir, "f%03d.png" % n),
                    bgra, [cv2.IMWRITE_PNG_COMPRESSION, 9])
        n += 1
    print("  wrote %d frames (from %d sampled, trimmed [%d:%d]) -> %s"
          % (n, len(diffs), lo, hi, out_dir))
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("out_dir")
    ap.add_argument("--fps", type=float, default=12.0)
    ap.add_argument("--height", type=int, default=700)
    ap.add_argument("--key", type=int, default=14, help="green-dominance threshold")
    ap.add_argument("--motion", type=float, default=1.4, help="neutral-trim threshold")
    args = ap.parse_args()
    n = extract(args.video, args.out_dir, args.fps, args.height, args.key, args.motion)
    return 0 if n > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
