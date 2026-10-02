extends RefCounted
## Neo Tokyo's streets as geometry, and everything along them:
##   asphalt ribbons (the race road's material: same wetness / puddles / night), a plate over every
##   junction, centre and edge lines, stop lines and zebra crossings at the junctions, manholes, kerbs;
##   parking bays with parked cars on the wide streets; streetlights (real lights via the light pool),
##   street trees (cherries on some streets), utility poles with sagging wires on the narrow ones,
##   fire hydrants, vending machines, bicycles, benches, bins, post boxes, traffic signals, bus stops
##   with lit ads; and in race mode water barriers closing every side street at the race route.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const CityAtlas = preload("res://scripts/world/city/city_atlas.gd")
const Colliders = preload("res://scripts/util/colliders.gd")

const Y_STREET := 0.016
const Y_PLATE := 0.026
const Y_LINE := 0.006           # above the surface it's painted on

var net
var cm
var track
var scenery
var add_inst: Callable          # (kind, Transform3D, custom Color)
var lamps                       # city_lamps.gd: the breakable streetlights
var light: Callable             # (pos, colour, range, energy, kind)
var rng := RandomNumberGenerator.new()
var plates: Array = []          # [Vector2 centre, radius, Array of the street directions leaving it]
var _plate_grid := {}           # Vector2i (PLATE_CELL cells) -> plates there
const PLATE_CELL := 36.0        # > the largest plate radius (26) + the largest `extra` asked for (8)
var closures: Array = []        # race mode barriers (RigidBodies), removable for free roam
var sakura_streets := {}
var people_spots: Array = []    # [Vector3 position, Vector3 facing] for pedestrians
var stats := {}


func build(p_net, p_cm, p_track, p_scenery, p_add: Callable, p_light: Callable, parent: Node3D) -> void:
	net = p_net
	cm = p_cm
	track = p_track
	scenery = p_scenery
	add_inst = p_add
	light = p_light
	rng.seed = 4242
	_find_plates()
	for k in net.streets.size():
		if rng.randf() < 0.3 or net.streets[k]["kind"] == "crossing":
			sakura_streets[k] = true
	for k in net.streets.size():
		_ribbon(k)
		_markings(k)
		_kerbs(k)
	for p in plates:
		_plate(p[0], p[1])
	_route_mouths()
	for k in net.streets.size():
		_furniture(k)
	_closures(parent)


# ---------------------------------------------------------------------------
# Surfaces
# ---------------------------------------------------------------------------
## A junction plate wherever street ends meet (not at the race route: its road lies on top there).
func _find_plates() -> void:
	var ends: Array = []
	for s in net.streets:
		var pts: PackedVector2Array = s["pts"]
		if s["kind"] == "ring":
			continue
		ends.append([pts[0], float(s["w"]), (pts[1] - pts[0]).normalized()])
		ends.append([pts[pts.size() - 1], float(s["w"]), (pts[pts.size() - 2] - pts[pts.size() - 1]).normalized()])
	var used := {}
	for a in ends.size():
		if used.has(a):
			continue
		var c: Vector2 = ends[a][0]
		var r: float = float(ends[a][1]) * 0.5
		var members := 1
		var dirs: Array = [ends[a][2]]
		for b in range(a + 1, ends.size()):
			if not used.has(b) and (ends[b][0] as Vector2).distance_to(c) < 4.0:
				used[b] = true
				r = maxf(r, float(ends[b][1]) * 0.5)
				members += 1
				dirs.append(ends[b][2])
		if net.owner_at(c) == -3 or _near_track(c, 6.0):
			continue
		# where two streets meet at a sharp angle their ribbons overlap far out: cover all of it
		var need := r + 2.0
		for x in dirs.size():
			for y in range(x + 1, dirs.size()):
				var ang := acos(clampf((dirs[x] as Vector2).dot(dirs[y]), -1.0, 1.0))
				need = maxf(need, r / maxf(tan(ang * 0.5), 0.25) + 1.5)
		plates.append([c, minf(need, 26.0), dirs])
	for pl in plates:
		var c: Vector2 = pl[0]
		var key := Vector2i(int(floor(c.x / PLATE_CELL)), int(floor(c.y / PLATE_CELL)))
		if not _plate_grid.has(key):
			_plate_grid[key] = []
		_plate_grid[key].append(pl)


func _near_track(p: Vector2, extra: float) -> bool:
	# quick reject with the terrain's distance field (distance to the centreline)
	if float(scenery.terrain.distance_to_road(p.x, p.y)) > 24.0 + extra:
		return false
	var i: int = track.nearest_index(Vector3(p.x, 0, p.y))
	var s: Vector3 = track.samples[i]
	return Vector2(s.x, s.z).distance_to(p) < maxf(float(track.off_left[i]), float(track.off_right[i])) + extra


## Does street k end here on another street (a T-junction without a plate)?
func _t_junction(e0: Vector2, k: int) -> bool:
	for d: Vector2 in [Vector2.ZERO, Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		var o: int = net.owner_at(e0 + d)
		if o == -2 or (o >= 0 and o != k):
			return true
	return false


func _in_plate(p: Vector2, extra := 0.0) -> bool:
	var key := Vector2i(int(floor(p.x / PLATE_CELL)), int(floor(p.y / PLATE_CELL)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for pl in _plate_grid.get(key + Vector2i(dx, dz), []):
				if (pl[0] as Vector2).distance_to(p) < float(pl[1]) + extra:
					return true
	return false


func _ribbon(k: int) -> void:
	var s: Dictionary = net.streets[k]
	var pts: PackedVector2Array = s["pts"]
	var hw: float = float(s["w"]) * 0.5
	var y := Y_STREET + (0.004 if s["kind"] == "ring" else 0.0) + 0.0006 * (k % 4)
	var v := 0.0
	for j in pts.size() - 1:
		var a := pts[j]
		var b := pts[j + 1]
		var na := _normal(pts, j)
		var nb := _normal(pts, j + 1)
		var l := a.distance_to(b)
		v += l
		# the junction plate covers the street's end: no ribbon under it (no overlap, no flicker)
		if _in_plate(a, -1.0) and _in_plate(b, -1.0):
			continue
		var pa := Vector3(a.x, y, a.y)
		var pb := Vector3(b.x, y, b.y)
		# u 0.2 – 0.8: the road shader's edge lines (for the race track) stay off the streets
		cm.quad("road", pa - Vector3(na.x, 0, na.y) * hw, pa + Vector3(na.x, 0, na.y) * hw, pb + Vector3(nb.x, 0, nb.y) * hw, pb - Vector3(nb.x, 0, nb.y) * hw,
			Vector3.UP, Color(1, 1, 1), Vector2(0.2, v - l), Vector2(0.8, v - l), Vector2(0.8, v), Vector2(0.2, v))
	stats["street_m"] = int(stats.get("street_m", 0)) + int(v)


## Where a street meets the race route it starts at the barrier line – on the outside of a bend
## that is metres away from the road, and the pavement showed in between. Asphalt from the street's
## end right under the edge of the route's road, the mouth flared like a real junction and following
## the curve of the road's edge.
func _route_mouths() -> void:
	const FLARE := 3.0
	var n: int = track.sample_count()
	for j in net.junctions:
		var k: int = j["street"]
		var s: Dictionary = net.streets[k]
		var pts: PackedVector2Array = s["pts"]
		if pts.size() < 2:
			continue
		var pos: Vector2 = j["pos"]
		var first := pts[0].distance_to(pos) <= pts[pts.size() - 1].distance_to(pos)
		var e := pts[0] if first else pts[pts.size() - 1]
		var e1 := pts[1] if first else pts[pts.size() - 2]
		var into := (e1 - e).normalized()
		var nrm := _normal(pts, 0 if first else pts.size() - 1)
		var hw: float = float(s["w"]) * 0.5
		var i: int = j["index"]
		var side: float = j["side"]
		# both corners of the street's end, back along the street onto the road's edge
		var hit := []
		for c: Vector2 in [e + nrm * hw, e - nrm * hw]:
			var f := _edge_hit(c, -into, i, side)
			if f < 0.0:
				break
			hit.append(f)
		if hit.size() < 2:
			continue
		var fa: float = hit[0]
		var fb: float = hit[1]
		var fl := FLARE / float(track.SPACING)
		if fa < fb:
			fa -= fl
			fb += fl
		else:
			fa += fl
			fb -= fl
		var steps := maxi(int(ceil(absf(fb - fa))), 2)
		var y := Y_STREET - 0.002
		var prev_r := Vector3.ZERO
		var prev_s := Vector3.ZERO
		for t in steps + 1:
			var u := float(t) / steps
			var r := _edge_at(lerpf(fa, fb, u), side, n)
			var st2: Vector2 = (e + nrm * hw).lerp(e - nrm * hw, u)
			var rp := Vector3(r.x, y, r.y)
			var sp := Vector3(st2.x, y, st2.y)
			if t > 0:
				cm.quad("road", prev_r, rp, sp, prev_s, Vector3.UP, Color(1, 1, 1),
					Vector2(0.2 + 0.6 * (u - 1.0 / steps), 0.0), Vector2(0.2 + 0.6 * u, 0.0), Vector2(0.2 + 0.6 * u, 3.0), Vector2(0.2 + 0.6 * (u - 1.0 / steps), 3.0))
			prev_r = rp
			prev_s = sp
		stats["route_mouths"] = int(stats.get("route_mouths", 0)) + 1


## Point (x, z) on the route's road edge (0.4 m in under the road) at fractional sample index f.
func _edge_at(f: float, side: float, n: int) -> Vector2:
	var i0 := int(floor(f))
	var a: Vector3 = track.edge_point((i0 % n + n) % n, side * (float(track.hws[(i0 % n + n) % n]) - 0.4))
	var b: Vector3 = track.edge_point(((i0 + 1) % n + n) % n, side * (float(track.hws[((i0 + 1) % n + n) % n]) - 0.4))
	var t := f - float(i0)
	return Vector2(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))


## Where the line through p along dir meets the route's road edge on `side` near sample i, the
## crossing nearest to p (behind it too: a street meeting the route at a slant pokes one corner in
## past the edge): the fractional sample index (-1 if none within 60 m).
func _edge_hit(p: Vector2, dir: Vector2, i: int, side: float) -> float:
	var n: int = track.sample_count()
	var best_t := 1e9
	var best_f := -1.0
	for m in range(i - 30, i + 30):
		var a := _edge_at(float(m), side, n)
		var b := _edge_at(float(m + 1), side, n)
		var ab := b - a
		var den := dir.x * ab.y - dir.y * ab.x
		if absf(den) < 1e-6:
			continue
		var ap := a - p
		var t := (ap.x * ab.y - ap.y * ab.x) / den
		var u := (ap.x * dir.y - ap.y * dir.x) / den
		if u >= 0.0 and u <= 1.0 and absf(t) < best_t and absf(t) < 60.0:
			best_t = absf(t)
			best_f = float(m) + u
	return best_f


static func _normal(pts: PackedVector2Array, j: int) -> Vector2:
	var a := pts[maxi(j - 1, 0)]
	var b := pts[mini(j + 1, pts.size() - 1)]
	var t := (b - a).normalized()
	return Vector2(-t.y, t.x)


func _plate(c: Vector2, r: float) -> void:
	var seg := 20
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := Vector3(c.x + cos(a0) * r, Y_PLATE, c.y + sin(a0) * r)
		var p1 := Vector3(c.x + cos(a1) * r, Y_PLATE, c.y + sin(a1) * r)
		var pc := Vector3(c.x, Y_PLATE, c.y)
		cm.quad("road", pc, p0, p1, pc, Vector3.UP, Color(1, 1, 1),
			Vector2(0.5, c.y), Vector2(0.5 + cos(a0) * 0.25, p0.z), Vector2(0.5 + cos(a1) * 0.25, p1.z), Vector2(0.5, c.y))


func _markings(k: int) -> void:
	var s: Dictionary = net.streets[k]
	var pts: PackedVector2Array = s["pts"]
	var w: float = s["w"]
	var hw := w * 0.5
	var y := Y_STREET + 0.004 + Y_LINE
	var white := Color(0.92, 0.92, 0.9)
	var yellow := Color(0.95, 0.72, 0.12)
	var centre := yellow if (s["kind"] == "ring" or s["kind"] == "feeder") else white
	var kind: String = s["kind"]
	var total := 0.0
	for j in pts.size() - 1:
		total += pts[j].distance_to(pts[j + 1])
	var speed_done := false
	var dist := 0.0
	for j in pts.size() - 1:
		var a := pts[j]
		var b := pts[j + 1]
		var l := a.distance_to(b)
		var t := (b - a) / maxf(l, 0.01)
		var nrm := Vector2(-t.y, t.x)
		var mid := (a + b) * 0.5
		var skip: bool = _in_plate(mid, 2.5) or net.owner_at(mid) == -3 or _near_track(mid, 3.0)
		if not skip:
			# centre line (dashed on the small streets), edge lines
			var dash: bool = s["kind"] == "street" and int(dist / 3.0) % 2 == 1
			if not dash and w >= 7.0:
				_line(a, b, 0.0, 0.15, y, centre)
			for side: float in [-1.0, 1.0]:
				_line(a, b, side * (hw - 0.5), 0.12, y, white)
			# a manhole now and then
			if j % 9 == 4:
				_disc(mid + nrm * hw * 0.4, 0.4, y - 0.002, Color(0.16, 0.16, 0.17))
			# blue bicycle chevrons along the left edge of the wide streets (both directions)
			if w >= 10.0 and kind != "ring" and int(dist / 4.0) % 3 == 0 and l > 1.0:
				for side: float in [-1.0, 1.0]:
					var go := t * (-side)            # side -1 is the lane along t (keep left)
					_chevron(mid + nrm * side * (hw - 1.3), go, 0.9, y, BIKE_BLUE)
			# the speed limit in both lanes, half-way along the longer streets
			if not speed_done and dist > total * 0.5 and total > 70.0:
				speed_done = true
				var limit := "50" if kind == "ring" else ("40" if w >= 10.0 else "30")
				for side: float in [-1.0, 1.0]:
					_digits(limit, mid + nrm * side * hw * 0.5, t * (-side), y, white)
		dist += l
	# stop line and zebra crossing near both ends (where the street meets a junction plate)
	for end in [0, 1]:
		var e0 := pts[0] if end == 0 else pts[pts.size() - 1]
		var e1 := pts[1] if end == 0 else pts[pts.size() - 2]
		var dir := (e1 - e0).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var off := 0.0
		var plate_dirs: Array = []
		for pl in plates:
			if (pl[0] as Vector2).distance_to(e0) < 4.0:
				off = float(pl[1])
				plate_dirs = pl[2]
		if off == 0.0 and not _near_track(e0, 4.0) and not _t_junction(e0, k):
			continue
		if off == 0.0:
			off = 3.0
		var zc := e0 + dir * (off + 2.5)
		# the lane coming in (keep left): arrows for the ways on, diamonds announcing the crossing
		var lane_c := zc + nrm * hw * 0.5
		var d_in := -dir
		var ways := {}
		for od in plate_dirs:
			var o: Vector2 = od
			if o.dot(dir) > 0.98:
				continue                      # this street itself
			if o.dot(d_in) > 0.75:
				ways["straight"] = true
			elif o.dot(Vector2(d_in.y, -d_in.x)) > 0.0:
				ways["left"] = true
			else:
				ways["right"] = true
		if not ways.is_empty() and total > 24.0:
			_arrow(lane_c + dir * 9.0, d_in, ways.keys(), y, white)
		if total > 60.0:
			_diamond(lane_c + dir * 22.0, d_in, y, white)
		if total > 90.0:
			_diamond(lane_c + dir * 40.0, d_in, y, white)
		var n := int(w / 0.9)
		for z in n:
			var p := zc + nrm * (-hw + 0.45 + z * 0.9)
			_bar(p, dir, 0.45, 3.2, y, white)
		_bar_across(zc + dir * 2.5, nrm, hw * 0.95, 0.35, y, white)
		people_spots.append([Vector3(zc.x + nrm.x * (hw + 2.5), 0, zc.y + nrm.y * (hw + 2.5)), Vector3(-nrm.x, 0, -nrm.y)])


func _line(a: Vector2, b: Vector2, lat: float, width: float, y: float, col: Color) -> void:
	if width <= 0.0:
		return
	var t := (b - a).normalized()
	var n := Vector2(-t.y, t.x)
	var c0 := a + n * lat
	var c1 := b + n * lat
	cm.quad("line", Vector3(c0.x - n.x * width * 0.5, y, c0.y - n.y * width * 0.5), Vector3(c0.x + n.x * width * 0.5, y, c0.y + n.y * width * 0.5),
		Vector3(c1.x + n.x * width * 0.5, y, c1.y + n.y * width * 0.5), Vector3(c1.x - n.x * width * 0.5, y, c1.y - n.y * width * 0.5), Vector3.UP, col)


const BIKE_BLUE := Color(0.12, 0.32, 0.78)


## A segment from a to b, `wid` wide.
func _seg(a: Vector2, b: Vector2, wid: float, y: float, col: Color) -> void:
	if a.distance_to(b) > 0.01:
		_line(a, b, 0.0, wid, y, col)


## A filled triangle (arrow heads).
func _tri2(a: Vector2, b: Vector2, c: Vector2, y: float, col: Color) -> void:
	cm.tri("line", Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, col)


## A lane arrow pointing along `dir` (the way the traffic goes): a shaft, and a head for each of the
## ways on ("straight", "left", "right").
func _arrow(p: Vector2, dir: Vector2, ways: Array, y: float, col: Color) -> void:
	var left := Vector2(dir.y, -dir.x)
	var base := p - dir * 2.8
	var top := p + dir * 1.2
	_seg(base, top, 0.22, y, col)
	if ways.has("straight") or ways.size() == 0:
		_seg(top, p + dir * 1.8, 0.22, y, col)
		_tri2(p + dir * 1.8 - left * 0.5, p + dir * 1.8 + left * 0.5, p + dir * 3.2, y, col)
	for side in ["left", "right"]:
		if not ways.has(side):
			continue
		var sd := left if side == "left" else -left
		var knee := p - dir * 0.2
		var out := knee + sd * 1.0 + dir * 0.5
		_seg(knee, out, 0.22, y, col)
		var fw := (sd * 0.85 + dir * 0.5).normalized()
		var nb := Vector2(fw.y, -fw.x)
		_tri2(out - nb * 0.45, out + nb * 0.45, out + fw * 1.1, y, col)


## ◇ – a pedestrian crossing ahead (Japanese road marking), 5 m long.
func _diamond(p: Vector2, dir: Vector2, y: float, col: Color) -> void:
	var left := Vector2(dir.y, -dir.x)
	var f := p + dir * 2.5
	var b := p - dir * 2.5
	var l := p + left * 0.75
	var r := p - left * 0.75
	for e in [[f, l], [l, b], [b, r], [r, f]]:
		_seg(e[0], e[1], 0.15, y, col)


## A chevron pointing along `dir` (bicycle lane markings).
func _chevron(p: Vector2, dir: Vector2, size: float, y: float, col: Color) -> void:
	var left := Vector2(dir.y, -dir.x)
	_seg(p - dir * size * 0.5 + left * size * 0.4, p + dir * size * 0.3, 0.16, y, col)
	_seg(p - dir * size * 0.5 - left * size * 0.4, p + dir * size * 0.3, 0.16, y, col)


## Painted numbers (the speed limit): tall narrow digits read by a driver going along `dir`.
func _digits(text: String, p: Vector2, dir: Vector2, y: float, col: Color) -> void:
	const SEGS := {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
		"7": "abc", "8": "abcdefg", "9": "abcdfg"}
	var right := Vector2(-dir.y, dir.x)
	var dw := 0.8
	var dh := 3.0
	var gap := 0.35
	var x0 := -(text.length() * dw + (text.length() - 1) * gap) * 0.5
	for k in text.length():
		var segs: String = SEGS.get(text[k], "")
		var o := p + right * (x0 + k * (dw + gap)) - dir * dh * 0.5
		var pt := func(u: float, v: float) -> Vector2:
			return o + right * u * dw + dir * v * dh
		var lines := {"a": [Vector2(0, 1), Vector2(1, 1)], "b": [Vector2(1, 1), Vector2(1, 0.5)], "c": [Vector2(1, 0.5), Vector2(1, 0)],
			"d": [Vector2(0, 0), Vector2(1, 0)], "e": [Vector2(0, 0), Vector2(0, 0.5)], "f": [Vector2(0, 0.5), Vector2(0, 1)],
			"g": [Vector2(0, 0.5), Vector2(1, 0.5)]}
		for sg in segs:
			var e: Array = lines[sg]
			_seg(pt.call(e[0].x, e[0].y), pt.call(e[1].x, e[1].y), 0.16, y, col)


## A bar `len_` long along `dir`, `wid` wide, centred at p.
func _bar(p: Vector2, dir: Vector2, wid: float, len_: float, y: float, col: Color) -> void:
	var n := Vector2(-dir.y, dir.x)
	var a := p - dir * len_ * 0.5
	var b := p + dir * len_ * 0.5
	cm.quad("line", Vector3(a.x - n.x * wid * 0.5, y, a.y - n.y * wid * 0.5), Vector3(a.x + n.x * wid * 0.5, y, a.y + n.y * wid * 0.5),
		Vector3(b.x + n.x * wid * 0.5, y, b.y + n.y * wid * 0.5), Vector3(b.x - n.x * wid * 0.5, y, b.y - n.y * wid * 0.5), Vector3.UP, col)


func _bar_across(p: Vector2, across: Vector2, half: float, wid: float, y: float, col: Color) -> void:
	var t := Vector2(across.y, -across.x)
	var a := p - across * half
	var b := p + across * half
	cm.quad("line", Vector3(a.x - t.x * wid * 0.5, y, a.y - t.y * wid * 0.5), Vector3(a.x + t.x * wid * 0.5, y, a.y + t.y * wid * 0.5),
		Vector3(b.x + t.x * wid * 0.5, y, b.y + t.y * wid * 0.5), Vector3(b.x - t.x * wid * 0.5, y, b.y - t.y * wid * 0.5), Vector3.UP, col)


func _disc(c: Vector2, r: float, y: float, col: Color) -> void:
	for k in 10:
		var a0 := TAU * k / 10.0
		var a1 := TAU * (k + 1) / 10.0
		var pc := Vector3(c.x, y, c.y)
		cm.quad("line", pc, pc + Vector3(cos(a0) * r, 0, sin(a0) * r), pc + Vector3(cos(a1) * r, 0, sin(a1) * r), pc, Vector3.UP, col)


## Kerb stones along both edges (visual; the pavement behind them is level with the road).
func _kerbs(k: int) -> void:
	var s: Dictionary = net.streets[k]
	var pts: PackedVector2Array = s["pts"]
	var hw: float = float(s["w"]) * 0.5
	var col := Color(0.66, 0.66, 0.64)
	for j in pts.size() - 1:
		var a := pts[j]
		var b := pts[j + 1]
		for side: float in [-1.0, 1.0]:
			var na := _normal(pts, j) * side * (hw + 0.15)
			var nb := _normal(pts, j + 1) * side * (hw + 0.15)
			var pa := a + na
			var pb := b + nb
			var mid := (pa + pb) * 0.5
			if _in_plate(mid, 0.5) or _near_track(mid, 1.0) or net.value_at(mid) == net.ROAD and net.owner_at(mid) != k:
				continue
			var dir := Vector3(pb.x - pa.x, 0, pb.y - pa.y)
			var l := dir.length()
			if l < 0.1:
				continue
			cm.box("frame", Transform3D(Basis.looking_at(dir / l, Vector3.UP), Vector3(mid.x, 0.07, mid.y)), Vector3(0.3, 0.14, l + 0.05), col)


# ---------------------------------------------------------------------------
# Along the pavements
# ---------------------------------------------------------------------------
func _furniture(k: int) -> void:
	var s: Dictionary = net.streets[k]
	var pts: PackedVector2Array = s["pts"]
	var w: float = s["w"]
	var hw := w * 0.5
	var narrow := w < 10.0
	var kind: String = s["kind"]
	var total := 0.0
	var poles: Array = [[], []]
	var lamp_every := 18.0 if not narrow else 20.0
	var next_lamp := [rng.randf_range(4.0, 14.0), rng.randf_range(4.0, 14.0) + lamp_every * 0.5]
	var next_tree := [rng.randf_range(3.0, 8.0), rng.randf_range(3.0, 8.0)]
	var next_pole := rng.randf_range(5.0, 20.0)
	var next_hydrant := [rng.randf_range(20.0, 60.0), rng.randf_range(20.0, 60.0)]
	var next_misc := [rng.randf_range(10.0, 30.0), rng.randf_range(10.0, 30.0)]
	var parking := [not narrow and kind != "ring" and kind != "crossing" and rng.randf() < 0.5, false]
	parking[1] = not narrow and kind == "street" and rng.randf() < 0.3
	for j in pts.size() - 1:
		var a := pts[j]
		var b := pts[j + 1]
		var l := a.distance_to(b)
		var t := (b - a) / maxf(l, 0.01)
		var nrm := Vector2(-t.y, t.x)
		var steps := maxi(int(l / 2.0), 1)
		for q in steps:
			var d := total + l * float(q) / steps
			var p := a.lerp(b, float(q) / steps)
			if _in_plate(p, 3.0) or _near_track(p, 4.0):
				continue
			for si in 2:
				var side := -1.0 if si == 0 else 1.0
				var kerb := p + nrm * side * (hw + 0.6)
				var walk := p + nrm * side * (hw + 2.2)
				if net.value_at(walk) == net.ROAD:
					continue        # another street (junction mouth)
				var face := Vector3(-nrm.x * side, 0, -nrm.y * side)    # towards the road
				# streetlights on both sides, staggered
				if d >= float(next_lamp[si]):
					next_lamp[si] = d + lamp_every
					_streetlight(Vector3(kerb.x, 0, kerb.y), face, hw)
				# trees on the wide streets
				elif not narrow and d >= float(next_tree[si]):
					next_tree[si] = d + rng.randf_range(10.0, 13.0)
					var tk := "sakura" if sakura_streets.has(k) else "tree"
					var sc := rng.randf_range(0.85, 1.1) * (1.0 if tk == "sakura" else 0.62)
					add_inst.call(tk, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc, sc)), Vector3(walk.x, 0, walk.y)), Color(1, 1, 1, 1))
					add_inst.call("tree_pit", Transform3D(Basis.looking_at(face, Vector3.UP), Vector3(walk.x, 0.0, walk.y)), Color(1, 1, 1, 1))
				# hydrants
				if d >= float(next_hydrant[si]):
					next_hydrant[si] = d + rng.randf_range(55.0, 90.0)
					# breakable (a fountain when knocked off): city_lamps.gd
					lamps.add_hydrant(Vector3(kerb.x + t.x * 1.2, 0, kerb.y + t.y * 1.2), face)
				# vending machines, bicycles, benches, bins, post boxes
				if d >= float(next_misc[si]):
					next_misc[si] = d + rng.randf_range(14.0, 40.0)
					_misc(Vector3(p.x + nrm.x * side * (hw + 4.0), 0, p.y + nrm.y * side * (hw + 4.0)), face, Vector2(t.x, t.y))
				# pedestrians
				if rng.randf() < 0.035:
					var pp := p + nrm * side * (hw + rng.randf_range(1.5, 4.0))
					people_spots.append([Vector3(pp.x, 0, pp.y), Vector3(t.x, 0, t.y) * (1.0 if rng.randf() < 0.5 else -1.0)])
				# parking bays (parallel, inside the street edge) every 6 m
				if parking[si] and q == 0 and j % 2 == 0 and j > 2 and j < pts.size() - 4:
					_parking_bay(p + nrm * side * (hw - 1.3), t, side, k)
			# utility poles (one side) on the narrow streets
			if narrow and d >= next_pole:
				next_pole = d + rng.randf_range(28.0, 34.0)
				var pp := p + nrm * (hw + 0.8)
				if net.value_at(p + nrm * (hw + 2.0)) != net.ROAD:
					# breakable, with the little security light every one carries over the street
					# (city_lamps.gd); the wires between them follow
					var pi: int = lamps.add_utility_pole(Vector3(pp.x, 0, pp.y), Vector3(t.x, 0, t.y), Vector3(-nrm.x, 0, -nrm.y))
					poles[0].append([Vector3(pp.x, 0, pp.y), pi])
					stats["pole_lights"] = int(stats.get("pole_lights", 0)) + 1
		total += l
	_wires(poles[0])
	# traffic signals where the street meets a junction plate or the race route
	for end in [0, 1]:
		var e0 := pts[0] if end == 0 else pts[pts.size() - 1]
		var e1 := pts[1] if end == 0 else pts[pts.size() - 2]
		var dir := (e1 - e0).normalized()
		var off := 0.0
		for pl in plates:
			if (pl[0] as Vector2).distance_to(e0) < 4.0:
				off = float(pl[1])
		if off == 0.0:
			if _near_track(e0, 4.0):
				off = 4.0
			elif _t_junction(e0, k):
				off = 3.0
			else:
				continue
		var nrm := Vector2(-dir.y, dir.x)
		var sp := e0 + dir * (off + 5.0) + nrm * (hw + 1.0)
		# the signal faces the cars coming up the street towards the junction
		_signal(Vector3(sp.x, 0, sp.y), Vector3(dir.x, 0, dir.y), Vector3(-nrm.x, 0, -nrm.y), hw)


static var _barricade_mesh: ArrayMesh

## A Japanese road closure stand: an A-frame with yellow and black striped legs, a white board
## "通行止め / ROAD CLOSED" (readable from both sides) and a blinking red lamp on top; a RigidBody.
func _barricade() -> RigidBody3D:
	if _barricade_mesh == null:
		_barricade_mesh = _make_barricade_mesh()
	var b := RigidBody3D.new()
	b.mass = 22.0
	b.collision_layer = 8
	b.collision_mask = 1 | 2 | 4 | 8
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.5, 1.7, 0.9)
	cs.shape = sh
	cs.position = Vector3(0, 0.85, 0)
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _barricade_mesh
	b.add_child(mi)
	b.sleeping = true
	stats["roadblocks"] = int(stats.get("roadblocks", 0)) + 1
	return b


static func _make_barricade_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# the board: both faces show the atlas cell, a white rim round it
	var st := MeshKit.new_st()
	var rect: Rect2 = CityAtlas.shop(63)
	var u0 := rect.position.x
	var u1 := rect.end.x
	var v0 := rect.position.y
	var v1 := rect.end.y
	var w := 1.15
	var h0 := 0.95
	var h1 := 1.55
	var col := Color(0.6, 0, 0, 1)        # (red channel: how much it glows at night)
	for side: float in [-1.0, 1.0]:
		var z := side * 0.03
		if side > 0.0:
			MeshKit.quad(st, Vector3(-w, h0, z), Vector3(w, h0, z), Vector3(w, h1, z), Vector3(-w, h1, z), Vector3(0, 0, 1),
				Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0), col)
		else:
			MeshKit.quad(st, Vector3(w, h0, z), Vector3(-w, h0, z), Vector3(-w, h1, z), Vector3(w, h1, z), Vector3(0, 0, -1),
				Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0), col)
	mesh = MeshKit.commit(st, CityAtlas.material(), mesh)
	# frame: rim, A-frame legs (yellow / black stripes), feet; the lamp housing
	var fr := MeshKit.new_st()
	var white := Color(0.95, 0.95, 0.93)
	MeshKit.box(fr, Transform3D(Basis.IDENTITY, Vector3(0, h1 + 0.04, 0)), Vector3(w * 2.0 + 0.1, 0.08, 0.07), white)
	MeshKit.box(fr, Transform3D(Basis.IDENTITY, Vector3(0, h0 - 0.04, 0)), Vector3(w * 2.0 + 0.1, 0.08, 0.07), white)
	for sx: float in [-1.0, 1.0]:
		MeshKit.box(fr, Transform3D(Basis.IDENTITY, Vector3(sx * (w + 0.04), (h0 + h1) * 0.5, 0)), Vector3(0.08, h1 - h0 + 0.16, 0.07), white)
		for sz: float in [-1.0, 1.0]:
			# a leg leaning out to the foot, in stripes
			var top := Vector3(sx * (w - 0.1), h1 + 0.02, 0)
			var foot := Vector3(sx * (w - 0.1), 0.0, sz * 0.42)
			var seg := 6
			for k in seg:
				var a := top.lerp(foot, float(k) / seg)
				var b2 := top.lerp(foot, float(k + 1) / seg)
				var basis := Basis.looking_at((b2 - a).normalized(), Vector3.RIGHT if absf((b2 - a).normalized().y) > 0.99 else Vector3.UP)
				var c := Color(0.98, 0.8, 0.05) if k % 2 == 0 else Color(0.08, 0.08, 0.08)
				MeshKit.box(fr, Transform3D(basis, (a + b2) * 0.5), Vector3(0.06, 0.06, a.distance_to(b2) + 0.01), c)
		# the foot bar on the ground
		MeshKit.box(fr, Transform3D(Basis.IDENTITY, Vector3(sx * (w - 0.1), 0.03, 0)), Vector3(0.08, 0.06, 0.9), Color(0.1, 0.1, 0.1))
	MeshKit.box(fr, Transform3D(Basis.IDENTITY, Vector3(0, h1 + 0.12, 0)), Vector3(0.16, 0.08, 0.16), Color(0.1, 0.1, 0.1))
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.roughness = 0.55
	mesh = MeshKit.commit(fr, fm, mesh)
	# the blinking red lamp
	var lamp := MeshKit.new_st()
	MeshKit.box(lamp, Transform3D(Basis.IDENTITY, Vector3(0, h1 + 0.25, 0)), Vector3(0.18, 0.18, 0.18), Color(1, 0.1, 0.05))
	var lm := ShaderMaterial.new()
	lm.shader = Shader.new()
	lm.shader.code = """
shader_type spatial;
render_mode unshaded;
void fragment() {
	float on = step(0.5, fract(TIME * 1.3));
	ALBEDO = vec3(1.0, 0.08, 0.04) * (0.35 + 2.6 * on);
}
"""
	mesh = MeshKit.commit(lamp, lm, mesh)
	return mesh


func _streetlight(p: Vector3, face: Vector3, hw: float) -> void:
	# breakable: drawn, made solid and knocked over by city_lamps.gd
	lamps.add(p, face, hw)
	stats["streetlights"] = int(stats.get("streetlights", 0)) + 1


func _misc(p: Vector3, face: Vector3, along: Vector2) -> void:
	var basis := Basis.looking_at(face, Vector3.UP)
	var r := rng.randf()
	if r < 0.3:
		# knockable (city_lamps.gd)
		lamps.add_vending(p, face)
	elif r < 0.5:
		for k in rng.randi_range(2, 5):
			add_inst.call("bicycle", Transform3D(Basis.looking_at(face, Vector3.UP).rotated(Vector3.UP, PI * 0.5 + rng.randf_range(-0.1, 0.1)), p + Vector3(along.x, 0, along.y) * (k * 0.7)), Color(1, 1, 1, 1))
	elif r < 0.65:
		add_inst.call("bench", Transform3D(basis.rotated(Vector3.UP, PI), p), Color(1, 1, 1, 1))
		add_inst.call("bin", Transform3D(basis, p + Vector3(along.x, 0, along.y) * 1.5), Color(1, 1, 1, 1))
	elif r < 0.75:
		add_inst.call("postbox", Transform3D(basis, p), Color(1, 1, 1, 1))
	elif r < 0.85:
		add_inst.call("bin", Transform3D(basis, p), Color(1, 1, 1, 1))
	else:
		_bus_stop(p, face, along)


func _bus_stop(p: Vector3, face: Vector3, along: Vector2) -> void:
	var basis := Basis.looking_at(face, Vector3.UP)
	var col := Color(0.45, 0.47, 0.5, 0.5)
	for x: float in [-1.6, 1.6]:
		cm.box("metal", Transform3D(basis, p + basis.x * x + Vector3(0, 1.2, 0) - face * 0.6), Vector3(0.1, 2.4, 0.1), col)
	cm.box("metal", Transform3D(basis, p + Vector3(0, 2.45, 0) - face * 0.2), Vector3(3.6, 0.1, 1.6), col)
	cm.box("frame", Transform3D(basis, p + Vector3(0, 0.45, 0) - face * 0.7), Vector3(2.4, 0.08, 0.4), Color(0.5, 0.35, 0.2))
	# the lit ad panel at one end, the stop sign at the kerb
	var ad_basis := Basis.looking_at(Vector3(along.x, 0, along.y), Vector3.UP)
	cm.sign_box(Transform3D(ad_basis, p + basis.x * 1.75 + Vector3(0, 1.25, 0) - face * 0.2), Vector3(1.2, 1.8, 0.12), CityAtlas.ad(rng.randi()), 1.0, true)
	cm.box("metal", Transform3D(basis, p + face * 1.2 + Vector3(0, 1.3, 0)), Vector3(0.08, 2.6, 0.08), col)
	cm.sign_box(Transform3D(basis.rotated(Vector3.UP, PI), p + face * 1.2 + Vector3(0, 2.5, 0)), Vector3(0.5, 0.5, 0.05), CityAtlas.misc(6), 0.6, true)
	light.call(p + Vector3(0, 2.2, 0), Color(0.9, 0.95, 1.0), 6.0, 1.0, 0)
	stats["bus_stops"] = int(stats.get("bus_stops", 0)) + 1


func _parking_bay(p: Vector2, t: Vector2, side: float, k: int) -> void:
	if _in_plate(p, 8.0) or _near_track(p, 10.0):
		return
	var y := Y_STREET + 0.004 + Y_LINE
	var white := Color(0.92, 0.92, 0.9)
	var n := Vector2(-t.y, t.x) * side
	# the bay outline: the outer line along the lane and the two end ticks
	_line(p - t * 3.0 - n * 1.2, p + t * 3.0 - n * 1.2, 0.0, 0.12, y, white)
	_line(p - t * 3.0 - n * 1.2, p - t * 3.0 + n * 1.2, 0.0, 0.12, y, white)
	if rng.randf() < 0.65 and scenery.details:
		var yaw := atan2(-t.x, -t.y) if rng.randf() < 0.5 else atan2(t.x, t.y)
		scenery.details.add_parked_car(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y)))
	if rng.randf() < 0.3:
		add_inst.call("meter", Transform3D(Basis.looking_at(Vector3(-n.x, 0, -n.y), Vector3.UP), Vector3(p.x + n.x * 1.7, 0, p.y + n.y * 1.7)), Color(1, 1, 1, 1))
	stats["parking_bays"] = int(stats.get("parking_bays", 0)) + 1


## Car and pedestrian signals at a street's mouth: pole on the kerb, mast arm over the lane – they
## can be knocked over (city_lamps.gd).
func _signal(p: Vector3, face: Vector3, across: Vector3, hw: float) -> void:
	lamps.add_signal(p, face, across, hw, rng.randi() % 3)
	stats["signals"] = int(stats.get("signals", 0)) + 1


## Sagging cables between neighbouring utility poles ([position, index in city_lamps]); they come
## down with a pole.
func _wires(poles: Array) -> void:
	for k in poles.size() - 1:
		var a: Vector3 = poles[k][0]
		var b: Vector3 = poles[k + 1][0]
		if a.distance_to(b) > 45.0:
			continue
		lamps.add_span(int(poles[k][1]), int(poles[k + 1][1]))


## Race mode: a row of water-filled barriers across every side street, a few metres from the race
## route, and a "road closed" board. They are loose bodies; free roam can take them away.
func _closures(parent: Node3D) -> void:
	for j in net.junctions:
		var pos: Vector2 = j["pos"]
		var i: int = j["index"]
		var side: float = j["side"]
		var r: Vector3 = track.rights[i] * side
		var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
		var w: float = j["w"]
		var c := Vector3(pos.x, 0, pos.y) + r * 7.0
		var n := int(w / 1.3) + 1
		for k in n:
			var bp := c + t * (-w * 0.5 + 0.2 + k * 1.3) + Vector3(0, 0.45, 0)
			var b := RigidBody3D.new()
			b.mass = 120.0
			b.collision_layer = 8
			b.collision_mask = 1 | 2 | 4 | 8
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(1.2, 0.9, 0.5)
			cs.shape = sh
			b.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.2, 0.9, 0.5)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.9, 0.1, 0.08) if k % 2 == 0 else Color(0.95, 0.95, 0.95)
			m.roughness = 0.6
			bm.material = m
			mi.mesh = bm
			b.add_child(mi)
			parent.add_child(b)
			b.global_transform = Transform3D(Basis.looking_at(r, Vector3.UP), bp)
			b.sleeping = true
			b.add_to_group("race_closure")
			closures.append(b)
		# the "road closed" barricade in front of them, facing the race route: knock it over if you like
		var bar := _barricade()
		parent.add_child(bar)
		bar.global_transform = Transform3D(Basis.looking_at(r, Vector3.UP), c - r * 1.8 + Vector3(0, 0.02, 0))
		bar.add_to_group("race_closure")
		closures.append(bar)
