#!/usr/bin/env python3
"""Builds the data of the "Grüne Hölle" track (a Nordschleife replica) from open data.

Sources (downloaded once into --cache):
  * course: the guard rails along the Nordschleife (OpenStreetMap, via the Overture Maps base theme
    on AWS S3). The rails are dilated into a closed ring, the gaps between them filled, and the ring's
    medial axis is the centreline.
  * elevation: AWS Terrain Tiles (Terrarium PNG, zoom 14 – SRTM / EU-DEM based).
  * forest / fields / villages: Overture Maps land cover (derived from ESA WorldCover).

Writes to assets/tracks/gruene_hoelle/:
  centerline.bin  float32 x, y, z per sample (2 m apart, driving direction, sample 0 on the T13 straight)
  dem.bin         deflate: uint16 height in cm above meta.dem_min, row-major (nz rows of nx)
  cover.bin       deflate: 3 bytes per cell (forest, field, village) 0..255, same grid as the DEM
  meta.json       grid layout, height reference, section names, attribution

Local frame: x = east, z = south (metres), y = height above meta.h0 (the start line is near y = 0).

Needs: numpy scipy pillow shapely pyarrow scikit-image networkx
"""
import argparse
import json
import math
import os
import subprocess
import zlib

import numpy as np
import networkx as nx
import pyarrow.compute as pc
import pyarrow.dataset as ds
import pyarrow.fs as pafs
import pyarrow.parquet as pq
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.ndimage import gaussian_filter1d, map_coordinates
from shapely import wkb
from skimage.draw import line as draw_line
from skimage.morphology import skeletonize

LAT0, LON0 = 50.355, 6.965
PHI = math.radians(LAT0)
M_LAT = 111132.954 - 559.822 * math.cos(2 * PHI) + 1.175 * math.cos(4 * PHI)
M_LON = 111412.84 * math.cos(PHI) - 93.5 * math.cos(3 * PHI) + 0.118 * math.cos(5 * PHI)
BBOX = (6.85, 50.28, 7.09, 50.43)          # lon/lat of everything we download
OVERTURE = "overturemaps-us-west-2/release/2026-09-23.1"
TILE_Z = 14
SPACING = 2.0
GRID_CELL = 10.0
GRID_HALF = (5400.0, 5000.0)               # grid reaches ±x / ±z around the local origin

# The start area (T13): the rails end where the pit walls start. These walls and two short closing
# lines keep the corridor ring shut (lon/lat).
T13_BOX = ((6.9481, 50.3370), (6.9517, 50.3391))
T13_CLOSE = [((6.949062, 50.3379978), (6.9497942, 50.3379978)),
             ((6.9506389, 50.3375456), (6.9506953, 50.3372562))]
START_GEO = (6.9500758, 50.3380249)         # on the T13 straight, heading north-west
# The two legs of the Karussell run so close together that their rails merge into one band: a slit
# along the middle barrier (from the tip out into the open ground north-east of the fork) keeps them
# apart, otherwise the medial axis would cut the corner off (lon/lat).
KARUSSELL_SLIT = [(6.9859221, 50.3720022), (6.9864008, 50.3722735), (6.986964, 50.37259), (6.9875272, 50.3728613),
                  (6.9880903, 50.3731327), (6.9886535, 50.3733587), (6.9891463, 50.3735577), (6.9894983, 50.3738109),
                  (6.9898925, 50.3740099)]

# Section names in driving order with the anchor they are measured from. Anchors are found in the
# geometry ("west" = westernmost point, "low" = lowest point, "karussell" = tightest left hairpin
# after Kesselchen, "high" = highest point after it, "loop" = the Schwalbenschwanz hairpin,
# "straight" = start of the Döttinger Höhe); the other names sit at their real share between anchors.
SECTIONS = [
    ("T13 Start/Ziel", "start", 0.00), ("Sabine-Schmitz-Kurve", "start", 0.06),
    ("Hatzenbach", "start", 0.27), ("Hocheichen", "start", 0.55), ("Quiddelbacher Höhe", "start", 0.64),
    ("Flugplatz", "start", 0.71), ("Kottenborn", "start", 0.80), ("Schwedenkreuz", "start", 0.90),
    ("Aremberg", "west", 0.00), ("Fuchsröhre", "west", 0.12), ("Adenauer Forst", "west", 0.33),
    ("Metzgesfeld", "west", 0.50), ("Kallenhard", "west", 0.62), ("Wehrseifen", "west", 0.85),
    ("Breidscheid", "low", 0.00), ("Ex-Mühle", "low", 0.07), ("Bergwerk", "low", 0.22),
    ("Kesselchen", "low", 0.40), ("Mutkurve", "low", 0.66), ("Klostertal", "low", 0.76),
    ("Steilstrecke", "low", 0.90), ("Karussell", "karussell", 0.00), ("Hohe Acht", "high", 0.00),
    ("Hedwigshöhe", "high", 0.13), ("Wippermann", "high", 0.25), ("Eschbach", "high", 0.38),
    ("Brünnchen", "high", 0.50), ("Eiskurve", "high", 0.62), ("Pflanzgarten", "high", 0.72),
    ("Sprunghügel", "high", 0.84), ("Schwalbenschwanz", "loop", 0.00), ("Kleines Karussell", "loop", 0.12),
    ("Galgenkopf", "loop", 0.45), ("Döttinger Höhe", "straight", 0.00), ("Antoniusbuche", "straight", 0.80),
    ("Tiergarten", "straight", 0.88), ("Hohenrain", "straight", 0.95),
]


def local(lon, lat):
    return (np.asarray(lon) - LON0) * M_LON, -(np.asarray(lat) - LAT0) * M_LAT


def geo(x, z):
    return np.asarray(x) / M_LON + LON0, -np.asarray(z) / M_LAT + LAT0


# ---------------------------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------------------------
def overture(cache, theme, kind, columns):
    path = os.path.join(cache, f"{theme}_{kind}.parquet")
    if not os.path.exists(path):
        s3 = pafs.S3FileSystem(anonymous=True, region="us-west-2")
        d = ds.dataset(f"{OVERTURE}/theme={theme}/type={kind}/", filesystem=s3, format="parquet")
        x0, y0, x1, y1 = BBOX
        flt = ((pc.field("bbox", "xmin") < x1) & (pc.field("bbox", "xmax") > x0)
               & (pc.field("bbox", "ymin") < y1) & (pc.field("bbox", "ymax") > y0))
        print(f"downloading overture {theme}/{kind} …")
        pq.write_table(d.to_table(filter=flt, columns=columns), path)
    return pq.read_table(path).to_pylist()


def tile_xy(lon, lat):
    n = 2 ** TILE_Z
    r = np.radians(lat)
    return (np.asarray(lon) + 180.0) / 360.0 * n, (1.0 - np.log(np.tan(r) + 1.0 / np.cos(r)) / math.pi) / 2.0 * n


def dem_mosaic(cache):
    x0, y0, x1, y1 = BBOX
    tx0, ty1 = [int(v) for v in tile_xy(x0, y0)]
    tx1, ty0 = [int(v) for v in tile_xy(x1, y1)]
    out = np.zeros(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256), np.float32)
    os.makedirs(os.path.join(cache, "tiles"), exist_ok=True)
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            f = os.path.join(cache, "tiles", f"{TILE_Z}_{tx}_{ty}.png")
            if not os.path.exists(f):
                url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{TILE_Z}/{tx}/{ty}.png"
                subprocess.run(["curl", "-sf", "-m", "60", "-o", f, url], check=True)
            a = np.asarray(Image.open(f).convert("RGB")).astype(np.float32)
            out[(ty - ty0) * 256:(ty - ty0 + 1) * 256, (tx - tx0) * 256:(tx - tx0 + 1) * 256] = \
                a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0
    return out, tx0, ty0


def dem_sample(mosaic, x, z, order=1):
    lon, lat = geo(x, z)
    tx, ty = tile_xy(lon, lat)
    m, tx0, ty0 = mosaic
    return map_coordinates(m, [(ty - ty0) * 256 - 0.5, (tx - tx0) * 256 - 0.5], order=order, mode="nearest")


# ---------------------------------------------------------------------------------------------
# Course
# ---------------------------------------------------------------------------------------------
def rail_lines(infra):
    (bx0, by0), (bx1, by1) = T13_BOX
    lines = []
    for r in infra:
        if r["class"] not in ("guard_rail", "jersey_barrier", "wall"):
            continue
        g = wkb.loads(r["geometry"])
        if g.geom_type != "LineString" or g.length <= 0:
            continue
        c = np.array(g.coords)[:, :2]
        if r["class"] == "wall":
            m = (c[:, 0] > bx0) & (c[:, 0] < bx1) & (c[:, 1] > by0) & (c[:, 1] < by1)
            if m.sum() < 2:
                continue
            c = c[m]
        lines.append(np.stack(local(c[:, 0], c[:, 1]), 1))
    for a, b in T13_CLOSE:
        lines.append(np.stack(local(np.array([a[0], b[0]]), np.array([a[1], b[1]])), 1))
    return lines


def bridge_gaps(lines, max_gap=180.0):
    """Joins rail ends that continue each other (same direction, facing each other)."""
    ends = []
    for i, rl in enumerate(lines):
        for seq in (rl, rl[::-1]):
            j = len(seq) - 1
            while j > 0 and np.linalg.norm(seq[-1] - seq[j - 1]) < 15.0:
                j -= 1
            d = seq[-1] - seq[max(j - 1, 0)]
            n = np.linalg.norm(d)
            if n > 0.1:
                ends.append((i, seq[-1], d / n))
    cos30 = math.cos(math.radians(30))
    out = []
    for i, p, d in ends:
        best = None
        for j, q, dq in ends:
            if j == i:
                continue
            v = q - p
            length = np.linalg.norm(v)
            if length < 0.5 or length > max_gap:
                continue
            u = v / length
            if u.dot(d) < cos30 or (-u).dot(dq) < cos30:
                continue
            if best is None or length < best[0]:
                best = (length, q)
        if best:
            out.append(np.array([p, best[1]]))
    return out


def centreline(lines, radius=12.0, cell=2.0):
    allp = np.concatenate(lines)
    mn = allp.min(0) - 300.0
    mx = allp.max(0) + 300.0
    w, h = int((mx[0] - mn[0]) / cell) + 1, int((mx[1] - mn[1]) / cell) + 1
    grid = np.zeros((h, w), bool)
    for rl in lines:
        for a, b in zip(rl[:-1], rl[1:]):
            rr, cc = draw_line(int((a[1] - mn[1]) / cell), int((a[0] - mn[0]) / cell),
                               int((b[1] - mn[1]) / cell), int((b[0] - mn[0]) / cell))
            grid[rr, cc] = True
    band = ndi.distance_transform_edt(~grid) * cell <= radius
    slit = np.zeros_like(grid)
    sl = np.stack(local(*np.array(KARUSSELL_SLIT).T), 1)
    for a, b in zip(sl[:-1], sl[1:]):
        rr, cc = draw_line(int((a[1] - mn[1]) / cell), int((a[0] - mn[0]) / cell),
                           int((b[1] - mn[1]) / cell), int((b[0] - mn[0]) / cell))
        slit[rr, cc] = True
    band &= ~ndi.binary_dilation(slit)
    lab, _ = ndi.label(~band)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    seed = lab[int((0 - mn[1]) / cell), int((0 - mn[0]) / cell)]
    if seed in border:
        raise SystemExit("the rail ring is not closed – a gap is left open")
    ring = ~((lab == seed) | np.isin(lab, list(border)))
    sk = skeletonize(ring)
    ys, xs = np.nonzero(sk)
    idx = {(y, x): i for i, (y, x) in enumerate(zip(ys, xs))}
    g = nx.Graph()
    for (y, x), i in idx.items():
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                j = idx.get((y + dy, x + dx))
                if j is not None and j != i:
                    g.add_edge(i, j)
    while True:
        leaves = [v for v in g if g.degree(v) <= 1]
        if not leaves:
            break
        g.remove_nodes_from(leaves)
    cyc = max(nx.cycle_basis(g), key=len)
    return np.array([[xs[i] * cell + mn[0] + cell / 2, ys[i] * cell + mn[1] + cell / 2] for i in cyc])


def resample(p, step):
    q = np.vstack([p, p[:1]])
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(q, axis=0), axis=1))])
    n = int(round(s[-1] / step))
    t = np.linspace(0.0, s[-1], n, endpoint=False)
    return np.stack([np.interp(t, s, q[:, 0]), np.interp(t, s, q[:, 1])], 1)


def smooth_loop(p, sigma):
    return np.stack([gaussian_filter1d(p[:, 0], sigma, mode="wrap"), gaussian_filter1d(p[:, 1], sigma, mode="wrap")], 1)


def curvature(p):
    t = np.gradient(p, axis=0)
    return np.gradient(np.unwrap(np.arctan2(t[:, 1], t[:, 0]))) / SPACING


def adaptive_smooth(p):
    """Medial-axis kinks (a rail missing on one side shifts the axis) vanish on the straights under a
    50 m gaussian; in the corners a 12 m one keeps the shape. Blended by the corner sharpness."""
    light = smooth_loop(p, 12.0 / SPACING)
    heavy = smooth_loop(p, 50.0 / SPACING)
    kh = gaussian_filter1d(np.abs(curvature(heavy)), 10, mode="wrap")
    w = gaussian_filter1d(np.clip((kh - 1 / 700) / (1 / 180 - 1 / 700), 0, 1), 15, mode="wrap")
    return heavy * (1 - w)[:, None] + light * w[:, None]


def profile(mosaic, pts):
    raw = dem_sample(mosaic, pts[:, 0], pts[:, 1])
    # canopy and bridges show up as short bumps in the surface model: an opening over 60 m removes
    # them, then a 45 m gaussian rounds the crests off (the big ones stay – Flugplatz, Pflanzgarten)
    w = int(60.0 / SPACING)
    opened = ndi.maximum_filter1d(ndi.minimum_filter1d(raw, w, mode="wrap"), w, mode="wrap")
    return gaussian_filter1d(opened, 45.0 / SPACING, mode="wrap"), raw


# ---------------------------------------------------------------------------------------------
# Rasters
# ---------------------------------------------------------------------------------------------
def cover_raster(cover, origin, n):
    """forest / field / village weights on the grid (0..255 each)."""
    layers = {}
    for name, subtypes in (("forest", {"forest": 255, "shrub": 110}), ("field", {"crop": 255, "shrub": 90}),
                           ("village", {"urban": 255})):
        img = Image.new("L", n, 0)
        d = ImageDraw.Draw(img)
        for sub, val in subtypes.items():
            for r in cover:
                if r["subtype"] != sub or r["cartography"]["min_zoom"] < 8:
                    continue
                g = wkb.loads(r["geometry"])
                for poly in ([g] if g.geom_type == "Polygon" else list(g.geoms)):
                    def px(coords):
                        c = np.array(coords)[:, :2]
                        x, z = local(c[:, 0], c[:, 1])
                        return list(zip((x - origin[0]) / GRID_CELL, (z - origin[1]) / GRID_CELL))
                    d.polygon(px(poly.exterior.coords), fill=val)
                    for hole in poly.interiors:
                        d.polygon(px(hole.coords), fill=0)
        # soft edges (the source polygons are generalised)
        layers[name] = ndi.gaussian_filter(np.asarray(img, np.float32), 1.2)
    return np.clip(np.stack([layers["forest"], layers["field"], layers["village"]], -1), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------------------------
def sections(pts, h):
    n = len(pts)
    s = np.arange(n) * SPACING
    t = np.gradient(pts, axis=0)
    heading = np.unwrap(np.arctan2(t[:, 1], t[:, 0]))
    curv = gaussian_filter1d(np.gradient(heading) / SPACING, 4)
    km = lambda d: int(d / SPACING) % n
    west = int(np.argmin(pts[:, 0]))
    low = int(np.argmin(h))
    # Karussell: the tightest left hairpin (heading turns to the left = negative curvature in x/z with z south)
    lo, hi = low + km(1500), low + km(5000)
    karussell = lo + int(np.argmin(curv[lo:hi]))
    high = karussell + int(np.argmax(h[karussell:karussell + km(1500)]))
    lo2 = high + km(2000)
    loop = lo2 + int(np.argmax(np.abs(curv[lo2:lo2 + km(2500)])))
    # Döttinger Höhe: first sample after the loop that starts 1.2 km without a real corner
    straight = loop + km(300)
    while np.max(np.abs(curv[straight:straight + km(1200)])) > 1.0 / 300.0:
        straight += 5
    anchors = {"start": 0, "west": west, "low": low, "karussell": karussell, "high": high, "loop": loop,
               "straight": straight, "end": n}
    order = ["start", "west", "low", "karussell", "high", "loop", "straight", "end"]
    nxt = {a: anchors[order[i + 1]] for i, a in enumerate(order[:-1])}
    out = []
    for name, a, frac in SECTIONS:
        i0 = anchors[a]
        out.append([name, round(float(s[0] + (i0 + frac * (nxt[a] - i0)) * SPACING), 1)])
    return out, anchors


# ---------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default="build/gruene_hoelle_cache")
    ap.add_argument("--out", default="assets/tracks/gruene_hoelle")
    ap.add_argument("--preview", default="build/gruene_hoelle_preview.png")
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    os.makedirs(a.out, exist_ok=True)

    infra = overture(a.cache, "base", "infrastructure", ["id", "class", "subtype", "geometry", "bbox"])
    cover = overture(a.cache, "base", "land_cover", ["id", "subtype", "cartography", "geometry", "bbox"])
    mosaic = dem_mosaic(a.cache)

    lines = rail_lines(infra)
    lines += bridge_gaps(lines)
    raw = centreline(lines)
    pts = resample(adaptive_smooth(resample(raw, SPACING)), SPACING)
    # driving direction: clockwise seen from above, starting on the T13 straight towards the north-west
    sx, sz = local(*START_GEO)
    k = int(np.argmin(np.linalg.norm(pts - np.array([sx, sz]), axis=1)))
    if (pts[(k + 3) % len(pts)] - pts[k])[0] > 0.0:
        pts = pts[::-1].copy()
        k = len(pts) - 1 - k
    pts = np.roll(pts, -k, axis=0)
    h, h_raw = profile(mosaic, pts)
    length = len(pts) * SPACING
    h0 = float(round(h[0]))
    grade = np.gradient(h, SPACING)
    curv_v = np.gradient(grade, SPACING)
    print(f"length {length:.0f} m, height {h.min():.1f} … {h.max():.1f} m (Δ {h.max() - h.min():.0f} m), "
          f"grade {grade.min() * 100:.1f} … {grade.max() * 100:.1f} %, tightest crest radius "
          f"{1.0 / max(-curv_v.min(), 1e-6):.0f} m")

    cl = np.stack([pts[:, 0], h - h0, pts[:, 1]], 1).astype(np.float32)
    cl.tofile(os.path.join(a.out, "centerline.bin"))

    # DEM + cover on the shared grid
    origin = (-GRID_HALF[0], -GRID_HALF[1])
    gn = (int(2 * GRID_HALF[0] / GRID_CELL) + 1, int(2 * GRID_HALF[1] / GRID_CELL) + 1)
    gx = origin[0] + np.arange(gn[0]) * GRID_CELL
    gz = origin[1] + np.arange(gn[1]) * GRID_CELL
    X, Z = np.meshgrid(gx, gz)
    dem = dem_sample(mosaic, X.ravel(), Z.ravel(), order=3).reshape(Z.shape)
    dem_min = float(np.floor(dem.min()))
    q = np.clip(np.round((dem - dem_min) * 100.0), 0, 65535).astype("<u2")
    with open(os.path.join(a.out, "dem.bin"), "wb") as f:
        f.write(zlib.compress(q.tobytes(), 9))
    cov = cover_raster(cover, origin, gn)
    with open(os.path.join(a.out, "cover.bin"), "wb") as f:
        f.write(zlib.compress(cov.tobytes(), 9))

    secs, anchors = sections(pts, h)
    meta = {
        "name": "Grüne Hölle",
        "samples": len(pts), "spacing": SPACING, "length": round(length, 1),
        "h0": h0, "dem_min": dem_min, "grid_origin": list(origin), "grid_cell": GRID_CELL,
        "grid_size": list(gn), "dem_bytes": int(q.nbytes), "cover_bytes": int(cov.nbytes),
        "sections": secs,
        "attribution": [
            "Streckenverlauf: © OpenStreetMap contributors (ODbL), über Overture Maps Foundation",
            "Landbedeckung: Overture Maps Foundation (aus ESA WorldCover, CC BY 4.0)",
            "Höhendaten: AWS Terrain Tiles / Mapzen – SRTM, EU-DEM (Copernicus), GMTED",
        ],
    }
    with open(os.path.join(a.out, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("anchors (m):", {k: v * SPACING for k, v in anchors.items()})
    for name, d in secs:
        print(f"  {d / 1000:6.2f} km  {name}")

    if a.preview:
        os.makedirs(os.path.dirname(a.preview) or ".", exist_ok=True)
        v = ((dem - dem.min()) / (dem.max() - dem.min()) * 150 + 50).astype(np.uint8)
        img = Image.fromarray(v).convert("RGB")
        g = Image.fromarray((cov[..., 0] > 128).astype(np.uint8) * 60)
        img = Image.composite(Image.new("RGB", img.size, (30, 90, 30)), img, g)
        d = ImageDraw.Draw(img)
        P = lambda p: ((p[0] - origin[0]) / GRID_CELL, (p[1] - origin[1]) / GRID_CELL)
        d.line([P(p) for p in np.vstack([pts, pts[:1]])], fill=(255, 255, 255), width=2)
        for name, dist in secs:
            p = P(pts[int(dist / SPACING) % len(pts)])
            d.ellipse([p[0] - 3, p[1] - 3, p[0] + 3, p[1] + 3], fill=(255, 80, 80))
            d.text((p[0] + 5, p[1] - 5), name, fill=(255, 255, 160))
        img.save(a.preview)
    sizes = {f: os.path.getsize(os.path.join(a.out, f)) for f in os.listdir(a.out)}
    print("written:", sizes)


if __name__ == "__main__":
    main()
