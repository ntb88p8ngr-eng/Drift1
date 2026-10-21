#!/usr/bin/env python3
"""Builds the data of "Takioro Mountain", a made-up Japanese mountain pass (no real-world data).

The course is laid out like a road engineer would (turtle): straights, arcs and corners that
tighten or open up, every piece with its own grade, the legs between the corners never quite
straight and no two hairpins alike – a valley straight at the foot, a zig-zag of hairpins up the south
face, a traverse along the upper slopes through rock spurs (tunnels), the pass, a faster descent
with more hairpins down the west face and back along the valley to the start. The ground is then
made to fit the road: near it the road's own heights, further out a massif with peaks above the
pass and ranges all round; above every tunnel the rock spur it runs through.

Writes to assets/tracks/takioro/ (the same formats as tools/make_gruene_hoelle.py):
  centerline.bin  float32 x, y, z per sample (2 m apart, driving direction, sample 0 on the start straight)
  dem.bin         deflate: uint16 height in cm above meta.dem_min, row-major
  cover.bin       deflate: 3 bytes per cell (forest, field, village) 0..255, same grid as the DEM
  meta.json       grid layout, section names, tunnels, cherry-tree stretches, viewpoints

Local frame: x = east, z = south (metres), y = height above the start line.
Needs: numpy scipy pillow
"""
import argparse
import json
import math
import os
import zlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

SPACING = 2.0
GRID_CELL = 10.0
GRID_HALF = 4600.0


class Turtle:
    """Lays out the course piece by piece: pts (x, z), grade per point, a label per point."""

    def __init__(self, x, z, heading_deg):
        self.x, self.z = x, z
        self.th = math.radians(heading_deg)
        self.pts = [(x, z)]
        self.grades = [0.0]
        self.tags = [""]
        self.tag = ""

    def _add(self, g):
        self.pts.append((self.x, self.z))
        self.grades.append(g)
        self.tags.append(self.tag)

    def straight(self, length, grade=0.0):
        n = max(1, int(round(length / 1.0)))
        step = length / n
        for _ in range(n):
            self.x += math.cos(self.th) * step
            self.z += math.sin(self.th) * step
            self._add(grade)

    def turn(self, deg, radius, grade=0.0):
        """deg > 0: left (seen from the driver), < 0: right."""
        ang = math.radians(abs(deg))
        n = max(2, int(round(ang * radius / 1.0)))
        sgn = -1.0 if deg > 0 else 1.0       # left turns decrease the heading (z points south)
        dth = sgn * ang / n
        for _ in range(n):
            # chord step along the arc
            mid = self.th + dth * 0.5
            step = 2.0 * radius * math.sin(abs(dth) * 0.5)
            self.x += math.cos(mid) * step
            self.z += math.sin(mid) * step
            self.th += dth
            self._add(grade)

    def curve(self, deg, r0, r1, grade=0.0):
        """Like turn(), but the radius changes evenly from r0 to r1 on the way round: a corner that
        tightens (r1 < r0) or opens up (r1 > r0)."""
        ang = math.radians(abs(deg))
        k0, k1 = 1.0 / r0, 1.0 / r1
        length = ang / ((k0 + k1) * 0.5)
        n = max(2, int(round(length / 1.0)))
        ds = length / n
        sgn = -1.0 if deg > 0 else 1.0
        ks = [k0 + (k1 - k0) * (j + 0.5) / n for j in range(n)]
        scale = ang / (sum(ks) * ds)
        for kk in ks:
            dth = sgn * kk * ds * scale
            mid = self.th + dth * 0.5
            self.x += math.cos(mid) * ds
            self.z += math.sin(mid) * ds
            self.th += dth
            self._add(grade)

    def heading_deg(self):
        return math.degrees(self.th)

    def turn_amount(self, target_deg, side=0):
        """The signed turn (deg > 0 left) to a compass heading; side +1 left, -1 right, 0 the
        shorter way."""
        cur = self.heading_deg() % 360.0
        diff = (target_deg - cur) % 360.0          # increasing heading = a right turn
        right = diff if diff > 1e-6 else 360.0
        left = 360.0 - right
        if side == 0:
            side = 1 if left < right else -1
        return left if side > 0 else -right

    def turn_to(self, target_deg, radius, grade=0.0, side=0, r1=None):
        """Turns to a compass heading (0 east, 90 south, 180 west, 270 north); r1: the radius at
        the end of the corner, if it changes."""
        deg = self.turn_amount(target_deg, side)
        if r1 is None:
            self.turn(deg, radius, grade)
        else:
            self.curve(deg, radius, r1, grade)

    def wander(self, length, grade, rng, max_dev=6.0, bend=(3.0, 12.0), radius=(80.0, 260.0), gap=(22.0, 70.0)):
        """A leg that is never quite straight: short straights and gentle bends of different size
        and radius, the heading kept within max_dev of the one it started with."""
        h0 = self.heading_deg()
        done = 0.0
        while done < length - 1.0:
            sl = min(rng.uniform(*gap), length - done)
            self.straight(sl, grade)
            done += sl
            if done > length - 15.0:
                break
            off = (self.heading_deg() - h0 + 180.0) % 360.0 - 180.0     # > 0: turned right
            deg = rng.uniform(*bend) * (1.0 if rng.random() < 0.5 else -1.0)
            if abs(off - deg) > max_dev:
                deg = -deg
            if abs(off - deg) > max_dev:
                deg = off                                             # back onto the line
            r = rng.uniform(*radius)
            arc = r * math.radians(abs(deg))
            if arc > length - done:
                r = max((length - done) / max(math.radians(abs(deg)), 1e-3), 30.0)
                arc = r * math.radians(abs(deg))
            if abs(deg) > 0.5:
                self.turn(deg, r, grade)
                done += arc

    def hairpin(self, spec, target, side, grade):
        """A hairpin onto a compass heading, each one its own: "plain" (one radius), "tighten" /
        "open" (radius r → x), "keyhole" (swings out x° the other way first, then round), "double"
        (two apexes with x m between them)."""
        kind, r, x = spec
        if kind == "plain":
            self.turn_to(target, r, grade, side)
        elif kind in ("tighten", "open"):
            self.turn_to(target, r, grade, side, r1=x)
        elif kind == "keyhole":
            self.turn(-side * x, 55.0, grade)
            self.turn_to(target, r, grade, side)
        elif kind == "double":
            half = self.turn_amount(target, side) * 0.5
            self.turn(half, r, grade)
            self.straight(x, grade)
            self.turn_to(target, r, grade, side)


E, S, W, N = 0.0, 90.0, 180.0, 270.0


def layout():
    t = Turtle(0.0, 0.0, 0.0)
    rng = np.random.default_rng(2611)
    secs = []

    def sec(name):
        secs.append((name, len(t.pts) - 1))

    # --- the valley: start/finish, then over the river and into the foot of the mountain ------------
    sec("Start / Ziel")
    t.tag = "valley"
    t.straight(190, 0.0)
    t.turn(-5, 420, 0.3)
    t.straight(60, 0.5)
    sec("Hashi-Kurve")
    t.turn_to(N + 45, 200, 0.8, r1=90)          # tightens onto the bridge
    t.straight(70, 1.5)
    t.turn(12, 150, 2.0)
    t.straight(60, 2.5)
    sec("Sugi-Allee")
    t.turn_to(N + 72, 150, 3.0, r1=105)
    t.wander(110, 4.0, rng, max_dev=5)
    t.turn_to(N, 62, 4.5, r1=115)                # opens up
    t.straight(50, 6.0)
    # --- the zig-zag up the south face: no two legs or hairpins alike ------------------------------
    t.tag = "switchbacks"
    sec("Iroha-Serpentinen")
    # legs: length, tilt uphill (°), grade (%), how far a leg wanders off its line (°)
    # (of different lengths, so the hairpins don't line up: the zig-zag works its way east as it climbs)
    legs = [(205, 11, 8.0, 6), (275, 6, 7.5, 9), (150, 16, 9.0, 4), (245, 9, 8.0, 10),
            (185, 13, 8.5, 7), (290, 5, 7.0, 8), (160, 15, 9.0, 5), (230, 10, 7.5, 8)]
    pins = [("plain", 18.0, 0.0), ("tighten", 34.0, 14.5), ("keyhole", 16.0, 26.0), ("double", 21.0, 14.0),
            ("plain", 15.0, 0.0), ("open", 14.5, 30.0), ("plain", 26.0, 0.0)]
    t.turn_to(W + legs[0][1], 45, 6.0, side=1, r1=70)
    for k, (L, tilt, gr, dev) in enumerate(legs):
        west = k % 2 == 0
        t.wander(L, gr, rng, max_dev=dev)
        if k < len(legs) - 1:
            sec("Kehre %d" % (k + 1))
            # westbound legs end with a right-hand hairpin (towards the uphill side, north),
            # eastbound ones with a left-hand one
            nt = legs[k + 1][1]
            t.hairpin(pins[k], E - nt if west else W + nt, -1 if west else 1, 4.0)
    # --- round the shoulder and along the upper slopes westwards, through the spurs ----------------
    t.tag = "traverse"
    sec("Kumo-Schulter")
    t.turn_to(W - 5, 48, 5.0, side=1, r1=80)
    t.wander(150, 4.5, rng, max_dev=5)
    sec("Tunnel Ichi")
    t.straight(70, 3.5)                 # (tunnel 1, a slight bend inside)
    t.turn(-7, 600, 3.5)
    t.straight(87, 3.5)
    t.turn_to(W - 35, 230, 3.0, r1=95)          # tightens on the way out
    t.wander(120, 3.0, rng, max_dev=4)
    sec("Galerie")
    t.turn_to(W + 25, 140, 3.0)
    t.straight(110, 2.5)                # (rock gallery along the cliff)
    t.turn(5, 500, 2.5)
    t.straight(56, 2.5)
    t.turn_to(W - 20, 115, 2.5, r1=60)
    t.straight(60, 2.0)
    # into the gully the stream has cut, round its head under the waterfall and out again
    t.turn(-55, 50, 2.0)
    t.straight(22, 2.0)
    sec("Taki-Wasserfall")
    t.turn(105, 30, 1.5)
    t.straight(30, 1.5)
    t.turn(-50, 70, 1.5)
    t.turn_to(W, 90, 1.0)
    sec("Tunnel Ni")
    t.straight(120, 1.5)                # (tunnel 2)
    t.turn(6, 700, 1.5)
    t.straight(67, 1.5)
    t.turn_to(W - 25, 260, 1.0, r1=150)
    t.wander(120, 0.5, rng, max_dev=4)
    sec("Takioro-Pass")
    t.turn_to(W + 10, 250, 0.0)
    t.straight(90, 0.0)
    t.turn(-5, 300, 0.0)
    t.straight(40, 0.0)
    # --- down the west face: sweepers that tighten, a sharp kink, then a zig-zag of hairpins -------
    t.tag = "descent"
    t.turn_to(S + 45, 150, -3.0, side=1, r1=85)     # heading south-west
    t.wander(170, -7.0, rng, max_dev=6)
    sec("Momiji-Kurven")
    t.turn_to(S + 5, 110, -6.0, r1=55)
    t.straight(70, -6.5)
    t.turn(-14, 120, -6.5)
    t.straight(40, -6.5)
    t.turn_to(S + 80, 34, -6.0)                     # the sharp one
    t.straight(80, -6.5)
    t.turn_to(S + 20, 160, -6.0, r1=90)
    sec("Tunnel San")
    t.straight(190, -5.5)               # (tunnel 3)
    t.turn_to(S, 160, -6.0)
    t.straight(60, -7.0)
    sec("Kaeru-Kehren")
    # zig-zag down: legs east-west, moving south
    legs2 = [(150, 10, -8.5, 5), (210, 6, -8.0, 8), (130, 15, -9.0, 4), (200, 9, -8.0, 9),
             (120, 13, -8.5, 5), (215, 7, -7.5, 7)]
    pins2 = [("tighten", 30.0, 14.5), ("plain", 20.0, 0.0), ("keyhole", 15.5, 24.0), ("double", 18.0, 10.0),
             ("open", 14.5, 27.0)]
    t.turn_to(E + legs2[0][1], 60, -7.0, side=1, r1=40)
    for k, (L, tilt, gr, dev) in enumerate(legs2):
        east = k % 2 == 0
        t.wander(L, gr, rng, max_dev=dev)
        if k < len(legs2) - 1:
            nt = legs2[k + 1][1]
            t.hairpin(pins2[k], W - nt if east else E + nt, -1 if east else 1, -4.0)
    # --- back along the valley under the cherry trees, through the village to the start ------------
    t.tag = "valley"
    sec("Sakura-Ufer")
    t.curve(95, 150, 80, -5.0)              # round the foot of the slope in two goes
    t.straight(55, -5.0)
    t.turn_to(E, 190, -5.0)
    t.wander(200, -4.0, rng, max_dev=7)
    t.turn_to(E - 25, 260, -3.0)
    t.straight(70, -2.0)
    t.turn(16, 140, -2.0)
    t.turn(-22, 110, -2.0)
    t.straight(60, -1.5)
    t.turn_to(E + 10, 250, -1.5)
    t.wander(120, -1.0, rng, max_dev=5)
    # the valley road back east towards the start, winding a little along the fields
    def bearing(x, z):
        return math.degrees(math.atan2(z - t.z, x - t.x)) % 360.0

    t.turn_to(bearing(-420.0, 30.0), 230, -2.5)
    t.wander(math.hypot(t.x + 420.0, t.z - 30.0) * 0.55, -2.5, rng, max_dev=9, bend=(5.0, 16.0))
    t.turn_to(bearing(-420.0, 30.0), 180, -2.0)
    t.wander(max(math.hypot(t.x + 420.0, t.z - 30.0) - 60.0, 40.0), -2.0, rng, max_dev=6)
    sec("Dorf")
    # the village street: a jog round the houses, then out onto the start straight
    t.turn_to(bearing(-200.0, 0.0), 120, -0.5)
    t.straight(40, -0.5)
    t.turn(-18, 70, -0.5)
    t.straight(30, 0.0)
    t.turn(18, 70, 0.0)
    return t, secs


def close_loop(t):
    """A Hermite curve from the turtle's end back to the start point, arriving heading east."""
    p0 = np.array([t.x, t.z])
    p1 = np.array([0.0, 0.0])
    d = np.linalg.norm(p1 - p0)
    m0 = np.array([math.cos(t.th), math.sin(t.th)]) * d * 1.1
    m1 = np.array([1.0, 0.0]) * d * 1.1
    n = int(d / 1.0) + 8
    out = []
    for i in range(1, n):
        s = i / n
        h00 = 2 * s ** 3 - 3 * s ** 2 + 1
        h10 = s ** 3 - 2 * s ** 2 + s
        h01 = -2 * s ** 3 + 3 * s ** 2
        h11 = s ** 3 - s ** 2
        out.append(h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1)
    return np.array(out)


def resample(p, step):
    seg = np.linalg.norm(np.diff(np.vstack([p, p[:1]]), axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    total = s[-1]
    n = int(round(total / step))
    q = np.linspace(0.0, total, n, endpoint=False)
    pc = np.vstack([p, p[:1]])
    x = np.interp(q, s, pc[:, 0])
    z = np.interp(q, s, pc[:, 1])
    return np.stack([x, z], 1), s, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/tracks/takioro")
    ap.add_argument("--preview", default="build/takioro_preview.png")
    ap.add_argument("--plan-only", action="store_true")
    a = ap.parse_args()

    t, secs = layout()
    raw = np.array(t.pts)
    grades = np.array(t.grades)
    closing = close_loop(t)
    raw_all = np.vstack([raw, closing])
    g_all = np.concatenate([grades, np.zeros(len(closing))])
    # heights: the grades integrated, the closing curve takes the rest back down to the start level
    dist_raw = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(raw_all, axis=0), axis=1))])
    h_raw = np.concatenate([[0.0], np.cumsum(g_all[1:] / 100.0 * np.diff(dist_raw))])
    n_main = len(raw)
    h_end = h_raw[n_main - 1]
    print(f"height at the end of the laid-out course: {h_end:.1f} m (the closing curve takes it to 0)")
    c_len = dist_raw[-1] - dist_raw[n_main - 1]
    for i in range(n_main, len(raw_all)):
        k = (dist_raw[i] - dist_raw[n_main - 1]) / max(c_len, 1.0)
        h_raw[i] = h_end * (1.0 - (3 * k * k - 2 * k * k * k))
    pts, s_raw, total = resample(raw_all, SPACING)
    pts = np.stack([ndi.gaussian_filter1d(pts[:, 0], 2.5, mode="wrap"), ndi.gaussian_filter1d(pts[:, 1], 2.5, mode="wrap")], 1)
    q = np.arange(len(pts)) * SPACING
    h = np.interp(q, np.concatenate([dist_raw, [total]]), np.concatenate([h_raw, [0.0]]))
    # no kinks in the profile (the grade changes over ~40 m)
    h = ndi.gaussian_filter1d(h, 8.0, mode="wrap")
    h -= h[0]
    grade = np.gradient(h, SPACING)
    print(f"length {total:.0f} m, {len(pts)} samples, height {h.min():.1f} … {h.max():.1f} m, "
          f"grade {grade.min() * 100:.1f} … {grade.max() * 100:.1f} %, closing {c_len:.0f} m (from a gap of "
          f"{math.hypot(t.x, t.z):.0f} m), end heading {t.heading_deg() % 360:.0f}°")
    # how close different parts of the lap come to each other (plan view)
    from scipy.spatial import cKDTree
    tree = cKDTree(pts)
    pairs = tree.query_pairs(26.0)
    close = [(i, j) for i, j in pairs if min(abs(i - j), len(pts) - abs(i - j)) > 40]
    if close:
        worst = min(close, key=lambda ij: np.linalg.norm(pts[ij[0]] - pts[ij[1]]))
        i, j = worst
        print(f"  closest other part of the lap: {np.linalg.norm(pts[i] - pts[j]):.1f} m apart at "
              f"{i * SPACING:.0f} m / {j * SPACING:.0f} m (Δh {abs(h[i] - h[j]):.1f} m), {len(close)} close pairs")
    # section names at their distance along the lap
    sec_m = [(name, float(dist_raw[min(ir, n_main - 1)])) for name, ir in secs]
    def sec_at(name):
        return next(d for n, d in sec_m if n == name)
    # tunnels and the rock gallery: [from, to] metres along the lap (the pieces laid out for them)
    tunnels = [[sec_at("Tunnel Ichi") + 12.0, sec_at("Tunnel Ichi") + 218.0],
               [sec_at("Tunnel Ni") + 12.0, sec_at("Tunnel Ni") + 248.0],
               [sec_at("Tunnel San") + 14.0, sec_at("Tunnel San") + 178.0]]
    gallery = [sec_at("Galerie") + 95.0, sec_at("Galerie") + 290.0]
    if a.plan_only:
        _preview(a.preview, pts, h, sec_m, tunnels, None, None, None)
        return

    # --- the ground -------------------------------------------------------------------------------
    centre = (pts.min(0) + pts.max(0)) * 0.5
    origin = (float(np.floor((centre[0] - GRID_HALF) / 10.0) * 10.0), float(np.floor((centre[1] - GRID_HALF) / 10.0) * 10.0))
    gn = (int(2 * GRID_HALF / GRID_CELL) + 1, int(2 * GRID_HALF / GRID_CELL) + 1)
    gx = origin[0] + np.arange(gn[0]) * GRID_CELL
    gz = origin[1] + np.arange(gn[1]) * GRID_CELL
    X, Z = np.meshgrid(gx, gz)
    from scipy.spatial import cKDTree
    tree = cKDTree(pts)
    d_road, idx = tree.query(np.stack([X.ravel(), Z.ravel()], 1))
    d_road = d_road.reshape(X.shape)
    idx = idx.reshape(X.shape)
    rng = np.random.default_rng(7)

    def raster(vals):
        acc = np.zeros(X.shape)
        w = np.zeros(X.shape)
        ix = np.clip(((pts[:, 0] - origin[0]) / GRID_CELL).round().astype(int), 0, gn[0] - 1)
        iz = np.clip(((pts[:, 1] - origin[1]) / GRID_CELL).round().astype(int), 0, gn[1] - 1)
        np.add.at(acc, (iz, ix), vals)
        np.add.at(w, (iz, ix), 1.0)
        return acc, w

    def norm_conv(vals, sigma):
        acc, w = raster(vals)
        a2 = ndi.gaussian_filter(acc, sigma)
        w2 = ndi.gaussian_filter(w, sigma)
        return a2, w2

    def fbm(scale, octaves, seed, ridged=False):
        out = np.zeros(X.shape)
        amp = 1.0
        total = 0.0
        g = np.random.default_rng(seed)
        for o in range(octaves):
            n = max(int(2 * GRID_HALF / (scale / (2 ** o))) + 3, 4)
            base = g.standard_normal((n, n))
            f = ndi.zoom(base, (gn[1] / n, gn[0] / n), order=3)[:gn[1], :gn[0]]
            if f.shape != X.shape:
                f = np.pad(f, ((0, gn[1] - f.shape[0]), (0, gn[0] - f.shape[1])), mode="edge")
            if ridged:
                f = 1.0 - np.abs(np.tanh(f * 1.2))
            out += f * amp
            total += amp
            amp *= 0.5
        return out / total

    # the far landscape at the edge of the map: high ranges to the north, lower hills to the south
    edge_h = 430.0 + 380.0 * (-(Z - centre[1]) / GRID_HALF) + 160.0 * fbm(2600.0, 3, 21)

    # a smooth membrane through the road (its heights fixed) and the far ranges (harmonic, solved
    # coarse to fine): the slopes between the legs of the zig-zags, the face between the valley and
    # the pass, the valleys round the mountain – no terraces, no seams
    def membrane():
        H = None
        for cell, iters in ((160.0, 3000), (80.0, 1500), (40.0, 700), (20.0, 300), (10.0, 160)):
            n = int(2 * GRID_HALF / cell) + 1
            ax = origin[0] + np.arange(n) * cell
            az = origin[1] + np.arange(n) * cell
            ix = np.clip(((pts[:, 0] - origin[0]) / cell).round().astype(int), 0, n - 1)
            iz = np.clip(((pts[:, 1] - origin[1]) / cell).round().astype(int), 0, n - 1)
            acc = np.zeros((n, n))
            cnt = np.zeros((n, n))
            np.add.at(acc, (iz, ix), h)
            np.add.at(cnt, (iz, ix), 1.0)
            mask = cnt > 0
            val = np.where(mask, acc / np.maximum(cnt, 1), 0.0)
            # the edge values at this level
            sx = np.clip(((ax - origin[0]) / GRID_CELL).round().astype(int), 0, gn[0] - 1)
            sz = np.clip(((az - origin[1]) / GRID_CELL).round().astype(int), 0, gn[1] - 1)
            B = edge_h[np.ix_(sz, sx)]
            if H is None:
                H = B.copy()
            else:
                H = ndi.zoom(H, (n / H.shape[0], n / H.shape[1]), order=1)[:n, :n]
                if H.shape != (n, n):
                    H = np.pad(H, ((0, n - H.shape[0]), (0, n - H.shape[1])), mode="edge")
            for _ in range(iters):
                H[1:-1, 1:-1] = 0.25 * (H[:-2, 1:-1] + H[2:, 1:-1] + H[1:-1, :-2] + H[1:-1, 2:])
                H[mask] = val[mask]
                H[0, :] = B[0, :]
                H[-1, :] = B[-1, :]
                H[:, 0] = B[:, 0]
                H[:, -1] = B[:, -1]
        return H

    base = membrane()
    # where the road is and how it runs (lateral offset to the right, distance along the lap)
    s_idx = idx.ravel()
    tg = np.gradient(pts, axis=0)
    tg /= np.linalg.norm(tg, axis=1, keepdims=True)
    rights = np.stack([-tg[:, 1], tg[:, 0]], 1)      # (x, z): right of the driving direction
    rel = np.stack([X.ravel(), Z.ravel()], 1) - pts[s_idx]
    lat_all = np.einsum("ij,ij->i", rel, rights[s_idx]).reshape(X.shape)
    dist_along = (idx * SPACING).astype(float)
    # which side of the road is uphill (the membrane 60 m to the right vs. the road)
    def at_grid(px, pz):
        ix = np.clip(((px - origin[0]) / GRID_CELL).round().astype(int), 0, gn[0] - 1)
        iz = np.clip(((pz - origin[1]) / GRID_CELL).round().astype(int), 0, gn[1] - 1)
        return base[iz, ix]
    up_right = np.sign(at_grid(pts[:, 0] + rights[:, 0] * 70.0, pts[:, 1] + rights[:, 1] * 70.0)
                       - at_grid(pts[:, 0] - rights[:, 0] * 70.0, pts[:, 1] - rights[:, 1] * 70.0))
    uphill_lat = lat_all * up_right[idx]           # > 0 on the uphill side

    away = smoothstep(30.0, 320.0, d_road)
    far_k = smoothstep(150.0, 1600.0, d_road)
    # texture of the land: rolling near the road, rugged ridges further out
    rough = fbm(450.0, 5, 12)
    ridges = fbm(1300.0, 5, 11, ridged=True)
    dem = base + rough * 14.0 * away + (ridges - 0.5) * 260.0 * far_k
    # peaks above the pass and the traverse (north, uphill), shoulders towards the hairpins
    for k, name in enumerate(("Tunnel Ichi", "Galerie", "Tunnel Ni", "Takioro-Pass", "Kehre 5", "Momiji-Kurven")):
        i0 = int(sec_at(name) / SPACING) % len(pts)
        up = rights[i0] * up_right[i0]
        c = pts[i0] + up * rng.uniform(420, 650) + rng.uniform(-120, 120, 2)
        amp = rng.uniform(170, 300) if k < 4 else rng.uniform(90, 150)
        r = rng.uniform(320, 480)
        dem += amp * np.exp(-(((X - c[0]) ** 2 + (Z - c[1]) ** 2) / (r * r))) * smoothstep(40.0, 260.0, d_road)
    # the rock spurs the tunnels run through: 15 m of rock over the portals, ~40 m in the middle,
    # running on up the slope. Measured against the tunnel's own piece of road only (the nearest
    # point of the whole lap jumps to the hairpin below – that left a cliff along the seam).
    cells = np.stack([X.ravel(), Z.ravel()], 1)

    def along_piece(d0, d1, reach):
        i0 = int((d0 - reach) / SPACING)
        i1 = int((d1 + reach) / SPACING)
        ii = np.arange(i0, i1) % len(pts)
        tr2 = cKDTree(pts[ii])
        dd, kk = tr2.query(cells, distance_upper_bound=320.0)
        ok = np.isfinite(dd)
        kk = np.where(ok, kk, 0)
        si = ii[kk]
        rel2 = cells - pts[si]
        lat = np.einsum("ij,ij->i", rel2, rights[si]) * up_right[si]
        along = (i0 + kk) * SPACING
        # beyond the ends of the piece: how far past them (the bump fades out there)
        past = np.einsum("ij,ij->i", rel2, tg[si])
        return ok.reshape(X.shape), along.reshape(X.shape), lat.reshape(X.shape), past.reshape(X.shape), dd.reshape(X.shape)

    for (d0, d1) in tunnels:
        ok, along, lat, past, dd = along_piece(d0, d1, 60.0)
        # full height right at the portals, falling away outside them
        wa = np.clip((along - (d0 - 50.0)) / 50.0, 0.0, 1.0) * np.clip(((d1 + 50.0) - along) / 50.0, 0.0, 1.0)
        wa = wa * wa * (3.0 - 2.0 * wa)
        mid = np.clip(np.minimum(along - d0, d1 - along) / 70.0, 0.0, 1.0)
        height = 15.0 + 28.0 * mid
        prof = np.exp(-(np.maximum(-lat, 0.0) / 55.0) ** 2) * (1.0 + 0.6 * smoothstep(0.0, 120.0, lat))
        prof *= 1.0 - smoothstep(90.0, 160.0, np.where(ok, dd, 1e9))
        dem += np.where(ok, wa * height * prof, 0.0)
    # the gallery: a sheer cliff right beside the road on the uphill side
    ok, along, lat, past, dd = along_piece(gallery[0], gallery[1], 60.0)
    ga = np.clip((along - (gallery[0] - 30.0)) / 40.0, 0.0, 1.0) * np.clip(((gallery[1] + 30.0) - along) / 40.0, 0.0, 1.0)
    ga = ga * ga * (3.0 - 2.0 * ga) * (1.0 - smoothstep(120.0, 220.0, np.where(ok, dd, 1e9)))
    dem += np.where(ok, ga * 32.0 * smoothstep(9.0, 30.0, lat) * (1.0 - smoothstep(70.0, 130.0, lat)), 0.0)
    # the waterfall: a short rock wall above the uphill verge that the water drops down
    wf = sec_at("Taki-Wasserfall") + 25.0       # the apex of the bend round the head of the gully
    # (a level shelf at road height up to the foot of the wall, ~30 m out, whatever the slope was
    # there – on the outside of the bend round the gully head it would bury the wall – then 28 m of
    # rock straight up; the 10 m grid smears it over a few cells, so it starts well behind the verge)
    ok, along, lat, past, dd = along_piece(wf - 40.0, wf + 40.0, 60.0)
    wa = np.clip(1.0 - (np.abs(along - wf) - 22.0) / 40.0, 0.0, 1.0)
    wa = wa * wa * (3.0 - 2.0 * wa) * (1.0 - smoothstep(90.0, 160.0, np.where(ok, dd, 1e9)))
    wa *= (lat > -5.0) * (1.0 - smoothstep(60.0, 95.0, lat))
    road_y = h[np.clip((along / SPACING).astype(int), 0, None) % len(pts)]
    wall = road_y + 0.5 + 28.0 * smoothstep(31.0, 37.0, lat)
    shaped = np.where(lat < 37.0, wall, np.maximum(dem, wall))
    dem = np.where(ok, dem + wa * (shaped - dem), dem)
    dem_min = float(np.floor(dem.min()))
    q = np.clip(np.round((dem - dem_min) * 100.0), 0, 65535).astype("<u2")

    # --- land cover: forest on the slopes, rice fields and the village in the valley, bare rock high up
    slope = np.hypot(*np.gradient(dem, GRID_CELL))
    alt = dem
    # rice fields on the flat valley floor (patchy), not up on the mountain
    patches = smoothstep(-0.2, 0.3, fbm(260.0, 3, 31))
    field = np.clip((1.0 - smoothstep(0.05, 0.14, slope)) * (1.0 - smoothstep(30.0, 70.0, alt)) * patches, 0, 1)
    village_c = pts[(int(sec_at("Dorf") / SPACING) + 40) % len(pts)]
    village = 1.0 - smoothstep(120.0, 220.0, np.hypot(X - village_c[0], Z - village_c[1]))
    forest = np.clip(1.0 - field * 1.2 - village, 0.0, 1.0) * (1.0 - smoothstep(780.0, 950.0, alt))
    forest *= 1.0 - smoothstep(0.9, 1.3, slope)          # cliffs: rock
    cov = (np.stack([forest, field, village], -1) * 255.0).round().astype(np.uint8)

    os.makedirs(a.out, exist_ok=True)
    cl = np.stack([pts[:, 0], h, pts[:, 1]], 1).astype(np.float32)
    cl.tofile(os.path.join(a.out, "centerline.bin"))
    with open(os.path.join(a.out, "dem.bin"), "wb") as f:
        f.write(zlib.compress(q.tobytes(), 9))
    with open(os.path.join(a.out, "cover.bin"), "wb") as f:
        f.write(zlib.compress(cov.tobytes(), 9))
    # cherry trees along the valley and the lower switchbacks, the waterfall's spot
    sakura = [[0.0, sec_at("Hashi-Kurve") + 120.0], [sec_at("Iroha-Serpentinen"), sec_at("Kehre 3")],
              [sec_at("Takioro-Pass") - 120.0, sec_at("Takioro-Pass") + 160.0], [sec_at("Sakura-Ufer"), total]]
    meta = {
        "name": "Takioro Mountain",
        "samples": len(pts), "spacing": SPACING, "length": round(total, 1),
        "h0": 0.0, "dem_min": dem_min, "grid_origin": list(origin), "grid_cell": GRID_CELL,
        "grid_size": list(gn), "dem_bytes": int(q.nbytes), "cover_bytes": int(cov.nbytes),
        "sections": [[n, round(d, 1)] for n, d in sec_m],
        "tunnels": [[round(a0, 1), round(a1, 1)] for a0, a1 in tunnels],
        "gallery": [round(gallery[0], 1), round(gallery[1], 1)],
        "sakura": [[round(a0, 1), round(a1, 1)] for a0, a1 in sakura],
        "waterfall": round(wf, 1),
        "village": [round(float(village_c[0]), 1), round(float(village_c[1]), 1)],
        "attribution": ["Takioro Mountain: frei erfunden (tools/make_takioro.py)"],
    }
    with open(os.path.join(a.out, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print(f"ground {dem.min():.0f} … {dem.max():.0f} m, forest {forest.mean() * 100:.0f} %, fields {field.mean() * 100:.0f} %")
    _preview(a.preview, pts, h, sec_m, tunnels, dem, (origin, gn), forest)
    sizes = {f: os.path.getsize(os.path.join(a.out, f)) for f in os.listdir(a.out)}
    print("written:", sizes)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _preview(path, pts, h, sec_m, tunnels, dem, grid, forest):
    if not path:
        return
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if dem is None:
        mn = pts.min(0) - 60
        mx = pts.max(0) + 60
    else:
        mn = pts.min(0) - 900
        mx = pts.max(0) + 900
    sc = 1000.0 / max(mx - mn)
    W, H = int((mx - mn)[0] * sc) + 1, int((mx - mn)[1] * sc) + 1
    if dem is None:
        img = Image.new("RGB", (W, H), (20, 24, 30))
    else:
        origin, gn = grid
        # hill-shaded height map, green where the forest is
        x0 = int((mn[0] - origin[0]) / GRID_CELL)
        z0 = int((mn[1] - origin[1]) / GRID_CELL)
        x1 = int((mx[0] - origin[0]) / GRID_CELL)
        z1 = int((mx[1] - origin[1]) / GRID_CELL)
        sub = dem[z0:z1, x0:x1]
        gy, gx2 = np.gradient(sub, GRID_CELL)
        shade = np.clip(0.6 + (gx2 * -0.7 + gy * -0.7) * 1.2, 0.2, 1.2)
        hn = (sub - sub.min()) / max(sub.max() - sub.min(), 1.0)
        fo = forest[z0:z1, x0:x1]
        rgb = np.stack([(90 + 120 * hn) * (1 - 0.45 * fo), (85 + 100 * hn) * (1 - 0.1 * fo), (70 + 90 * hn) * (1 - 0.5 * fo)], -1)
        rgb = np.clip(rgb * shade[..., None], 0, 255).astype(np.uint8)
        img = Image.fromarray(rgb).resize((W, H))
    d = ImageDraw.Draw(img)
    hn2 = (h - h.min()) / max(h.max() - h.min(), 1)
    tun = np.zeros(len(pts), bool)
    for a0, a1 in tunnels:
        tun[int(a0 / SPACING):int(a1 / SPACING)] = True
    for i in range(len(pts)):
        p = (pts[i] - mn) * sc
        c = (40, 40, 40) if tun[i] else (int(80 + 175 * hn2[i]), int(200 - 120 * hn2[i]), int(255 - 200 * hn2[i]))
        d.ellipse([p[0] - 1.5, p[1] - 1.5, p[0] + 1.5, p[1] + 1.5], fill=c)
    for name, dist in sec_m:
        p = (pts[int(dist / SPACING) % len(pts)] - mn) * sc
        d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=(255, 80, 80))
        d.text((p[0] + 6, p[1] - 6), name, fill=(255, 255, 160))
    img.save(path)
    print("preview:", path)


if __name__ == "__main__":
    main()
