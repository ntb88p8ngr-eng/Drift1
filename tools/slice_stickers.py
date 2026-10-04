"""Cuts sticker sheets (white shapes on transparent) into single stickers for the paint booth.
Each separate shape (parts closer than a few pixels count as one) becomes a PNG in assets/stickers/,
trimmed and padded to a square; near-identical ones (same silhouette) are kept only once.
Usage: python3 tools/slice_stickers.py sheet.png [sheet2.png …]  (names: <sheet index>_<n>.png)"""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage

OUT = "assets/stickers"
MERGE = 2          # px: parts closer than this belong to one sticker (and parts inside another)
MIN_SIZE = 26      # px: smaller blobs are specks
SIG = 40           # silhouette size for the duplicate test


def signature(mask):
    h, w = mask.shape
    s = max(h, w)
    pad = np.zeros((s, s), np.uint8)
    pad[(s - h) // 2:(s - h) // 2 + h, (s - w) // 2:(s - w) // 2 + w] = mask * 255
    return np.array(Image.fromarray(pad).resize((SIG, SIG), Image.BILINEAR)) > 100


def main(args):
    os.makedirs(OUT, exist_ok=True)
    kept = []        # signatures of what is already out
    names = []
    paths = []
    for a in args:
        if a.startswith("--existing="):
            # the game's own shapes: a new sticker that looks the same is left out
            d = a.split("=", 1)[1]
            for f in sorted(os.listdir(d)):
                if f.endswith(".png"):
                    m = np.array(Image.open(os.path.join(d, f)).convert("RGBA"))[..., 3] > 40
                    ys, xs = np.nonzero(m)
                    if len(ys):
                        kept.append(signature(m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]))
        else:
            paths.append(a)
    global MERGE
    for si, spec in enumerate(paths):
        bits = spec.split(":")
        path = bits[0]
        MERGE = int(bits[1]) if len(bits) > 1 and bits[1] else 2
        # "split<y>": wide pieces above y (the digit rows) are cut apart into single digits
        split_y = int(bits[2][5:]) if len(bits) > 2 and bits[2].startswith("split") else -1
        dup_limit = float(bits[3]) if len(bits) > 3 else 0.86
        img = np.array(Image.open(path).convert("RGBA"))
        alpha = img[..., 3]
        solid = alpha > 40
        grown = ndimage.binary_dilation(solid, iterations=MERGE) if MERGE > 0 else solid
        labels, n = ndimage.label(grown)
        boxes = ndimage.find_objects(labels)
        # a part lying inside another one's box (a number in its frame, the eyes in a skull) joins it
        owner = list(range(n))
        def find(i):
            while owner[i] != i:
                i = owner[i]
            return i
        area = [(b[0].stop - b[0].start) * (b[1].stop - b[1].start) for b in boxes]
        order = sorted(range(n), key=lambda i: -area[i])
        for i in order:
            bi = boxes[i]
            for j in order:
                if area[j] <= area[i] or find(j) == find(i):
                    continue
                bj = boxes[j]
                if bi[0].start >= bj[0].start - 4 and bi[0].stop <= bj[0].stop + 4 and bi[1].start >= bj[1].start - 4 and bi[1].stop <= bj[1].stop + 4:
                    owner[find(i)] = find(j)
                    break
        groups = {}
        for i in range(n):
            groups.setdefault(find(i), []).append(i)
        merged = np.zeros_like(labels)
        for gi, (root, members) in enumerate(groups.items()):
            for m in members:
                merged[labels == m + 1] = gi + 1
        labels = merged
        boxes = ndimage.find_objects(labels)
        items = []
        for k, sl in enumerate(boxes):
            if sl is None:
                continue
            part = (labels[sl] == k + 1) & solid[sl]
            ys, xs = np.nonzero(part)
            if len(ys) == 0:
                continue
            y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            if max(y1 - y0, x1 - x0) < MIN_SIZE:
                continue
            gy, gx = sl[0].start + y0, sl[1].start + x0
            m = part[y0:y1, x0:x1]
            pieces = [(0, m.shape[1])]
            split = gy + m.shape[0] < split_y
            if split and m.shape[1] > m.shape[0] * 1.15:
                # (digits set close together: a column with (almost) nothing in it is the gap between two)
                col = m.sum(axis=0)
                empty = col <= max(1, int(m.shape[0] * 0.02))
                pieces = []
                start = None
                for xi in range(m.shape[1] + 1):
                    filled = xi < m.shape[1] and not empty[xi]
                    if filled and start is None:
                        start = xi
                    elif not filled and start is not None:
                        if xi - start >= 6:
                            pieces.append((start, xi))
                        start = None
            if split:
                # two digits that touch: cut at the thinnest column round the middle
                done = []
                while pieces:
                    a, b = pieces.pop()
                    w = b - a
                    if w > m.shape[0] * 1.02 and w > 30:
                        col = m[:, a:b].sum(axis=0)
                        lo, hi = int(w * 0.3), int(w * 0.7)
                        cut = lo + int(np.argmin(col[lo:hi]))
                        if col[cut] < col.max() * 0.35:
                            pieces += [(a, a + cut), (a + cut, b)]
                            continue
                    done.append((a, b))
                pieces = sorted(done)
            for (a, b) in pieces:
                sub = m[:, a:b]
                ys2 = np.nonzero(sub.any(axis=1))[0]
                if len(ys2) == 0:
                    continue
                items.append((gy + ys2.min(), gx + a, ys2.max() + 1 - ys2.min(), b - a, sub[ys2.min():ys2.max() + 1]))
        # reading order: rows (by top, in bands), then left to right
        items.sort(key=lambda t: (t[0] // 40, t[1]))
        count = 0
        for (gy, gx, h, w, mask) in items:
            sig = signature(mask)
            dup = False
            for o in kept:
                inter = np.logical_and(sig, o).sum()
                union = np.logical_or(sig, o).sum()
                if union and inter / union > dup_limit:
                    dup = True
                    break
            if dup:
                continue
            kept.append(sig)
            crop = img[gy:gy + h, gx:gx + w].copy()
            crop[..., 3] = np.where(mask, crop[..., 3], 0)
            # white shapes keep their (grey) inner lines as shading: brighten towards white
            rgb = crop[..., :3].astype(np.float32)
            crop[..., :3] = np.clip(rgb * 0.6 + 255 * 0.4, 0, 255).astype(np.uint8)
            s = int(max(h, w) * 1.08) + 4
            sq = np.zeros((s, s, 4), np.uint8)
            oy, ox = (s - h) // 2, (s - w) // 2
            sq[oy:oy + h, ox:ox + w] = crop
            im = Image.fromarray(sq)
            if s > 256:
                im = im.resize((256, 256), Image.LANCZOS)
            name = "%d_%03d" % (si + 1, count)
            im.save(os.path.join(OUT, name + ".png"))
            names.append(name)
            count += 1
        print(path, "->", count, "stickers (", len(items) - count, "dropped as duplicates )")
    with open(os.path.join(OUT, "index.txt"), "w") as f:
        f.write("\n".join(names) + "\n")
    print("total", len(names))


main(sys.argv[1:])
