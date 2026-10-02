extends Node3D
## Traffic on every street of Neo Tokyo. A lane graph is built from the street network (street_net.gd):
## two lanes per street, cars keep left as in Japan; at every junction connector curves join each
## incoming lane to the outgoing ones. Cars follow each other, slow down for the turns, wait at a
## junction while something crosses their way (whoever waited longest goes first), pick a random
## way at each junction and turn round where a street ends at the race route (closed in race mode).
## They brake for the players too, pull away and brake smoothly (the acceleration eases in), drive at
## the speed chosen in the menu, and when a player knocks one aside it carries on from where it ended
## up and steers back into its lane. Moved every frame (cars beyond drawing range less often) and
## drawn by traffic_cars.gd.

const DENSITY := [0.0, 5.0, 9.0, 14.0, 20.0]     # cars per km of street, both directions
const MAX_CARS := 560
const LANE_Y := 0.03
const ACC := 2.0
const DEC := 4.5
const DEC_MAX := 7.5
const JERK := 5.0
const LAT_ACC := 2.6
const LAT_W := 1.3               # back into the lane after a knock: spring rate
const NEAR := 520.0              # beyond drawing range: updated every 4th frame only
const SEG_CELL := 32.0
const ID_BASE := 100000          # car ids for traffic_cars.gd (the route traffic's start at 0)
const BASE_KMH := 50.0           # the street speeds below are for this menu setting

class Path:
	var pts := PackedVector3Array()
	var cum := PackedFloat32Array()
	var length := 0.0
	var cars: Array = []          # front-most first
	var next: Array = []          # lanes: connector ids; connectors: [lane id]
	var vmax := 12.0
	var conn := false
	var conflicts: Array = []     # connectors: crossing connectors of the same junction
	var siblings: Array = []      # connectors: the others leaving the same lane (same start)
	var waiting := -1.0           # connectors: since when a car waits for it (-1 nobody)
	var reserved = null           # connectors: the car that has committed to it
	var reverse := -1             # lanes: the same street's other lane
	var crossings: Array = []     # lanes: [arc length here, other lane, arc length there] where lanes cross outside a junction

class Car:
	var path := 0
	var s := 0.0
	var v := 0.0
	var want := 10.0
	var next := -1
	var model := 0
	var paint := Color.WHITE
	var half := 2.2
	var odo := 0.0
	var brake := false
	var xf := Transform3D.IDENTITY
	var acc := 0.0
	var id := 0
	var a := 0.0                  # acceleration (eases towards what's needed)
	var lat := 0.0                # off the lane after a knock (m, + right)
	var lat_v := 0.0
	var shaken := 0.0

var world
var render
var paths: Array = []
var cars: Array = []
var stats := {}
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _frame := 0
var _players: Array = []        # [position, velocity]
var _speed_k := 1.0             # menu speed against BASE_KMH


func setup(p_world, net, level: int, p_render, speed_kmh := BASE_KMH) -> void:
	world = p_world
	render = p_render
	_rng.seed = 7171
	_speed_k = speed_kmh / BASE_KMH
	if render == null or not render.ok or level <= 0:
		return
	var t0 := Time.get_ticks_msec()
	var km := _build(net)
	var count := mini(int(km * float(DENSITY[clampi(level, 0, DENSITY.size() - 1)])), MAX_CARS)
	_spawn(count)
	stats["build_ms"] = Time.get_ticks_msec() - t0
	stats["cars"] = cars.size()
	stats["street_km"] = snappedf(km, 0.1)
	print("CITY TRAFFIC: %s" % str(stats))


# ---------------------------------------------------------------------------
# Lane graph
# ---------------------------------------------------------------------------
## Builds lanes and connectors; returns the street length in km.
func _build(net) -> float:
	var streets: Array = net.streets
	var cums: Array = []
	var seg_grid := {}
	for k in streets.size():
		var pts: PackedVector2Array = streets[k]["pts"]
		var cum := PackedFloat32Array([0.0])
		for j in range(1, pts.size()):
			cum.append(cum[j - 1] + pts[j - 1].distance_to(pts[j]))
			var lo := Vector2(minf(pts[j - 1].x, pts[j].x), minf(pts[j - 1].y, pts[j].y))
			var hi := Vector2(maxf(pts[j - 1].x, pts[j].x), maxf(pts[j - 1].y, pts[j].y))
			for gz in range(int(floor(lo.y / SEG_CELL)), int(floor(hi.y / SEG_CELL)) + 1):
				for gx in range(int(floor(lo.x / SEG_CELL)), int(floor(hi.x / SEG_CELL)) + 1):
					var key := Vector2i(gx, gz)
					if not seg_grid.has(key):
						seg_grid[key] = []
					seg_grid[key].append(Vector2i(k, j - 1))
		cums.append(cum)
	# --- junctions: street ends that meet, ends that run into another street (T), dead ends
	var ends: Array = []          # [street, 0 start / 1 end, position]
	for k in streets.size():
		if streets[k]["kind"] == "ring":
			continue
		var pts: PackedVector2Array = streets[k]["pts"]
		ends.append([k, 0, pts[0]])
		ends.append([k, 1, pts[pts.size() - 1]])
	var route_ends: Array = []
	for j in net.junctions:
		route_ends.append(j["pos"])
	var nodes: Array = []         # Vector2
	var dead := {}                # node id -> true for the turning places at dead ends
	var end_node := {}            # Vector2i(street, 0/1) -> node id
	var splits := {}              # street -> [[arc length, node id]]
	for a in ends.size():
		var e: Array = ends[a]
		var key := Vector2i(e[0], e[1])
		if end_node.has(key):
			continue
		var p: Vector2 = e[2]
		var group: Array = [e]
		for b in range(a + 1, ends.size()):
			var e2: Array = ends[b]
			if not end_node.has(Vector2i(e2[0], e2[1])) and (e2[2] as Vector2).distance_to(p) < 4.0:
				group.append(e2)
		if group.size() >= 2:
			var c := Vector2.ZERO
			for g in group:
				c += g[2]
			c /= group.size()
			nodes.append(c)
			var gid := nodes.size() - 1
			for g in group:
				end_node[Vector2i(g[0], g[1])] = gid
			# the streets may meet right on another one (the ring road): a junction on that one too
			var members: Array = []
			for g in group:
				members.append(int(g[0]))
			var on := _closest_street(streets, cums, seg_grid, c, members)
			if on[0] >= 0 and float(on[2]) < float(streets[on[0]]["w"]) * 0.5 + 3.0:
				if not splits.has(on[0]):
					splits[on[0]] = []
				splits[on[0]].append([on[1], gid])
			continue
		var at_route := false
		for rp in route_ends:
			if (rp as Vector2).distance_to(p) < 3.0:
				at_route = true
		if not at_route:
			# runs into another street: a T-junction on it
			var best := _closest_street(streets, cums, seg_grid, p, [int(e[0])])
			if best[0] >= 0 and float(best[2]) < float(streets[best[0]]["w"]) * 0.5 + 8.0:
				var id := -1
				for sp in splits.get(best[0], []):
					if absf(float(sp[0]) - float(best[1])) < 8.0:
						id = sp[1]
				if id < 0:
					nodes.append(best[3])
					id = nodes.size() - 1
					if not splits.has(best[0]):
						splits[best[0]] = []
					splits[best[0]].append([best[1], id])
				end_node[key] = id
				continue
		# dead end (at the race route: turn round before the barriers)
		nodes.append(p)
		dead[nodes.size() - 1] = 16.0 if at_route else 6.0
		end_node[key] = nodes.size() - 1
	# --- street pieces between junctions
	var pieces: Array = []        # [centre PackedVector2Array, width, kind, node a, node b]
	var km := 0.0
	for k in streets.size():
		var st: Dictionary = streets[k]
		var pts: PackedVector2Array = st["pts"]
		var cum: PackedFloat32Array = cums[k]
		var L: float = cum[cum.size() - 1]
		km += L / 1000.0
		var cuts: Array = splits.get(k, [])
		cuts.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		if st["kind"] == "ring":
			if cuts.is_empty():
				continue
			for c in cuts.size():
				var s0: float = cuts[c][0]
				var s1: float = cuts[(c + 1) % cuts.size()][0]
				if s1 <= s0:
					s1 += L
				pieces.append([_sub(pts, cum, s0, s1, true), float(st["w"]), st["kind"], cuts[c][1], cuts[(c + 1) % cuts.size()][1]])
		else:
			var marks: Array = [[0.0, end_node[Vector2i(k, 0)]]]
			marks.append_array(cuts)
			marks.append([L, end_node[Vector2i(k, 1)]])
			for c in marks.size() - 1:
				if float(marks[c + 1][0]) - float(marks[c][0]) < 1.0:
					continue
				pieces.append([_sub(pts, cum, marks[c][0], marks[c + 1][0], false), float(st["w"]), st["kind"], marks[c][1], marks[c + 1][1]])
	# junction size: the widest street there
	var radius := {}
	for pc in pieces:
		for ni in [pc[3], pc[4]]:
			# cars wait this far back: clear of the curves of the other lanes through the junction
			radius[ni] = maxf(float(radius.get(ni, 6.5)), float(pc[1]) * 0.5 + 3.0)
	# --- lanes
	var lanes_in := {}
	var lanes_out := {}
	for pc in pieces:
		var centre: PackedVector2Array = pc[0]
		var w: float = pc[1]
		var kind: String = pc[2]
		# the menu's speed on the main streets, a little less on the narrow ones (bends: slower)
		var vmax := BASE_KMH / 3.6 * _speed_k * (1.0 if kind == "ring" or kind == "feeder" or w >= 10.0 else 0.8)
		var ids: Array = []
		for dir in 2:
			var c := centre.duplicate()
			var na: int = pc[3]
			var nb: int = pc[4]
			if dir == 1:
				c.reverse()
				na = pc[4]
				nb = pc[3]
			var t0: float = dead.get(na, radius.get(na, 5.0))
			var t1: float = dead.get(nb, radius.get(nb, 5.0))
			var lane := Path.new()
			lane.pts = _offset_cut(c, w * 0.25, t0, t1)
			if lane.pts.size() < 2:
				ids.append(-1)
				continue
			_measure(lane)
			lane.vmax = minf(vmax, _curve_speed(lane))
			paths.append(lane)
			var id := paths.size() - 1
			ids.append(id)
			if not lanes_out.has(na):
				lanes_out[na] = []
			lanes_out[na].append(id)
			if not lanes_in.has(nb):
				lanes_in[nb] = []
			lanes_in[nb].append(id)
		if ids[0] >= 0 and ids[1] >= 0:
			(paths[ids[0]] as Path).reverse = ids[1]
			(paths[ids[1]] as Path).reverse = ids[0]
	# --- connectors through every junction
	var n_conn := 0
	for ni in lanes_in:
		var outs: Array = lanes_out.get(ni, [])
		var made: Array = []
		for li in lanes_in[ni]:
			var lin: Path = paths[li]
			var opts: Array = []
			for lo in outs:
				if lo != lin.reverse or dead.has(ni):
					opts.append(lo)
			if opts.is_empty() and lin.reverse >= 0 and outs.has(lin.reverse):
				opts.append(lin.reverse)
			for lo in opts:
				var cn := _connector(lin, paths[lo])
				cn.next = [lo]
				paths.append(cn)
				var cid := paths.size() - 1
				lin.next.append(cid)
				made.append([cid, li])
				n_conn += 1
		# connectors leaving the same lane start at the same point
		for x in made.size():
			for y in made.size():
				if x != y and made[x][1] == made[y][1]:
					(paths[made[x][0]] as Path).siblings.append(made[y][0])
		# which connectors cross each other
		for x in made.size():
			for y in range(x + 1, made.size()):
				if made[x][1] == made[y][1]:
					continue
				var cx: Path = paths[made[x][0]]
				var cy: Path = paths[made[y][0]]
				if _crosses(cx, cy):
					cx.conflicts.append(made[y][0])
					cy.conflicts.append(made[x][0])
	_find_crossings()
	stats["junctions"] = nodes.size()
	stats["lanes"] = paths.size() - n_conn
	stats["connectors"] = n_conn
	return km


## Lanes that cross each other away from any junction (streets drawn across one another): the cars
## there give way to whoever is nearer the crossing.
func _find_crossings() -> void:
	var grid := {}
	for li in paths.size():
		var p: Path = paths[li]
		if p.conn:
			continue
		for j in p.pts.size() - 1:
			var a := p.pts[j]
			var key := Vector2i(int(floor(a.x / 16.0)), int(floor(a.z / 16.0)))
			if not grid.has(key):
				grid[key] = []
			grid[key].append(Vector2i(li, j))
	var seen := {}
	for key in grid:
		var segs: Array = []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				segs.append_array(grid.get(key + Vector2i(dx, dz), []))
		for x in (grid[key] as Array):
			for y in segs:
				if x.x >= y.x or y.x == (paths[x.x] as Path).reverse:
					continue
				var pa: Path = paths[x.x]
				var pb: Path = paths[y.x]
				var a0 := Vector2(pa.pts[x.y].x, pa.pts[x.y].z)
				var a1 := Vector2(pa.pts[x.y + 1].x, pa.pts[x.y + 1].z)
				var b0 := Vector2(pb.pts[y.y].x, pb.pts[y.y].z)
				var b1 := Vector2(pb.pts[y.y + 1].x, pb.pts[y.y + 1].z)
				var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
				if hit == null:
					continue
				var tag := Vector2i(x.x, y.x)
				if seen.has(tag):
					continue
				seen[tag] = true
				var sa: float = pa.cum[x.y] + a0.distance_to(hit)
				var sb: float = pb.cum[y.y] + b0.distance_to(hit)
				pa.crossings.append([sa, y.x, sb])
				pb.crossings.append([sb, x.x, sa])
	stats["crossings"] = seen.size()


## The part of a polyline between arc lengths s0 and s1 (wrapping round for a closed ring).
static func _sub(pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float, ring: bool) -> PackedVector2Array:
	var L: float = cum[cum.size() - 1]
	var out := PackedVector2Array()
	out.append(_at2(pts, cum, fposmod(s0, L) if ring else s0))
	for j in pts.size():
		var s: float = cum[j]
		for lap in ([0.0, L] if ring else [0.0]):
			var sj: float = s + float(lap)
			if sj > s0 + 0.5 and sj < s1 - 0.5:
				out.append(pts[j])
	out.append(_at2(pts, cum, fposmod(s1, L) if ring else s1))
	return out


static func _at2(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var i := clampi(cum.bsearch(s), 1, cum.size() - 1)
	var l := cum[i] - cum[i - 1]
	return pts[i - 1].lerp(pts[i], clampf((s - cum[i - 1]) / maxf(l, 0.001), 0.0, 1.0))


## Nearest point on any street but those in `skip`: [street, arc length, distance, point].
static func _closest_street(streets: Array, cums: Array, seg_grid: Dictionary, p: Vector2, skip: Array) -> Array:
	var best := [-1, 0.0, 1e9, p]
	var c := Vector2i(int(floor(p.x / SEG_CELL)), int(floor(p.y / SEG_CELL)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for sg in seg_grid.get(c + Vector2i(dx, dz), []):
				if skip.has(sg.x):
					continue
				var pts: PackedVector2Array = streets[sg.x]["pts"]
				var a := pts[sg.y]
				var b := pts[sg.y + 1]
				var q := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := q.distance_to(p)
				if d < float(best[2]):
					var cum: PackedFloat32Array = cums[sg.x]
					best = [sg.x, cum[sg.y] + a.distance_to(q), d, q]
	return best


## A lane: the centre line shifted `off` to the left of the direction of travel, cut t0 metres after
## its start and t1 before its end (the junctions).
static func _offset_cut(c: PackedVector2Array, off: float, t0: float, t1: float) -> PackedVector3Array:
	var cum := PackedFloat32Array([0.0])
	for j in range(1, c.size()):
		cum.append(cum[j - 1] + c[j - 1].distance_to(c[j]))
	var L: float = cum[cum.size() - 1]
	if L - t0 - t1 < 3.0:
		var sh := maxf((L - 3.0) * 0.5, 0.3)
		t0 = minf(t0, sh)
		t1 = minf(t1, sh)
	var s0 := t0
	var s1 := L - t1
	var mid := PackedVector2Array()
	mid.append(_at2(c, cum, s0))
	for j in c.size():
		if cum[j] > s0 + 0.5 and cum[j] < s1 - 0.5:
			mid.append(c[j])
	mid.append(_at2(c, cum, s1))
	var out := PackedVector3Array()
	for j in mid.size():
		var a := mid[maxi(j - 1, 0)]
		var b := mid[mini(j + 1, mid.size() - 1)]
		var t := (b - a).normalized()
		var left := Vector2(t.y, -t.x)
		var q := mid[j] + left * off
		out.append(Vector3(q.x, LANE_Y, q.y))
	return out


static func _measure(p: Path) -> void:
	p.cum = PackedFloat32Array([0.0])
	for j in range(1, p.pts.size()):
		p.cum.append(p.cum[j - 1] + p.pts[j - 1].distance_to(p.pts[j]))
	p.length = maxf(p.cum[p.cum.size() - 1], 0.01)


## The speed the sharpest bend of a path allows.
static func _curve_speed(p: Path) -> float:
	var kmax := 0.0
	for j in range(1, p.pts.size() - 1):
		var a := p.pts[j] - p.pts[j - 1]
		var b := p.pts[j + 1] - p.pts[j]
		var l := (a.length() + b.length()) * 0.5
		if l < 0.05:
			continue
		var ang := Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))
		kmax = maxf(kmax, absf(ang) / l)
	return 30.0 if kmax < 1e-4 else clampf(sqrt(LAT_ACC / kmax), 2.5, 30.0)


## A curve from the end of one lane to the start of another (a cubic Bézier, tangent to both).
func _connector(a: Path, b: Path) -> Path:
	var p0: Vector3 = a.pts[a.pts.size() - 1]
	var d0: Vector3 = (p0 - a.pts[a.pts.size() - 2]).normalized()
	var p3: Vector3 = b.pts[0]
	var d3: Vector3 = (b.pts[1] - p3).normalized()
	var k := clampf(p0.distance_to(p3) * 0.45, 2.0, 12.0)
	if d0.dot(d3) < -0.7:
		k = 6.0             # turning round
	var p1 := p0 + d0 * k
	var p2 := p3 - d3 * k
	var c := Path.new()
	c.conn = true
	var n := 10
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		c.pts.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))
	_measure(c)
	c.vmax = _curve_speed(c)
	return c


## Do two connectors come closer than a car's width anywhere?
static func _crosses(a: Path, b: Path) -> bool:
	for p in a.pts:
		for q in b.pts:
			if Vector2(p.x - q.x, p.z - q.z).length_squared() < 2.5 * 2.5:
				return true
	return false


# ---------------------------------------------------------------------------
# Cars
# ---------------------------------------------------------------------------
func _spawn(count: int) -> void:
	var lanes: Array = []
	var total := 0.0
	for i in paths.size():
		var p: Path = paths[i]
		if not p.conn and not p.next.is_empty() and p.length > 12.0:
			lanes.append(i)
			total += p.length
	if lanes.is_empty():
		return
	var tries := 0
	while cars.size() < count and tries < count * 6:
		tries += 1
		var r := _rng.randf() * total
		var li: int = lanes[0]
		for i in lanes:
			r -= (paths[i] as Path).length
			if r <= 0.0:
				li = i
				break
		var lane: Path = paths[li]
		var s := _rng.randf_range(3.0, lane.length - 3.0)
		var free := true
		for o in lane.cars:
			if absf((o as Car).s - s) < 12.0:
				free = false
				break
		if not free:
			continue
		var c := Car.new()
		var pick: Array = render.pick(_rng)
		c.id = cars.size()
		c.model = pick[0]
		c.paint = pick[1]
		c.half = render.half_length(c.model)
		c.path = li
		c.s = s
		c.want = lane.vmax * _rng.randf_range(0.97, 1.05)
		c.v = c.want * 0.7
		c.odo = _rng.randf() * 100.0
		c.next = _choose(lane)
		# keep the lane's list ordered front-most first
		var at := lane.cars.size()
		for k in lane.cars.size():
			if (lane.cars[k] as Car).s < s:
				at = k
				break
		lane.cars.insert(at, c)
		c.xf = _xf(lane, s)
		cars.append(c)


func _choose(p: Path) -> int:
	if p.next.is_empty():
		return -1
	return p.next[_rng.randi() % p.next.size()]


func _process(delta: float) -> void:
	if cars.is_empty():
		return
	delta = minf(delta, 0.1)
	_time += delta
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	_players.clear()
	for car in world.cars.values():
		if is_instance_valid(car) and car.visible:
			_players.append([car.global_position, (car as RigidBody3D).linear_velocity])
	var near2 := NEAR * NEAR
	for c: Car in cars:
		c.acc += delta
		if c.xf.origin.distance_squared_to(cp) > near2 and (_frame + c.id) % 4 != 0:
			continue
		var dt := c.acc
		c.acc = 0.0
		_step(c, dt)
	for c: Car in cars:
		render.add(c.model, c.xf, c.paint, c.odo, c.brake, c.v, ID_BASE + c.id)


func _step(c: Car, dt: float) -> void:
	var p: Path = paths[c.path]
	# knocked by a player: carry on from where it ended up (along the lane; across it the spring
	# below steers it back), and wait a moment
	if render.hit(ID_BASE + c.id):
		c.v *= 0.5
		c.a = minf(c.a, 0.0)
		c.shaken = 1.2
	var e: Vector3 = render.disturbance(ID_BASE + c.id)
	if e != Vector3.ZERO:
		# loose: its place along the lane is where the body is (it steers itself back onto it)
		c.s = maxf(c.s + e.x, 0.0)
	var want := minf(c.want, p.vmax)
	var rem := p.length - c.s
	# the car in front (on this path, or the first one on the next)
	var gap := 1e9
	var lv := 0.0
	var i := p.cars.find(c)
	if i > 0:
		var l: Car = p.cars[i - 1]
		gap = l.s - c.s - l.half - c.half
		lv = l.v
	elif c.next >= 0:
		var q: Path = paths[c.next]
		if not q.cars.is_empty():
			var l: Car = q.cars.back()
			gap = rem + l.s - l.half - c.half
			lv = l.v
		elif q.conn:
			var q2: Path = paths[q.next[0]]
			if not q2.cars.is_empty():
				var l: Car = q2.cars.back()
				gap = rem + q.length + l.s - l.half - c.half
				lv = l.v
		# a car that just turned off another way is still right in front at first
		for sb in q.siblings:
			var sp: Path = paths[sb]
			if not sp.cars.is_empty():
				var l: Car = sp.cars.back()
				var g := rem + l.s - l.half - c.half
				if g < gap:
					gap = g
					lv = l.v
	if gap < 60.0:
		var g0 := 2.5 + c.v * 1.1
		if gap < g0:
			want = minf(want, lv * clampf((gap - 1.0) / (g0 - 1.0), 0.0, 1.0))
		want = minf(want, sqrt(maxf(lv * lv + 2.0 * DEC * (gap - 2.0), 0.0)))
	# the junction ahead: slow down for the turn, stop at the line unless it's ours to cross
	if not p.conn and c.next >= 0:
		var q: Path = paths[c.next]
		want = minf(want, sqrt(q.vmax * q.vmax + 2.0 * DEC * maxf(rem - 1.0, 0.0)))
		if q.reserved != c:
			if rem < c.v * c.v / (2.0 * DEC) + 10.0 and _may_enter(q, c):
				q.reserved = c
			else:
				want = minf(want, sqrt(2.0 * DEC * maxf(rem - 0.8, 0.0)))
				if c.v < 0.6 and rem < 10.0 and q.waiting < 0.0:
					q.waiting = _time
	# a crossing outside a junction: give way to a car nearer to it
	for cr in p.crossings:
		var d: float = float(cr[0]) - c.s
		if d < -c.half or d > 14.0:
			continue
		var other: Path = paths[cr[1]]
		for oc: Car in other.cars:
			var od: float = float(cr[2]) - oc.s
			if od > -oc.half - 1.0 and od < 9.0 and (od < d or (absf(od - d) < 0.5 and oc.id < c.id)):
				want = minf(want, sqrt(2.0 * DEC * maxf(d - c.half - 3.0, 0.0)))
				break
	# players and bots in the way
	if not _players.is_empty():
		var fwd := -c.xf.basis.z
		var side := c.xf.basis.x
		for pl in _players:
			var rel: Vector3 = (pl[0] as Vector3) - c.xf.origin
			if rel.length_squared() > 3600.0:
				continue
			var along := rel.dot(fwd)
			if along < 0.0 or along > 40.0 or absf(rel.dot(side)) > 2.4:
				continue
			var pv := maxf((pl[1] as Vector3).dot(fwd), 0.0)
			var g := along - c.half - 2.4
			want = minf(want, sqrt(maxf(pv * pv + 2.0 * DEC * (g - 1.5), 0.0)))
	if c.shaken > 0.0:
		c.shaken -= dt
		want = 0.0 if c.shaken > 0.6 else minf(want, 2.5)
	# pulling away eases in (no jolts); braking comes almost at once (it has to stop at the line)
	var a_want := clampf((want - c.v) * 1.6, -DEC_MAX, ACC)
	var rate := JERK * 8.0 if a_want < c.a else JERK
	c.a = move_toward(c.a, a_want, rate * dt)
	var nv := maxf(c.v + c.a * dt, 0.0)
	if nv <= 0.0:
		c.a = maxf(c.a, 0.0)
	c.brake = c.a < -0.6 or nv < 0.3
	c.v = nv
	c.s += nv * dt
	c.odo += nv * dt
	# never into the one in front on the same lane
	var me := p.cars.find(c)
	if me > 0:
		var ld: Car = p.cars[me - 1]
		var lim := ld.s - ld.half - c.half - 0.4
		if c.s > lim:
			c.s = maxf(lim, c.s - nv * dt)
			c.v = minf(c.v, ld.v)
	# back into the lane (a damped spring)
	if c.lat != 0.0 or c.lat_v != 0.0:
		c.lat_v += (-c.lat * LAT_W * LAT_W - 2.0 * LAT_W * c.lat_v) * dt
		c.lat += c.lat_v * dt
		if absf(c.lat) < 0.01 and absf(c.lat_v) < 0.01:
			c.lat = 0.0
			c.lat_v = 0.0
	# on to the next path
	while c.s >= p.length:
		if c.next < 0:
			c.s = p.length
			c.v = 0.0
			break
		var q: Path = paths[c.next]
		if q.conn and q.reserved != c and not _may_enter(q, c):
			c.s = p.length - 0.01
			var me2 := p.cars.find(c)
			if me2 > 0:
				var ld2: Car = p.cars[me2 - 1]
				c.s = minf(c.s, ld2.s - ld2.half - c.half - 0.4)
			c.v = 0.0
			break
		c.s -= p.length
		p.cars.erase(c)
		q.cars.append(c)
		if q.conn:
			q.reserved = null
			q.waiting = -1.0
		c.path = c.next
		p = q
		c.next = _choose(q)
	c.xf = _xf(p, c.s)
	if c.lat != 0.0:
		var f := -c.xf.basis.z
		c.xf.origin += Vector3(-f.z, 0, f.x).normalized() * c.lat


## May a car take connector q now? Nothing on (or committed to) a crossing connector, nobody there
## waiting clearly longer, room on the lane behind it.
func _may_enter(q: Path, c: Car) -> bool:
	for o in q.conflicts:
		var oc: Path = paths[o]
		if not oc.cars.is_empty() or (oc.reserved != null and oc.reserved != c):
			return false
	var mine := q.waiting if q.waiting >= 0.0 else _time
	for o in q.conflicts:
		var w: float = (paths[o] as Path).waiting
		if w >= 0.0 and w < mine - 0.5 and _time - w > 1.5:
			return false
	var out: Path = paths[q.next[0]]
	if not out.cars.is_empty():
		var last: Car = out.cars.back()
		if last.s < last.half + c.half + 3.0:
			return false
	if not q.cars.is_empty():
		var last: Car = q.cars.back()
		if last.s < last.half + c.half + 2.0:
			return false
	for sb in q.siblings:
		var sp: Path = paths[sb]
		if not sp.cars.is_empty():
			var last: Car = sp.cars.back()
			if last.s < last.half + c.half + 2.0:
				return false
	return true


func _xf(p: Path, s: float) -> Transform3D:
	var pos := _point(p, s)
	var a := _point(p, s - 1.6)
	var b := _point(p, s + 1.6)
	var fwd := b - a
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos)


static func _point(p: Path, s: float) -> Vector3:
	s = clampf(s, 0.0, p.length)
	var i := clampi(p.cum.bsearch(s), 1, p.cum.size() - 1)
	var l := p.cum[i] - p.cum[i - 1]
	return p.pts[i - 1].lerp(p.pts[i], clampf((s - p.cum[i - 1]) / maxf(l, 0.001), 0.0, 1.0))
