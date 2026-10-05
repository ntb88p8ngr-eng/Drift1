#!/usr/bin/env python3
"""Builds the other courses of the "Grüne Hölle" map (Nürburgring): the GP circuit alone and the
24h combination (GP circuit + Nordschleife), next to the Nordschleife data of make_gruene_hoelle.py.

GP circuit: the centre line of the TUM racetrack database (Nuerburgring.csv, LGPL-3.0, from
OpenStreetMap GPS points, local metres x east / y north) placed into the map's frame by matching it
against the grass areas around the track in the Overture land use data (best fit: rotated -1.75°,
shifted as in GP_T below). Heights from the map's own DEM (dem.bin).

Combination (as driven at the 24h race): GP start/finish – Mercedes Arena – Dunlop-Kehre – … –
ITT-Bogen, before the NGK chicane left into the Sabine-Schmitz-Kurve onto the Nordschleife, the whole
Nordschleife to Hohenrain, then onto the GP straight after the Coca-Cola-Kurve. The two short links
are drawn as smooth curves between the courses.

Writes to assets/tracks/gruene_hoelle/:
  centerline_gp.bin, centerline_combined.bin   float32 x, y, z per sample (2 m apart, driving order,
                                               sample 0 on the GP start/finish straight)
  layouts.json                                 the sections of each course (name, metres from sample 0)

Usage: python3 tools/make_gh_layouts.py [--csv path/to/Nuerburgring.csv]
"""
import argparse
import json
import math
import os
import urllib.request
import zlib

import numpy as np
from scipy.ndimage import gaussian_filter1d, map_coordinates

OUT = "assets/tracks/gruene_hoelle"
CSV_URL = "https://raw.githubusercontent.com/TUMFTM/racetrack-database/master/tracks/Nuerburgring.csv"
GP_ROT = math.radians(-1.75)
GP_T = (-1405.8162, 2332.0672)
SPACING = 2.0
# GP corners by index of the TUM centre line (5 m apart, start/finish = 0)
GP_SECTIONS = [("GP Start/Ziel", 0), ("Yokohama-S", 75), ("Mercedes-Arena", 135), ("Valvoline-Kurve", 255),
               ("Ford-Kurve", 335), ("Dunlop-Kehre", 455), ("Audi-S", 540), ("Michelin-Kurve", 650),
               ("Bit-Kurve", 700), ("ITT-Bogen", 760), ("NGK-Schikane", 900), ("Coca-Cola-Kurve", 935)]
GP_EXIT = 872            # TUM index: leave the GP circuit here (before the NGK chicane) …
NS_JOIN = 215            # … onto the Nordschleife sample after the Sabine-Schmitz-Kurve hairpin
NS_LEAVE = 10180         # Nordschleife sample at Hohenrain where the link to the GP straight starts
GP_ENTRY = 948           # TUM index on the GP straight after the Coca-Cola-Kurve


def load_gp(path):
    pts = np.loadtxt(path, delimiter=",", comments="#")
    x, z = pts[:, 0], -pts[:, 1]
    c, s = math.cos(GP_ROT), math.sin(GP_ROT)
    return np.stack([c * x - s * z + GP_T[0], s * x + c * z + GP_T[1]], 1)


def resample(p, closed, step=SPACING):
    """Polyline (n, k) resampled every `step` metres along x/z (columns 0 and last)."""
    q = np.vstack([p, p[:1]]) if closed else p
    xz = q[:, [0, -1]]
    d = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(xz, axis=0), axis=1))])
    n = int(d[-1] // step)
    t = np.linspace(0.0, d[-1], n, endpoint=not closed)
    return np.stack([np.interp(t, d, q[:, k]) for k in range(q.shape[1])], 1)


def hermite(p0, t0, p1, t1, k=1.2, n=200):
    """Smooth link from p0 (heading t0) to p1 (heading t1); tangent length k x the distance."""
    L = np.linalg.norm(p1 - p0) * k
    t0 = t0 / np.linalg.norm(t0) * L
    t1 = t1 / np.linalg.norm(t1) * L
    u = np.linspace(0.0, 1.0, n)[:, None]
    return (2 * u**3 - 3 * u**2 + 1) * p0 + (u**3 - 2 * u**2 + u) * t0 + (-2 * u**3 + 3 * u**2) * p1 + (u**3 - u**2) * t1


def dem_sampler(meta):
    nx, nz = meta["grid_size"]
    raw = zlib.decompress(open(os.path.join(OUT, "dem.bin"), "rb").read())
    h = np.frombuffer(raw, dtype=np.uint16).reshape(nz, nx).astype(np.float64) / 100.0 + meta["dem_min"] - meta["h0"]
    ox, oz = meta["grid_origin"]
    cell = meta["grid_cell"]

    def at(x, z):
        return map_coordinates(h, [(np.asarray(z) - oz) / cell, (np.asarray(x) - ox) / cell], order=1, mode="nearest")
    return at


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="build/gp_cache/Nuerburgring.csv")
    a = ap.parse_args()
    if not os.path.exists(a.csv):
        os.makedirs(os.path.dirname(a.csv), exist_ok=True)
        urllib.request.urlretrieve(CSV_URL, a.csv)
    meta = json.load(open(os.path.join(OUT, "meta.json")))
    dem = dem_sampler(meta)
    gp5 = load_gp(a.csv)
    ns = np.fromfile(os.path.join(OUT, "centerline.bin"), dtype=np.float32).reshape(-1, 3).astype(np.float64)
    out = {}

    # --- GP alone: a light smoothing (the data has small kinks), heights from the DEM ---
    gp = resample(gp5, True)
    gp[:, 0] = gaussian_filter1d(gp[:, 0], 2.0, mode="wrap")
    gp[:, 1] = gaussian_filter1d(gp[:, 1], 2.0, mode="wrap")
    y = gaussian_filter1d(dem(gp[:, 0], gp[:, 1]), 6.0, mode="wrap")
    gp3 = np.stack([gp[:, 0], y, gp[:, 1]], 1)
    # where each TUM index lies on the 2 m line
    def gp_at(k):
        return int(np.argmin(np.linalg.norm(gp - gp5[k % len(gp5)], axis=1)))
    secs = [[name, round(gp_at(k) * SPACING, 1)] for name, k in GP_SECTIONS]
    gp3.astype(np.float32).tofile(os.path.join(OUT, "centerline_gp.bin"))
    out["gp"] = {"length": len(gp3) * SPACING, "sections": secs}

    # --- the combination ---
    e, j = gp_at(GP_EXIT), gp_at(GP_ENTRY)
    part1 = gp3[: e + 1]
    t_exit = gp3[e + 1] - gp3[e - 1]
    t_join = ns[NS_JOIN + 1] - ns[NS_JOIN - 1]
    link1 = hermite(gp3[e], t_exit, ns[NS_JOIN], t_join, 1.6)[1:-1]
    part2 = ns[NS_JOIN: NS_LEAVE + 1]
    t_leave = ns[NS_LEAVE + 1] - ns[NS_LEAVE - 1]
    t_entry = gp3[j + 1] - gp3[j - 1]
    link2 = hermite(ns[NS_LEAVE], t_leave, gp3[j], t_entry, 1.0)[1:-1]
    part3 = gp3[j:]
    allp = np.vstack([part1, link1, part2, link2, part3])
    comb = resample(allp, True)
    # heights: the links follow the DEM, everything a little smoothed across the joins
    comb[:, 1] = gaussian_filter1d(comb[:, 1], 4.0, mode="wrap")
    comb.astype(np.float32).tofile(os.path.join(OUT, "centerline_combined.bin"))

    def dist_of(p):
        return round(float(np.argmin(np.linalg.norm(comb[:, [0, 2]] - p[[0, 2]], axis=1))) * SPACING, 1)
    csecs = [[n, d] for n, d in secs if d <= e * SPACING]
    csecs.append(["Sabine-Schmitz-Kurve", dist_of(link1[len(link1) // 2])])
    for name, d in meta["sections"]:
        k = int(round(d / SPACING))
        if NS_JOIN <= k <= NS_LEAVE:
            csecs.append([name, dist_of(ns[k])])
    csecs.append(["GP-Zielgerade", dist_of(gp3[j])])
    csecs.sort(key=lambda s: s[1])
    out["combined"] = {"length": len(comb) * SPACING, "sections": csecs}
    json.dump(out, open(os.path.join(OUT, "layouts.json"), "w"), ensure_ascii=False, indent=1)
    print("GP %.0f m, combined %.0f m (links %d + %d pts)" % (len(gp3) * SPACING, len(comb) * SPACING, len(link1), len(link2)))
    # the sharpest bend of the links (radius, m): drivable?
    for nm, lk in (("link1", link1), ("link2", link2)):
        v = np.diff(lk[:, [0, 2]], axis=0)
        ang = np.abs(np.diff(np.unwrap(np.arctan2(v[:, 1], v[:, 0]))))
        seg = np.linalg.norm(v, axis=1)[1:]
        print(nm, "length %.0f m, min radius %.1f m" % (seg.sum(), (seg / np.maximum(ang, 1e-6)).min()))


if __name__ == "__main__":
    main()
