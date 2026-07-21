"""ABANDONED: programmatic glasses removal from the boss head textures.

Kept as a record of what was tried, not as a working tool. Three approaches,
three different artifacts:

1. Flood-fill inpaint  -> smeared grey along rays. It seeded from imperfectly
   classified edge pixels and propagated one colour outward.
2. Flat skin fill      -> left a visible ghost RECTANGLE. The sampled tone was
   ~5 units off the surrounding skin, so the patch boundary read as a frame.
3. Per-column sampling -> vertical streaks, because columns near the eyebrows
   sampled different tones than columns near the temples.

Root cause: at this resolution the frame's anti-aliased edge and the eye art
are entangled. Every classifier wide enough to catch the frame halo also
clips the eye outline, and every fill smooth enough to hide the seam pulls in
colour from somewhere it shouldn't.

The right fix is a hand-drawn glasses-off head (one per expression, 9 total),
not inpainting. Until then "no glasses" is not an available customisation
option - accessories can be ADDED to the head, but the baked-in glasses cannot
be removed cleanly.
"""

import sys
from collections import deque

from PIL import Image


def is_lensish(c):
    r, g, b, a = c
    return a > 100 and abs(r - g) < 20 and abs(g - b) < 26 and 118 < r < 236


def is_ink(c):
    r, g, b, a = c
    return a > 100 and max(r, g, b) < 100


def is_sclera(c):
    r, g, b, a = c
    return a > 100 and min(r, g, b) > 232


def lens_boxes(px, W, H):
    seen = [[False] * W for _ in range(H)]
    comps = []
    for sy in range(H):
        for sx in range(W):
            if seen[sy][sx] or not is_lensish(px[sx, sy]):
                continue
            q = deque([(sx, sy)])
            seen[sy][sx] = True
            comp = []
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and is_lensish(px[nx, ny]):
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if len(comp) >= 400:
                comps.append(comp)
    comps.sort(key=len, reverse=True)
    out = []
    for comp in comps[:2]:
        xs = [c[0] for c in comp]
        ys = [c[1] for c in comp]
        out.append([min(xs), min(ys), max(xs), max(ys)])
    out.sort(key=lambda b: b[0])
    return out


def skin_tone(px, W, H, boxes):
    """Sample skin from the cheek band just below the lenses."""
    y0 = max(b[3] for b in boxes) + 14
    cx = (boxes[0][0] + boxes[1][2]) // 2
    best = None
    for y in range(y0, min(H, y0 + 40)):
        for x in range(max(0, cx - 70), min(W, cx + 70)):
            c = px[x, y]
            if c[3] > 200 and not is_ink(c) and not is_lensish(c) and c[0] > c[2] + 25:
                best = c
                break
        if best:
            break
    return best or (206, 159, 115, 255)


def deglass(path, out_path):
    im = Image.open(path).convert("RGBA")
    W, H = im.size
    px = im.load()
    boxes = lens_boxes(px, W, H)
    if len(boxes) < 2:
        return None, "found %d lens blobs (need 2)" % len(boxes)
    skin = skin_tone(px, W, H, boxes)

    out = im.copy()
    op = out.load()
    pad = 12

    def local_skin(x, y, y0, y1):
        """Nearest warm skin pixel straight above / below this column.

        A single sampled tone left a visible rectangle: the fill was ~5 units
        off the surrounding skin, so the patch boundary read as a ghost frame.
        Sampling per column follows the face's own vertical shading instead.
        """
        up = None
        for yy in range(y0 - pad - 2, max(-1, y0 - pad - 60), -1):
            if yy < 0:
                break
            c = px[x, yy]
            if c[3] > 200 and not is_ink(c) and not is_lensish(c) and c[0] - c[2] > 25:
                up = (c, y - yy)
                break
        dn = None
        for yy in range(y1 + pad + 2, min(H, y1 + pad + 60)):
            c = px[x, yy]
            if c[3] > 200 and not is_ink(c) and not is_lensish(c) and c[0] - c[2] > 25:
                dn = (c, yy - y)
                break
        if up and dn:
            return up[0] if up[1] <= dn[1] else dn[0]
        if up:
            return up[0]
        if dn:
            return dn[0]
        return skin
    for (x0, y0, x1, y1) in boxes:
        for y in range(max(0, y0 - pad), min(H, y1 + pad + 1)):
            for x in range(max(0, x0 - pad), min(W, x1 + pad + 1)):
                c = px[x, y]
                if c[3] < 60:
                    continue
                inner = (x0 + 2 <= x <= x1 - 2) and (y0 + 2 <= y <= y1 - 2)
                # Keep the eye: ink strokes and sclera inside the lens survive.
                if inner and (is_ink(c) or is_sclera(c)):
                    continue
                if is_lensish(c) or is_ink(c):
                    op[x, y] = local_skin(x, y, y0, y1)
                elif not inner and (c[0] - c[2]) < 30:
                    # Anti-aliased frame edge: neither ink nor lens by colour,
                    # but not warm skin either. Left alone it drew a dashed
                    # ghost rectangle exactly where the frame had been.
                    op[x, y] = local_skin(x, y, y0, y1)

    # Bridge over the nose.
    lb, rb = boxes
    by0, by1 = min(lb[1], rb[1]), min(lb[3], rb[3])
    for y in range(by0, by0 + int((by1 - by0) * 0.66)):
        for x in range(lb[2] - 3, rb[0] + 4):
            if 0 <= x < W and 0 <= y < H and (is_ink(px[x, y]) or is_lensish(px[x, y])):
                op[x, y] = skin

    # Temple arms out toward the ears.
    for (bx0, byy0, bx1, byy1), step in ((lb, -1), (rb, +1)):
        ty0 = byy0
        ty1 = byy0 + int((byy1 - byy0) * 0.45)
        for y in range(max(0, ty0), min(H, ty1)):
            x = bx0 - 1 if step < 0 else bx1 + 1
            gap = 0
            while 0 <= x < W and gap < 22:
                c = px[x, y]
                if is_ink(c) or is_lensish(c):
                    op[x, y] = skin
                    gap = 0
                else:
                    gap += 1
                x += step
    out.save(out_path)
    return out, "boxes=%s skin=%s" % (boxes, skin[:3])


if __name__ == "__main__":
    img, msg = deglass(sys.argv[1], sys.argv[2])
    print(("OK " if img else "FAIL ") + str(msg))
