"""Pull one clean full-frame still from a video, for use as an arena background.

Some backgrounds generate as short videos (e.g. the Boardroom clip). A background
is a full scene, NOT a green-screened character, so there's no keying/trimming —
just grab a representative frame at full resolution.

  python tools/extract_bg.py IN.mp4 OUT.png            # middle frame
  python tools/extract_bg.py IN.mp4 OUT.png --at 0.3   # 30% through the clip
  python tools/extract_bg.py IN.mp4 OUT.png --frame 45 # a specific frame index

Pick a frame with no motion blur and nothing mid-transition. Then drop OUT.png in
game/assets/scenes/ (or bg/) and point an arena's `bg` key at it.
"""
import argparse
import sys

import cv2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("out")
    ap.add_argument("--at", type=float, default=0.5,
                    help="fractional position through the clip (0..1); default middle")
    ap.add_argument("--frame", type=int, default=-1,
                    help="explicit frame index; overrides --at")
    args = ap.parse_args()

    cap = cv2.VideoCapture(args.video)
    if not cap.isOpened():
        print("cannot open", args.video)
        return 1
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 1
    idx = args.frame if args.frame >= 0 else int(max(0, min(total - 1, round(total * args.at))))
    cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
    ok, frame = cap.read()
    cap.release()
    if not ok:
        print("could not read frame", idx)
        return 1
    cv2.imwrite(args.out, frame)
    print("wrote frame %d/%d (%dx%d) -> %s"
          % (idx, total, frame.shape[1], frame.shape[0], args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
