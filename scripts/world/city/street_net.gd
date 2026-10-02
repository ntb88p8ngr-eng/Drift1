extends RefCounted
## Neo Tokyo's street network: an organic web of streets around the race route – the edges of a
## jittered Voronoi diagram, gently curved – with everything connected: side streets meet the race
## route at junctions (openings in its walls), a ring road closes the outside, short stubs are merged
## and dead ends removed. Also the occupancy raster (2 m cells) the buildings, parks and car parks are
## placed on, and the queries a free roam mode needs (nearest street, spawn points).

const CELL := 2.0
const FREE := 0
const ROAD := 1
const WALK := 2          # pavement / kerb zone
const BUILT := 3
const RESERVED := 4      # parks, car parks, plazas
const SIDEWALK := 4.5    # pavement width beside every street (m)
const SPACING := 92.0    # mean block size (Voronoi seed spacing)
const NO_JUNCTION := [-35.0, 30.0]   # around the start line (grid, gantry, grandstand): no side streets

var track
var area: Rect2
var nx := 0
var nz := 0
var grid := PackedByteArray()
var owner := PackedInt32Array()      # street index per road cell, -2 = junction (two streets), -3 = race route
var streets: Array = []              # {pts: PackedVector2Array, w: float, kind: String}
var junctions: Array = []            # on the race route: {progress, side, w, pos: Vector2, street}
var crossing_progress := 90.0
var rng := RandomNumberGenerator.new()


func build(p_track) -> void:
	track = p_track
	rng.seed = 5150
	area = (track.bounds as Rect2).grow(230.0)
	nx = int(ceil(area.size.x / CELL)) + 1
	nz = int(ceil(area.size.y / CELL)) + 1
	grid.resize(nx * nz)
	grid.fill(FREE)
	owner.resize(nx * nz)
	owner.fill(-1)
	_mark_track()
	var g := _voronoi_graph()
	g = _cut_at_track(g)
	g = _remove_dead_ends(g)
	_make_streets(g)
	for k in streets.size():
		_raster_street(k)
	_crossing_streets()


# ---------------------------------------------------------------------------
# Raster
# ---------------------------------------------------------------------------
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - area.position.x) / CELL)), int(floor((p.y - area.position.y) / CELL)))


func value_at(p: Vector2) -> int:
	var c := cell_of(p)
	if c.x < 0 or c.y < 0 or c.x >= nx or c.y >= nz:
		return ROAD           # outside: treat as taken
	return grid[c.y * nx + c.x]


func owner_at(p: Vector2) -> int:
	var c := cell_of(p)
	if c.x < 0 or c.y < 0 or c.x >= nx or c.y >= nz:
		return -1
	return owner[c.y * nx + c.x]


func set_at(p: Vector2, v: int) -> void:
	var c := cell_of(p)
	if c.x >= 0 and c.y >= 0 and c.x < nx and c.y < nz:
		grid[c.y * nx + c.x] = v


## Cells of an oriented rectangle (centre c, unit x axis ax, half sizes hx along ax, hz across).
func _rect_cells(c: Vector2, ax: Vector2, hx: float, hz: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var az := Vector2(-ax.y, ax.x)
	var ext := absf(ax.x) * hx + absf(az.x) * hz
	var ezt := absf(ax.y) * hx + absf(az.y) * hz
	var c0 := cell_of(c - Vector2(ext, ezt))
	var c1 := cell_of(c + Vector2(ext, ezt))
	for iz in range(maxi(c0.y, 0), mini(c1.y + 1, nz)):
		for ix in range(maxi(c0.x, 0), mini(c1.x + 1, nx)):
			var p := area.position + Vector2((ix + 0.5) * CELL, (iz + 0.5) * CELL) - c
			if absf(p.dot(ax)) <= hx and absf(p.dot(az)) <= hz:
				out.append(iz * nx + ix)
	return out


## True when every cell of the rectangle has one of the `allowed` values (and it lies in the area).
func rect_is(c: Vector2, ax: Vector2, hx: float, hz: float, allowed := [FREE]) -> bool:
	var az := Vector2(-ax.y, ax.x)
	for corner in [ax * hx + az * hz, ax * hx - az * hz, -ax * hx + az * hz, -ax * hx - az * hz]:
		if not area.grow(-2.0).has_point(c + (corner as Vector2)):
			return false
	for i in _rect_cells(c, ax, hx, hz):
		if not allowed.has(int(grid[i])):
			return false
	return true


func mark_rect(c: Vector2, ax: Vector2, hx: float, hz: float, v: int) -> void:
	for i in _rect_cells(c, ax, hx, hz):
		grid[i] = v


## Distance (m) from every free cell to the nearest taken one (two-pass chamfer).
func clearance() -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(nx * nz)
	for i in nx * nz:
		d[i] = 1e6 if grid[i] == FREE else 0.0
	var dg := CELL * 1.4142
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			if d[i] == 0.0:
				continue
			var v := d[i]
			if ix > 0: v = minf(v, d[i - 1] + CELL)
			if iz > 0:
				v = minf(v, d[i - nx] + CELL)
				if ix > 0: v = minf(v, d[i - nx - 1] + dg)
				if ix < nx - 1: v = minf(v, d[i - nx + 1] + dg)
			d[i] = v
	for iz in range(nz - 1, -1, -1):
		for ix in range(nx - 1, -1, -1):
			var i := iz * nx + ix
			if d[i] == 0.0:
				continue
			var v := d[i]
			if ix < nx - 1: v = minf(v, d[i + 1] + CELL)
			if iz < nz - 1:
				v = minf(v, d[i + nx] + CELL)
				if ix < nx - 1: v = minf(v, d[i + nx + 1] + dg)
				if ix > 0: v = minf(v, d[i + nx - 1] + dg)
			d[i] = v
	return d


func cell_center(i: int) -> Vector2:
	return area.position + Vector2((i % nx + 0.5) * CELL, (i / nx + 0.5) * CELL)


## The race route: road and walls are "road" (owned by the route), a pavement strip beyond the walls.
func _mark_track() -> void:
	var n: int = track.sample_count()
	for i in n:
		var s: Vector3 = track.samples[i]
		var r: Vector3 = track.rights[i]
		var reach := maxf(float(track.off_left[i]), float(track.off_right[i])) + 0.5
		for side: float in [-1.0, 1.0]:
			var off: float = (track.off_left[i] if side < 0.0 else track.off_right[i])
			var lat := 0.0
			while lat <= off + 0.5 + SIDEWALK:
				var p := Vector2(s.x + r.x * side * lat, s.z + r.z * side * lat)
				var c := cell_of(p)
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var ix: int = c.x + dx
						var iz: int = c.y + dz
						if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
							continue
						var k := iz * nx + ix
						if lat <= off + 0.5:
							grid[k] = ROAD
							owner[k] = -3
						elif grid[k] == FREE:
							grid[k] = WALK
				lat += CELL
		reach = reach


# ---------------------------------------------------------------------------
# Graph: Voronoi edges of jittered seeds, clipped to the area
# ---------------------------------------------------------------------------
## Returns {nodes: Array[Vector2], kinds: Array[String] ("node"/"ring"/"track"), edges: Array[Vector2i],
## jn: Dictionary node -> junction data}
func _voronoi_graph() -> Dictionary:
	var pts := PackedVector2Array()
	var big := area.grow(SPACING * 1.5)
	var gz := big.position.y
	var row := 0
	while gz < big.end.y:
		var gx := big.position.x + (SPACING * 0.5 if row % 2 == 1 else 0.0)
		while gx < big.end.x:
			pts.append(Vector2(gx + rng.randf_range(-0.36, 0.36) * SPACING, gz + rng.randf_range(-0.36, 0.36) * SPACING))
			gx += SPACING * rng.randf_range(0.85, 1.15)
		gz += SPACING * 0.87
		row += 1
	var tri := Geometry2D.triangulate_delaunay(pts)
	var cc: Array = []
	for t in tri.size() / 3:
		cc.append(_circum(pts[tri[t * 3]], pts[tri[t * 3 + 1]], pts[tri[t * 3 + 2]]))
	var edge_tris := {}
	for t in tri.size() / 3:
		for e in 3:
			var a: int = tri[t * 3 + e]
			var b: int = tri[t * 3 + (e + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not edge_tris.has(key):
				edge_tris[key] = []
			edge_tris[key].append(t)
	var inner := area.grow(-10.0)
	var g := {"nodes": [], "kinds": [], "edges": [], "jn": {}}
	var index := {}
	for key in edge_tris:
		var ts: Array = edge_tris[key]
		if ts.size() != 2:
			continue
		var a: Vector2 = cc[ts[0]]
		var b: Vector2 = cc[ts[1]]
		if a.distance_to(b) < 1.0:
			continue
		var clip := _clip(a, b, inner)
		if clip.is_empty():
			continue
		var ia := _node(g, index, clip[0], "ring" if clip[2] else "node")
		var ib := _node(g, index, clip[1], "ring" if clip[3] else "node")
		if ia != ib:
			g["edges"].append(Vector2i(ia, ib))
	_collapse_short(g, 16.0)
	return g


static func _circum(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-6:
		return (a + b + c) / 3.0
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)


## Liang–Barsky: [a', b', a_clipped, b_clipped] or [] when outside.
static func _clip(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for k in 4:
		if absf(p[k]) < 1e-9:
			if q[k] < 0.0:
				return []
		else:
			var t: float = q[k] / p[k]
			if p[k] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1, t0 > 0.0, t1 < 1.0]


func _node(g: Dictionary, index: Dictionary, p: Vector2, kind: String) -> int:
	var key := Vector2i(int(round(p.x * 10.0)), int(round(p.y * 10.0)))
	if index.has(key):
		var i: int = index[key]
		if kind == "ring":
			g["kinds"][i] = "ring"
		return i
	g["nodes"].append(p)
	g["kinds"].append(kind)
	index[key] = g["nodes"].size() - 1
	return g["nodes"].size() - 1


## Merges the ends of edges shorter than `min_len` (union-find), drops loops and duplicates.
func _collapse_short(g: Dictionary, min_len: float) -> void:
	var nodes: Array = g["nodes"]
	var parent: Array = []
	for i in nodes.size():
		parent.append(i)
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	for e in g["edges"]:
		var a: int = find.call(e.x)
		var b: int = find.call(e.y)
		if a != b and (nodes[a] as Vector2).distance_to(nodes[b]) < min_len:
			# keep a ring node where it is (it sits on the ring road)
			if g["kinds"][b] == "ring" and g["kinds"][a] != "ring":
				parent[a] = b
			else:
				if g["kinds"][a] != "ring":
					nodes[a] = ((nodes[a] as Vector2) + (nodes[b] as Vector2)) * 0.5
				parent[b] = a
	var seen := {}
	var edges: Array = []
	for e in g["edges"]:
		var a: int = find.call(e.x)
		var b: int = find.call(e.y)
		if a == b:
			continue
		var key := Vector2i(mini(a, b), maxi(a, b))
		if seen.has(key):
			continue
		seen[key] = true
		edges.append(key)
	g["edges"] = edges


# ---------------------------------------------------------------------------
# The race route: edges crossing it become junctions on both sides, edges running along it go
# ---------------------------------------------------------------------------
func _cut_at_track(g: Dictionary) -> Dictionary:
	var nodes: Array = g["nodes"]
	var out := {"nodes": nodes.duplicate(), "kinds": (g["kinds"] as Array).duplicate(), "edges": [], "jn": {}}
	var index := {}
	var taken := {-1.0: [], 1.0: []}        # junction progresses per side
	# crossing street: keep its surroundings free of other junctions
	for side: float in [-1.0, 1.0]:
		taken[side].append(crossing_progress)
	for e in g["edges"]:
		var a: Vector2 = nodes[e.x]
		var b: Vector2 = nodes[e.y]
		var l := a.distance_to(b)
		var n := maxi(int(l / 1.0), 2)
		var first := -1
		var last := -1
		var near := false
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var v := value_at(p)
			var o := owner_at(p)
			if v == ROAD and o == -3:
				if _over_deck(p):
					continue           # under the raised expressway: the street passes beneath
				if first < 0:
					first = k
				last = k
			elif v == WALK:
				near = true
		if first < 0:
			if near:
				continue               # runs along the route, no room for anything: drop
			out["edges"].append(e)
			continue
		# part before the route and part after it, each ending at the route's wall as a junction
		for part in [[a, b, first, e.x], [b, a, n - last, e.y]]:
			var s: Vector2 = part[0]
			var t: Vector2 = part[1]
			var hit: int = part[2]
			var p_end := s.lerp(t, float(hit) / n)
			if s.distance_to(p_end) < 18.0:
				continue
			var j := _junction(p_end, (t - s).normalized(), taken)
			if j.is_empty():
				continue
			var ni: int = out["nodes"].size()
			out["nodes"].append(j["pos"])
			out["kinds"].append("track")
			out["jn"][ni] = j
			out["edges"].append(Vector2i(part[3], ni))
	return out


## The junction where a street coming in along `dir` meets the race route at p (its wall), or {} when
## the angle is too shallow, it's on a ramp / the start area, or another junction is too close.
func _junction(p: Vector2, dir: Vector2, taken: Dictionary) -> Dictionary:
	var pr: Array = track.project(Vector3(p.x, 0, p.y), -1)
	var i: int = pr[0]
	var t: Vector3 = track.tangents[i]
	var t2 := Vector2(t.x, t.z).normalized()
	if absf(t2.dot(dir)) > 0.55:
		return {}
	if float(track.samples[i].y) > 0.15:
		return {}
	var prog: float = pr[1]
	var rel := fposmod(prog + 300.0, float(track.length)) - 300.0
	if rel > NO_JUNCTION[0] and rel < NO_JUNCTION[1]:
		return {}
	var side := signf(float(pr[2]))
	for q in taken[side]:
		var d := absf(fposmod(prog - float(q) + track.length * 0.5, track.length) - track.length * 0.5)
		if d < 34.0:
			return {}
	taken[side].append(prog)
	var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
	var s: Vector3 = track.samples[i]
	var r: Vector3 = track.rights[i]
	var edge := Vector2(s.x + r.x * side * (off + 0.3), s.z + r.z * side * (off + 0.3))
	return {"progress": prog, "side": side, "pos": edge, "index": i}


func _over_deck(p: Vector2) -> bool:
	var i: int = track.nearest_index(Vector3(p.x, 0, p.y))
	return float(track.samples[i].y) > 5.5


func _remove_dead_ends(g: Dictionary) -> Dictionary:
	var changed := true
	while changed:
		changed = false
		var deg := {}
		for e in g["edges"]:
			deg[e.x] = int(deg.get(e.x, 0)) + 1
			deg[e.y] = int(deg.get(e.y, 0)) + 1
		var keep: Array = []
		for e in g["edges"]:
			var ok := true
			for ni in [e.x, e.y]:
				if int(deg[ni]) < 2 and g["kinds"][ni] == "node":
					ok = false
			if ok:
				keep.append(e)
			else:
				changed = true
		g["edges"] = keep
	return g


# ---------------------------------------------------------------------------
# Streets: curved polylines with a width; the ring road; the scramble crossing's cross street
# ---------------------------------------------------------------------------
func _make_streets(g: Dictionary) -> void:
	var nodes: Array = g["nodes"]
	var kinds: Array = g["kinds"]
	for e in g["edges"]:
		var a: Vector2 = nodes[e.x]
		var b: Vector2 = nodes[e.y]
		var to_track: bool = kinds[e.x] == "track" or kinds[e.y] == "track"
		var l := a.distance_to(b)
		var w := rng.randf_range(8.0, 10.0)
		if to_track or l > 140.0:
			w = 11.0
		# gently curved (a quadratic Bézier), less so where the street meets the race route
		var bend := rng.randf_range(-0.11, 0.11) * (0.5 if to_track else 1.0)
		var dir := (b - a) / l
		var ctrl := (a + b) * 0.5 + Vector2(-dir.y, dir.x) * l * bend
		var pts := PackedVector2Array()
		var n := maxi(int(l / 4.0), 2)
		for k in n + 1:
			var t := float(k) / n
			pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
		var s := {"pts": pts, "w": w, "kind": "feeder" if to_track else "street"}
		streets.append(s)
		for ni in [e.x, e.y]:
			if kinds[ni] == "track":
				var j: Dictionary = (g["jn"][ni] as Dictionary).duplicate()
				j["w"] = w
				j["street"] = streets.size() - 1
				junctions.append(j)
	# the ring road along the edge of the area (rounded corners), joining all clipped streets
	var r := area.grow(-10.0)
	var rad := 55.0
	var ring := PackedVector2Array()
	var corners := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
	for c in corners:
		for k in 9:
			var a: float = float(c[1]) + PI * 0.5 * k / 8.0
			ring.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	var dense := PackedVector2Array()
	for k in ring.size():
		var a := ring[k]
		var b := ring[(k + 1) % ring.size()]
		var m := maxi(int(a.distance_to(b) / 4.0), 1)
		for j in m:
			dense.append(a.lerp(b, float(j) / m))
	dense.append(dense[0])
	streets.append({"pts": dense, "w": 12.0, "kind": "ring"})


func _raster_street(k: int) -> void:
	var s: Dictionary = streets[k]
	var pts: PackedVector2Array = s["pts"]
	var hw: float = float(s["w"]) * 0.5
	for j in pts.size() - 1:
		var a := pts[j]
		var b := pts[j + 1]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (hw + SIDEWALK)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (hw + SIDEWALK)
		var c0 := cell_of(lo)
		var c1 := cell_of(hi)
		for iz in range(maxi(c0.y, 0), mini(c1.y + 1, nz)):
			for ix in range(maxi(c0.x, 0), mini(c1.x + 1, nx)):
				var p := area.position + Vector2((ix + 0.5) * CELL, (iz + 0.5) * CELL)
				var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
				var i := iz * nx + ix
				if d <= hw:
					if owner[i] == -3:
						continue          # the race route's own road
					grid[i] = ROAD
					owner[i] = k if owner[i] < 0 or owner[i] == k else -2
				elif d <= hw + SIDEWALK and grid[i] == FREE:
					grid[i] = WALK


## The scramble crossing: a straight cross street on both sides of the start avenue, out to the
## first street it meets.
func _crossing_streets() -> void:
	var i: int = track.index_at(crossing_progress)
	var s: Vector3 = track.samples[i]
	var r: Vector3 = track.rights[i]
	for side: float in [-1.0, 1.0]:
		var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
		var a := Vector2(s.x + r.x * side * (off + 0.3), s.z + r.z * side * (off + 0.3))
		var dir := Vector2(r.x, r.z).normalized() * side
		var pts := PackedVector2Array([a])
		var p := a
		var hit := false
		for k in 90:
			p += dir * 2.0
			var v := value_at(p)
			pts.append(p)
			if v == ROAD and owner_at(p) >= 0 and k > 8:
				hit = true
				break
			if not area.grow(-12.0).has_point(p):
				break
		if pts.size() < 6:
			continue
		var dense := PackedVector2Array()
		for k in range(0, pts.size(), 2):
			dense.append(pts[k])
		if dense[dense.size() - 1] != pts[pts.size() - 1]:
			dense.append(pts[pts.size() - 1])
		streets.append({"pts": dense, "w": 16.0, "kind": "crossing"})
		_raster_street(streets.size() - 1)
		junctions.append({"progress": crossing_progress, "side": side, "pos": a, "index": i, "w": 16.0, "street": streets.size() - 1})
		hit = hit


# ---------------------------------------------------------------------------
# Queries (also for a free roam mode)
# ---------------------------------------------------------------------------
## [street index, closest point, distance, tangent] of the street nearest to p.
func nearest_street(p: Vector2) -> Array:
	var best := [-1, Vector2.ZERO, 1e9, Vector2.RIGHT]
	for k in streets.size():
		var pts: PackedVector2Array = streets[k]["pts"]
		for j in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
			var d := q.distance_to(p)
			if d < float(best[2]):
				best = [k, q, d, (pts[j + 1] - pts[j]).normalized()]
	return best


## Start transforms on the streets (right-hand lane), e.g. for free roam spawns.
func spawn_points(count: int) -> Array:
	var out: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for k in count:
		var s: Dictionary = streets[r.randi() % streets.size()]
		var pts: PackedVector2Array = s["pts"]
		var j := r.randi_range(1, maxi(pts.size() - 3, 1))
		var t := (pts[j + 1] - pts[j]).normalized()
		var p := pts[j] + Vector2(-t.y, t.x) * float(s["w"]) * 0.25
		var fwd := Vector3(t.x, 0, t.y)
		out.append(Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(p.x, 0.6, p.y)))
	return out
