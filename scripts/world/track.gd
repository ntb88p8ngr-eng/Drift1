extends Node3D
## Builds a closed circuit from control points: road ribbon, curbs, walls, start gantry and ground.
## Also answers spatial queries (progress along the lap, surface type, respawn points).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const SPACING := 2.0
const SHOULDER := 1.8      # mean width of the gravel shoulder from the road edge (m)
const ROAD_Y := 0.03
const WALL_HEIGHT := 1.15
const CELL := 20.0

const DEFS := {
	"ridge": {
		"points": [Vector2(0, 0), Vector2(0, -150), Vector2(20, -240), Vector2(90, -290), Vector2(170, -270),
			Vector2(210, -200), Vector2(200, -120), Vector2(240, -60), Vector2(320, -50), Vector2(370, -100),
			Vector2(380, -190), Vector2(430, -250), Vector2(500, -240), Vector2(530, -160), Vector2(510, -40),
			Vector2(450, 40), Vector2(380, 90), Vector2(290, 100), Vector2(220, 150), Vector2(150, 160),
			Vector2(80, 120), Vector2(20, 60)],
		"width": 15.0, "runoff": 5.0, "start_dist": 70.0,
		"ground": "grass", "offroad_grip": 0.62, "wall": "armco", "asphalt": Color(0.10, 0.10, 0.11),
	},
	"playground": {
		"points": [Vector2(0, 0), Vector2(45, -44), Vector2(83, -62), Vector2(109, -44), Vector2(118, 0), Vector2(109, 44),
			Vector2(83, 62), Vector2(45, 44), Vector2(0, 0), Vector2(-45, -44), Vector2(-83, -62), Vector2(-109, -44),
			Vector2(-118, 0), Vector2(-109, 44), Vector2(-83, 62), Vector2(-45, 44)],
		"width": 16.0, "runoff": 6.0, "start_dist": 40.0,
		"ground": "asphalt", "offroad_grip": 0.97, "wall": "none", "asphalt": Color(0.075, 0.075, 0.085),
	},
	"harbor": {
		"points": [Vector2(0, 0), Vector2(0, -120), Vector2(30, -170), Vector2(90, -175), Vector2(120, -130),
			Vector2(110, -70), Vector2(150, -30), Vector2(220, -40), Vector2(250, -100), Vector2(300, -130),
			Vector2(360, -110), Vector2(370, -40), Vector2(330, 20), Vector2(260, 60), Vector2(250, 120),
			Vector2(200, 160), Vector2(130, 150), Vector2(80, 100), Vector2(20, 70)],
		"width": 18.0, "runoff": 3.0, "start_dist": 60.0,
		"ground": "concrete", "offroad_grip": 0.85, "wall": "concrete", "asphalt": Color(0.085, 0.085, 0.095),
	},
	# Japanese city: avenues with the Shibuya-style scramble crossing, tight 90° corners between the
	# blocks and an elevated expressway loop (up to 10 m, ramps of 5 %) – points [x, z, height]
	"tokyo": {
		"points": [Vector2(0, 0), Vector2(0, -120), Vector2(0, -230), Vector2(10, -275), Vector2(55, -290), Vector2(200, -290),
			Vector2(245, -300), Vector2(260, -340), Vector2(260, -420), Vector2(275, -460), Vector2(320, -475), Vector2(420, -475),
			Vector2(540, -470), Vector2(640, -440), Vector2(710, -370), Vector2(740, -270), Vector2(735, -160), Vector2(700, -70),
			Vector2(630, -10), Vector2(540, 20), Vector2(440, 30), Vector2(360, 35), Vector2(300, 40), Vector2(255, 60),
			Vector2(240, 100), Vector2(240, 180), Vector2(225, 220), Vector2(185, 235), Vector2(80, 235), Vector2(40, 220),
			Vector2(25, 185), Vector2(25, 120), Vector2(15, 70), Vector2(0, 30)],
		"heights": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 9, 10, 10, 10, 10, 9, 6, 2.5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"width": 16.0, "runoff": 1.5, "start_dist": 60.0,
		"ground": "concrete", "offroad_grip": 0.85, "wall": "concrete", "asphalt": Color(0.07, 0.07, 0.08),
	},
	# Nordschleife replica: course and heights from real data (tools/make_gruene_hoelle.py)
	"gruene_hoelle": {
		"data": "res://assets/tracks/gruene_hoelle",
		"width": 18.0, "runoff": 4.0, "start_dist": 60.0,
		# [from section, to section, road width]: the Döttinger Höhe twice the old width
		"wide": [["Döttinger Höhe", "Tiergarten", 24.0]],
		# [section, bank angle (deg)]: the Karussell as a steep banked hairpin
		"banked": [["Karussell", 24.0]],
		# [section, reach (samples either side), passes]: the line rounded locally (the map data has a
		# kink at the Karussell entry – the radius jumped from 170 to 31 m within a few metres)
		"smooth": [["Karussell", 80, 40]],
		"ground": "grass", "offroad_grip": 0.62, "wall": "armco", "asphalt": Color(0.095, 0.095, 0.1),
	},
}

var track_id := "ridge"
var def: Dictionary
var width := 15.0
var half_w := 7.5
var wall_base := 12.5

var samples := PackedVector3Array()
var tangents := PackedVector3Array()
var rights := PackedVector3Array()
var dists := PackedFloat32Array()
var curvature := PackedFloat32Array()
## half road width per sample (= half_w except where a track widens, see "wide")
var hws := PackedFloat32Array()
## cross slope per sample: height change per metre towards +rights (banked corners, see "banked")
var bank := PackedFloat32Array()
var off_left := PackedFloat32Array()
var off_right := PackedFloat32Array()
var curb_mask := PackedByteArray()
## gravel trap on the outside of tight corners: weight 0..1, sign = side (+1 = +rights side)
var trap := PackedFloat32Array()
var trap_w := 4.6          # gravel trap width from the road edge (m), inside the run-off
var length := 0.0
var start_index := 0
var start_dist := 0.0
var bounds := Rect2()

var wetness := 0.0          # 0 dry … 1 soaked (set by the weather)
var puddle_level := 0.0     # how far the puddles have filled up
var puddles: Array = []     # {"c": centre, "t": tangent, "r": right, "la": half length, "lc": half width}
var road_material: ShaderMaterial
var gantry_xf := Transform3D.IDENTITY   # start gantry frame (grandstand on its +X side)
var stand_x := 0.0
## tracks built from data (Grüne Hölle) have real heights: samples carry y, the road has its own
## collision and the terrain follows the road instead of the other way round
var elevated := false
## Spline tracks with a height profile (the city's expressway): the road has its own collision, out
## to the walls (a bridge deck), the terrain stays flat underneath.
var raised := false
var meta: Dictionary = {}       # data tracks: meta.json (grid layout, sections, attribution)
var sections: Array = []        # [name, distance from the start line] in driving order
var min_y := 0.0
var max_y := 0.0
var kill_y := -20.0             # below this a car has left the world

var _grid := {}
var _edge: Dictionary = {}
## optional ground override (playground grass islands): func(pos: Vector3) -> [grip, name] or []
var ground_fn: Callable
var _puddle_index := {}     # sample index -> Array of puddle ids
var _start_lights: Array = []
## Openings in the barriers (set before build): [progress from, progress to, side (-1 left, 1 right)]
## in metres from the start line – driveways and forest tracks leave the road there.
var wall_gaps: Array = []
var _lamp_lights: Array = []


func build(id: String) -> void:
	track_id = id if DEFS.has(id) else "ridge"
	def = DEFS[track_id]
	width = def["width"]
	half_w = width * 0.5
	wall_base = half_w + float(def["runoff"])
	trap_w = minf(4.6, float(def["runoff"]) - 0.4)
	elevated = def.has("data")
	raised = def.has("heights")
	# ticks between the steps: the loading screen keeps moving on the long data tracks
	_sample_centerline()
	_setup_profile()
	await Game.load_tick(0.2)
	_compute_offsets()
	_build_grid()
	_build_ground()
	await Game.load_tick(0.35)
	_build_road()
	if elevated or raised:
		_build_road_collision()
	await Game.load_tick(0.55)
	_build_puddles()
	await Game.load_tick(0.7)
	_build_curbs()
	_build_walls()
	await Game.load_tick(0.9)
	_build_start()
	if str(def.get("wall", "")) != "none" or track_id != "playground":
		await _compute_edge(true)


# ---------------------------------------------------------------------------
# Centerline
# ---------------------------------------------------------------------------
static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


func _sample_centerline() -> void:
	if elevated:
		_load_centerline()
	else:
		_spline_centerline()
	var count := samples.size()
	var step := length / float(count)
	tangents.resize(count)
	rights.resize(count)
	curvature.resize(count)
	var flat_t := PackedVector3Array()
	flat_t.resize(count)
	for i in count:
		# tangents follow the slope; rights stay level (the road has no banking), corners are measured
		# on the ground plan
		var t: Vector3 = (samples[(i + 1) % count] - samples[(i - 1 + count) % count]).normalized()
		tangents[i] = t
		flat_t[i] = Vector3(t.x, 0.0, t.z).normalized()
		rights[i] = flat_t[i].cross(Vector3.UP).normalized()
	for i in count:
		var tp: Vector3 = flat_t[(i - 2 + count) % count]
		var tn: Vector3 = flat_t[(i + 2) % count]
		curvature[i] = tp.signed_angle_to(tn, Vector3.UP) / (4.0 * step)
	start_index = int(round(float(def["start_dist"]) / step)) % count
	start_dist = dists[start_index]
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	min_y = 1e9
	max_y = -1e9
	for p in samples:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.z)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.z)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	bounds = Rect2(mn, mx - mn)
	kill_y = min_y - 20.0
	# section names are measured from the first sample, progress from the start line
	sections.clear()
	for sec in meta.get("sections", []):
		sections.append([str(sec[0]), fposmod(float(sec[1]) - start_dist, length)])
	sections.sort_custom(func(a, b): return float(a[1]) < float(b[1]))


## Data track: samples (x, y, z) every SPACING metres, already in driving order.
func _load_centerline() -> void:
	var dir: String = def["data"]
	meta = JSON.parse_string(FileAccess.get_file_as_string(dir + "/meta.json"))
	var raw := FileAccess.get_file_as_bytes(dir + "/centerline.bin").to_float32_array()
	var count := raw.size() / 3
	samples.resize(count)
	dists.resize(count)
	for i in count:
		samples[i] = Vector3(raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2])
		dists[i] = float(i) * SPACING
	length = SPACING * count
	_smooth_sections()


## Rounds the centreline around named sections (def "smooth"): Laplacian passes on x/z whose weight
## fades out towards the ends of the region, so the rest of the lap stays untouched.
func _smooth_sections() -> void:
	var n := samples.size()
	for sdef in def.get("smooth", []):
		var at := -1.0
		for sec in meta.get("sections", []):
			if str(sec[0]) == str(sdef[0]):
				at = float(sec[1])
		if at < 0.0:
			continue
		var c := int(round(at / SPACING)) % n
		var reach: int = int(sdef[1])
		for _p in int(sdef[2]):
			var q := samples.duplicate()
			for d in range(-reach, reach + 1):
				var i := (c + d + n) % n
				var t := absf(float(d)) / reach
				var w := 0.6 * pow(1.0 - t * t, 2.0)
				var avg: Vector3 = (q[(i - 2 + n) % n] + q[(i - 1 + n) % n] + q[(i + 1) % n] + q[(i + 2) % n]) * 0.25
				samples[i] = Vector3(lerpf(q[i].x, avg.x, w), q[i].y, lerpf(q[i].z, avg.z, w))


func _spline_centerline() -> void:
	var pts: Array = []
	var hs: Array = def.get("heights", [])
	for k in def["points"].size():
		var p: Vector2 = def["points"][k]
		pts.append(Vector3(p.x, float(hs[k]) if k < hs.size() else 0.0, p.y))
	var n := pts.size()
	var dense: Array = []
	for i in n:
		for k in 40:
			dense.append(_catmull(pts[(i - 1 + n) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n], float(k) / 40.0))
	# arc-length resample
	var cum: Array = [0.0]
	for i in range(1, dense.size() + 1):
		var a: Vector3 = dense[i - 1]
		var b: Vector3 = dense[i % dense.size()]
		cum.append(float(cum[i - 1]) + a.distance_to(b))
	length = cum[cum.size() - 1]
	var count := int(floor(length / SPACING))
	var step := length / float(count)
	samples.resize(count)
	dists.resize(count)
	var j := 0
	for i in count:
		var d := float(i) * step
		while j < dense.size() - 1 and float(cum[j + 1]) < d:
			j += 1
		var seg_len: float = float(cum[j + 1]) - float(cum[j])
		var t := 0.0 if seg_len <= 0.0 else (d - float(cum[j])) / seg_len
		var a: Vector3 = dense[j]
		var b: Vector3 = dense[(j + 1) % dense.size()]
		samples[i] = a.lerp(b, t)
		dists[i] = d
	length = step * count


## Name of the track section at `progress` metres from the start line ("" on tracks without names).
func section_at(progress: float) -> String:
	if sections.is_empty():
		return ""
	var name: String = sections[sections.size() - 1][0]
	for sec in sections:
		if float(sec[1]) > progress:
			break
		name = sec[0]
	return name


## Road width and banking per sample from the track definition ("wide", "banked").
func _setup_profile() -> void:
	var n := samples.size()
	hws.resize(n)
	hws.fill(half_w)
	bank.resize(n)
	bank.fill(0.0)
	var raw_secs := {}
	for sec in meta.get("sections", []):
		raw_secs[str(sec[0])] = float(sec[1])
	# widened stretches, with 60 m long tapers at both ends
	for wdef in def.get("wide", []):
		if not raw_secs.has(str(wdef[0])) or not raw_secs.has(str(wdef[1])):
			continue
		var d0: float = raw_secs[str(wdef[0])]
		var d1: float = raw_secs[str(wdef[1])]
		var hw2: float = float(wdef[2]) * 0.5
		for i in n:
			var d := dists[i]
			var k := smoothstep(d0 - 30.0, d0 + 30.0, d) * (1.0 - smoothstep(d1 - 30.0, d1 + 30.0, d))
			if k > 0.0:
				hws[i] = maxf(hws[i], lerpf(half_w, hw2, k))
	# banked corners: from the section's anchor out to where the corner opens up (radius > 140 m),
	# the bank rises over 80 m before and falls over 80 m after (smootherstep: no kink in the roll
	# rate when driving in); the outside of the corner is high
	for bdef in def.get("banked", []):
		if not raw_secs.has(str(bdef[0])):
			continue
		var c := int(round(float(raw_secs[str(bdef[0])]) / SPACING)) % n
		# the anchor lies in the tightest part: look for it within 40 m
		var best := c
		for d in range(-20, 21):
			if absf(curvature[(c + d + n) % n]) > absf(curvature[best]):
				best = (c + d + n) % n
		c = best
		var lo := 0
		var hi := 0
		while lo < 150 and absf(_curv_avg(c - lo - 1, 3)) > 1.0 / 140.0:
			lo += 1
		while hi < 150 and absf(_curv_avg(c + hi + 1, 3)) > 1.0 / 140.0:
			hi += 1
		var sgn := signf(_curv_avg(c, 6))
		var slope := tan(deg_to_rad(float(bdef[1]))) * sgn
		var ramp := int(80.0 / SPACING)
		for d in range(-lo - ramp, hi + ramp + 1):
			var k := 1.0
			if d < -lo:
				k = _smootherstep(float(d + lo + ramp) / ramp)
			elif d > hi:
				k = _smootherstep(float(hi + ramp - d) / ramp)
			bank[(c + d + n) % n] = slope * k


static func _smootherstep(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


func _curv_avg(i: int, r: int) -> float:
	var n := samples.size()
	var acc := 0.0
	for d in range(-r, r + 1):
		acc += curvature[(i + d + n) % n]
	return acc / (2 * r + 1)


## Point at `lateral` metres to the right of sample i on the (banked) road plane, without ROAD_Y.
func edge_point(i: int, lateral: float) -> Vector3:
	var p := samples[i] + rights[i] * lateral
	if not bank.is_empty():
		p.y += lateral * bank[i]
	return p


## Height offset of the banked road at `lateral` metres to the right of sample i (0 elsewhere).
func bank_y(i: int, lateral: float) -> float:
	return lateral * bank[i] if not bank.is_empty() else 0.0


## Ground height offset beside a banked road: the road plane carried on to just past the barrier.
func ground_bank_y(i: int, lateral: float) -> float:
	if bank.is_empty() or bank[i] == 0.0:
		return 0.0
	var lim := wall_base + hws[i] - half_w + 1.5
	# a bit lower than the road plane: the 4 m ground grid can't follow the tilted, curved surface
	# exactly and would poke through at the road edges
	return clampf(lateral, -lim, lim) * bank[i] - 0.9 * absf(bank[i])


func max_half_w() -> float:
	var m := half_w
	for h in hws:
		m = maxf(m, h)
	return m


func _compute_offsets() -> void:
	var n := samples.size()
	off_left.resize(n)
	off_right.resize(n)
	curb_mask.resize(n)
	for i in n:
		var k := curvature[i]
		var wb_i := wall_base + hws[i] - half_w
		var min_off := hws[i] + 1.0
		var l := wb_i
		var r := wb_i
		if absf(k) > 1e-4:
			var radius := 1.0 / absf(k)
			if k > 0.0:
				l = clampf(radius - 4.0, min_off, wb_i)
			else:
				r = clampf(radius - 4.0, min_off, wb_i)
		off_left[i] = l
		off_right[i] = r
	off_left = _min_then_blur(off_left, 8, 4)
	off_right = _min_then_blur(off_right, 8, 4)
	# curbs where the corner is tighter than ~80 m, dilated a bit
	var raw := PackedByteArray()
	raw.resize(n)
	for i in n:
		raw[i] = 1 if absf(curvature[i]) > 1.0 / 80.0 else 0
	for i in n:
		var on := 0
		for d in range(-6, 7):
			if raw[(i + d + n) % n] == 1:
				on = 1
				break
		curb_mask[i] = on
	# gravel traps (crash zones) on the outside of the tight corners, not on the playground's open pad
	trap.resize(n)
	trap.fill(0.0)
	if str(def.get("wall", "")) != "none":
		var rawt := PackedFloat32Array()
		rawt.resize(n)
		for i in n:
			rawt[i] = signf(curvature[i]) if absf(curvature[i]) > 1.0 / 70.0 else 0.0
		for i in n:
			var acc := 0.0
			for d in range(-12, 13):
				acc += rawt[(i + d + n) % n]
			trap[i] = clampf(acc / 25.0 * 2.2, -1.0, 1.0)


static func _min_then_blur(arr: PackedFloat32Array, min_window: int, passes: int) -> PackedFloat32Array:
	var n := arr.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var m := arr[i]
		for d in range(-min_window, min_window + 1):
			m = minf(m, arr[(i + d + n) % n])
		out[i] = m
	for _p in passes:
		var tmp := out.duplicate()
		for i in n:
			tmp[i] = (out[(i - 2 + n) % n] + out[(i - 1 + n) % n] + out[i] + out[(i + 1) % n] + out[(i + 2) % n]) / 5.0
		out = tmp
	return out


func _build_grid() -> void:
	_grid.clear()
	for i in samples.size():
		var p := samples[i]
		var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------
## The visible ground and its collision come from terrain.gd; this only adds a safety floor.
func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "SafetyFloor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var wb := WorldBoundaryShape3D.new()
	wb.plane = Plane(Vector3.UP, min_y - 45.0)
	shape.shape = wb
	body.add_child(shape)
	add_child(body)


func _build_road() -> void:
	var st := MeshKit.new_st()
	var n := samples.size()
	# a figure eight crosses itself: the second pass over the crossing lies 8 mm higher, so the two
	# road ribbons don't z-fight (they use the same world-space texture, the step is invisible)
	var lift := PackedFloat32Array()
	lift.resize(n)
	lift.fill(0.0)
	for i in (n if str(def.get("wall", "")) == "none" else 0):
		for j in range(i + n / 4, i + n * 3 / 4):
			var k := j % n
			if Vector2(samples[i].x - samples[k].x, samples[i].z - samples[k].z).length() < width * 1.6:
				# lift the pass that lies in the middle of the lap (no step at the lap seam)
				if absi(i - n / 2) < absi(k - n / 2):
					lift[i] = 1.0
				break
	var lift_s := lift.duplicate()
	for i in n:
		var acc := 0.0
		for d in range(-10, 11):
			acc += lift[(i + d + n) % n]
		lift_s[i] = minf(acc / 6.0, 1.0) * 0.008
	for i in n:
		var i2 := (i + 1) % n
		var d0 := dists[i]
		var d1 := dists[i2] if i2 != 0 else length
		var y0 := Vector3(0, ROAD_Y + lift_s[i], 0)
		var y1 := Vector3(0, ROAD_Y + lift_s[i2], 0)
		var a := edge_point(i, -hws[i]) + y0
		var b := edge_point(i, hws[i]) + y0
		var c := edge_point(i2, hws[i2]) + y1
		var d := edge_point(i2, -hws[i2]) + y1
		var nrm := (b - a).normalized().cross(tangents[i]).normalized() if elevated or raised else Vector3.UP
		MeshKit.quad(st, a, b, c, d, nrm, Vector2(0, d0), Vector2(1, d0), Vector2(1, d1), Vector2(0, d1))
	var mat := TexKit.road_material(def["asphalt"])
	road_material = mat
	var mesh := MeshKit.commit(st, mat, null, true)
	var mi := MeshKit.mesh_instance(mesh, null, false)
	mi.name = "Road"
	add_child(mi)


## Data tracks: the car drives on the road ribbon itself (the terrain grid can't follow a 2 m road
## exactly); the terrain in the corridor lies at the sample height, ROAD_Y below.
func _build_road_collision() -> void:
	var faces := PackedVector3Array()
	var n := samples.size()
	var y := Vector3(0, ROAD_Y, 0)
	for i in n:
		var i2 := (i + 1) % n
		# a raised spline track drives on a deck that reaches to the walls (no gap at the edge)
		var wl0 := off_left[i] + 0.3 if raised else hws[i]
		var wr0 := off_right[i] + 0.3 if raised else hws[i]
		var wl1 := off_left[i2] + 0.3 if raised else hws[i2]
		var wr1 := off_right[i2] + 0.3 if raised else hws[i2]
		var a := edge_point(i, -wl0) + y
		var b := edge_point(i, wr0) + y
		var c := edge_point(i2, wr1) + y
		var d := edge_point(i2, -wl1) + y
		# clockwise seen from above = Godot's front face (the other order made the road collision
		# face downwards, so the cars ran on the terrain under it)
		faces.append_array(PackedVector3Array([a, c, b, a, d, c]))
	var body := StaticBody3D.new()
	body.name = "RoadBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "road")
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Puddles in dips of the road surface (fixed per track so every player has the same ones).
## The mask lives in road space – lateral texels across the road, 0.5 m rows along it – folded into
## columns of PUDDLE_ROWS rows, so it stays small on a 20 km track.
const PUDDLE_LAT := 32
const PUDDLE_PX := 0.5
const PUDDLE_ROWS := 8192


func _build_puddles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track_id) + 991
	var n := samples.size()
	var count := int(length / 32.0)
	var noise := FastNoiseLite.new()
	noise.seed = rng.seed
	noise.frequency = 0.35
	var rows_total := int(ceil(length / PUDDLE_PX))
	var rows := mini(rows_total, PUDDLE_ROWS)
	var cols := int(ceil(float(rows_total) / rows))
	var w := cols * PUDDLE_LAT
	var data := PackedByteArray()
	data.resize(w * rows)
	data.fill(0)
	var lat_px := width / PUDDLE_LAT
	for k in count:
		var i := rng.randi_range(0, n - 1)
		var lateral := rng.randf_range(-half_w + 1.0, half_w - 1.0)
		if hws[i] != half_w or bank[i] != 0.0:
			continue
		var c: Vector3 = samples[i] + rights[i] * lateral
		var la := rng.randf_range(1.2, 3.6)
		var lc := rng.randf_range(0.7, 1.8)
		var ang := rng.randf_range(-0.5, 0.5)
		var t: Vector3 = tangents[i].rotated(Vector3.UP, ang)
		var r: Vector3 = Vector3(t.x, 0.0, t.z).normalized().cross(Vector3.UP).normalized()
		puddles.append({"c": c, "t": t, "r": r, "la": la, "lc": lc})
		var id := puddles.size() - 1
		var span := int(ceil(la / SPACING)) + 1
		for d in range(-span, span + 1):
			var si := (i + d + n) % n
			if not _puddle_index.has(si):
				_puddle_index[si] = []
			_puddle_index[si].append(id)
		# stamp a soft, noisy ellipse into the road-space mask (along = a, across = l)
		var ca := cos(ang)
		var sa := sin(ang)
		var reach := la + 0.5
		var r0 := int(floor((dists[i] - reach) / PUDDLE_PX))
		var r1 := int(ceil((dists[i] + reach) / PUDDLE_PX))
		var x0 := maxi(int(floor((lateral - reach + half_w) / lat_px)), 0)
		var x1 := mini(int(ceil((lateral + reach + half_w) / lat_px)), PUDDLE_LAT - 1)
		for row in range(r0, r1 + 1):
			var rw := posmod(row, rows_total)
			var da := (float(row) + 0.5) * PUDDLE_PX - dists[i]
			var col := rw / rows
			var ry := rw % rows
			for x in range(x0, x1 + 1):
				var dl := (float(x) + 0.5) * lat_px - half_w - lateral
				var e := Vector2((da * ca - dl * sa) / la, (da * sa + dl * ca) / lc).length()
				var v := clampf(1.0 - e + noise.get_noise_2d(da + dists[i], dl + lateral) * 0.3, 0.0, 1.0)
				var idx := ry * w + col * PUDDLE_LAT + x
				data[idx] = maxi(data[idx], int(v * 255.0))
	var tex := ImageTexture.create_from_image(Image.create_from_data(w, rows, false, Image.FORMAT_L8, data))
	road_material.set_shader_parameter("puddle_tex", tex)
	road_material.set_shader_parameter("puddle_map", Vector3(rows * PUDDLE_PX, cols, 0.5 / PUDDLE_LAT))


## Called by the weather: road wetness and puddle fill level (0..1).
func set_weather(p_wetness: float, p_puddles: float, rain := 0.0) -> void:
	wetness = p_wetness
	puddle_level = p_puddles
	if road_material:
		road_material.set_shader_parameter("wetness", wetness)
		road_material.set_shader_parameter("puddle_level", puddle_level)
		road_material.set_shader_parameter("rain", rain)


## 0..1: how deep in a puddle `pos` is (0 when dry).
func puddle_at(pos: Vector3, idx: int) -> float:
	if puddle_level <= 0.02 or not _puddle_index.has(idx):
		return 0.0
	var best := 0.0
	for id in _puddle_index[idx]:
		var p: Dictionary = puddles[id]
		var rel: Vector3 = pos - (p["c"] as Vector3)
		var e := Vector2(rel.dot(p["t"]) / float(p["la"]), rel.dot(p["r"]) / float(p["lc"])).length()
		# the visible puddle grows with the fill level (same threshold as the road shader)
		if e < puddle_level:
			best = maxf(best, 1.0 - e / maxf(puddle_level, 0.01) * 0.5)
	return best


func _build_curbs() -> void:
	var st := MeshKit.new_st()
	var n := samples.size()
	var curb_w := 1.3
	for i in n:
		var i2 := (i + 1) % n
		if curb_mask[i] == 0 or curb_mask[i2] == 0:
			continue
		var col := Color(0.85, 0.08, 0.06) if (i / 2) % 2 == 0 else Color(0.95, 0.95, 0.95)
		for side: float in [-1.0, 1.0]:
			var r0: Vector3 = rights[i] * side
			var r1: Vector3 = rights[i2] * side
			var y := Vector3(0, ROAD_Y + 0.012, 0)
			var yo := Vector3(0, ROAD_Y + 0.06, 0)
			var a: Vector3 = edge_point(i, side * (hws[i] - 0.2)) + y
			var b: Vector3 = edge_point(i, side * (hws[i] + curb_w)) + yo
			var c: Vector3 = edge_point(i2, side * (hws[i2] + curb_w)) + yo
			var d: Vector3 = edge_point(i2, side * (hws[i2] - 0.2)) + y
			MeshKit.quad(st, a, b, c, d, Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
			# outer lip down to the ground
			var e: Vector3 = edge_point(i, side * (hws[i] + curb_w + 0.15))
			var f: Vector3 = edge_point(i2, side * (hws[i2] + curb_w + 0.15))
			MeshKit.quad(st, b, e, f, c, r0 + Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	var mesh := MeshKit.commit(st, mat)
	var mi := MeshKit.mesh_instance(mesh, null, false)
	mi.name = "Curbs"
	add_child(mi)


func _build_walls() -> void:
	var n := samples.size()
	if def["wall"] == "none":
		return        # open pad: the playground has a barrier around the whole area instead
	var concrete: bool = def["wall"] == "concrete"
	var vis := MeshKit.new_st()
	var faces_l := PackedVector3Array()
	var faces_r := PackedVector3Array()
	var h := WALL_HEIGHT
	var thick := 0.5 if concrete else 0.25
	for side: float in [-1.0, 1.0]:
		var offs: PackedFloat32Array = off_left if side < 0.0 else off_right
		for i in n:
			if in_wall_gap(i, side):
				continue
			var i2 := (i + 1) % n
			var r0: Vector3 = rights[i] * side
			var r1: Vector3 = rights[i2] * side
			var a: Vector3 = edge_point(i, side * offs[i])
			var b: Vector3 = edge_point(i2, side * offs[i2])
			var a_out: Vector3 = a + r0 * thick
			var b_out: Vector3 = b + r1 * thick
			var up := Vector3(0, h, 0)
			var col := Color(0.78, 0.78, 0.76)
			if concrete:
				col = Color(0.85, 0.12, 0.1) if (i / 3) % 2 == 0 else Color(0.9, 0.9, 0.88)
			var inward: Vector3 = -r0
			var u0 := dists[i] / 4.0
			var u1 := (dists[i2] if i2 != 0 else length) / 4.0
			if concrete:
				# jersey barrier: sloped lower part, vertical upper part
				var lip := inward * 0.18
				MeshKit.quad(vis, a + lip, b + inward * 0.18, b + Vector3(0, 0.3, 0), a + Vector3(0, 0.3, 0), inward + Vector3.UP * 0.5,
					Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0.7), Vector2(u0, 0.7), Color(0.6, 0.6, 0.58))
				MeshKit.quad(vis, a + Vector3(0, 0.3, 0), b + Vector3(0, 0.3, 0), b + up, a + up, inward,
					Vector2(u0, 0.7), Vector2(u1, 0.7), Vector2(u1, 0), Vector2(u0, 0), col)
			else:
				MeshKit.quad(vis, a + Vector3(0, 0.38, 0), b + Vector3(0, 0.38, 0), b + Vector3(0, 0.78, 0), a + Vector3(0, 0.78, 0), inward,
					Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0), col)
				MeshKit.quad(vis, a_out + Vector3(0, 0.38, 0), b_out + Vector3(0, 0.38, 0), b_out + Vector3(0, 0.78, 0), a_out + Vector3(0, 0.78, 0), -inward,
					Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0), col)
			if concrete:
				MeshKit.quad(vis, a + up, b + up, b_out + up, a_out + up, Vector3.UP,
					Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 0.1), Vector2(u0, 0.1), Color(0.7, 0.7, 0.68))
				MeshKit.quad(vis, a_out, b_out, b_out + up, a_out + up, -inward,
					Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0), Color(0.6, 0.6, 0.58))
			else:
				MeshKit.quad(vis, a + Vector3(0, 0.78, 0), b + Vector3(0, 0.78, 0), b_out + Vector3(0, 0.78, 0), a_out + Vector3(0, 0.78, 0), Vector3.UP,
					Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 0.1), Vector2(u0, 0.1), col)
			# collision: vertical wall face towards the road
			var faces: PackedVector3Array = faces_l if side < 0.0 else faces_r
			var hc := Vector3(0, h + 0.4, 0)
			faces.append_array(PackedVector3Array([a, b, b + hc, a, b + hc, a + hc]))
			if side < 0.0:
				faces_l = faces
			else:
				faces_r = faces
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	if concrete:
		mat.roughness = 0.9
		mat.albedo_texture = TexKit.noise_texture(51, 0.08, false, 256)
		mat.uv1_scale = Vector3(1, 1, 1)
	else:
		mat.metallic = 0.85
		mat.roughness = 0.35
	var mesh := MeshKit.commit(vis, mat)
	var mi := MeshKit.mesh_instance(mesh)
	mi.name = "Walls"
	add_child(mi)
	if not concrete:
		_build_posts()
	var body := StaticBody3D.new()
	body.name = "WallBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.25
	pm.bounce = 0.15
	body.physics_material_override = pm
	body.set_meta("surface", "wall")
	for faces in [faces_l, faces_r]:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	add_child(body)


## Builds the barriers again (after openings were added to wall_gaps once the track was built).
func rebuild_walls() -> void:
	for nm in ["Walls", "WallBody", "Posts"]:
		var old := get_node_or_null(nm)
		if old:
			remove_child(old)
			old.free()
	_build_walls()


## True when the barrier segment from sample i to i + 1 on this side is left open.
func in_wall_gap(i: int, side: float) -> bool:
	if wall_gaps.is_empty():
		return false
	var p := fposmod(dists[(i + samples.size()) % samples.size()] - start_dist, length)
	for g in wall_gaps:
		if signf(float(g[2])) == signf(side) and p >= float(g[0]) and p <= float(g[1]):
			return true
	return false


## Sample index at `progress` metres from the start line.
func index_at(progress: float) -> int:
	var n := samples.size()
	return (start_index + int(round(progress / SPACING)) + n * 4) % n


func _build_posts() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.85, 0.12)
	mm.mesh = post
	var xfs: Array = []
	var n := samples.size()
	for side: float in [-1.0, 1.0]:
		var offs: PackedFloat32Array = off_left if side < 0.0 else off_right
		for i in range(0, n, 2):
			if in_wall_gap(i, side) or in_wall_gap(i - 1, side):
				continue
			var p: Vector3 = edge_point(i, side * (offs[i] + 0.12)) + Vector3(0, 0.42, 0)
			xfs.append(Transform3D(Basis.IDENTITY, p))
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = TexKit.std(Color(0.55, 0.56, 0.58), 0.4, 0.8)
	mmi.name = "Posts"
	add_child(mmi)


func _build_start() -> void:
	var i := start_index
	var p := samples[i]
	var t := tangents[i]
	var r := rights[i]
	# checkered line
	var st := MeshKit.new_st()
	var y := Vector3(0, ROAD_Y + 0.008, 0)
	var a := p - r * half_w - t * 1.2 + y
	var b := p + r * half_w - t * 1.2 + y
	var c := p + r * half_w + t * 1.2 + y
	var d := p - r * half_w + t * 1.2 + y
	MeshKit.quad(st, a, b, c, d, Vector3.UP, Vector2(0, 0), Vector2(width / 2.4, 0), Vector2(width / 2.4, 1), Vector2(0, 1))
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = TexKit.checker_texture()
	cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	cm.roughness = 0.7
	var line := MeshKit.mesh_instance(MeshKit.commit(st, cm), null, false)
	line.name = "StartLine"
	add_child(line)
	# gantry
	var g := Node3D.new()
	g.name = "Gantry"
	add_child(g)
	g.global_transform = Transform3D(Basis.looking_at(Vector3(t.x, 0.0, t.z).normalized(), Vector3.UP), p)
	var steel := TexKit.std(Color(0.12, 0.12, 0.14), 0.4, 0.7)
	var span := half_w + 2.0
	gantry_xf = g.global_transform
	stand_x = span
	for side: float in [-1.0, 1.0]:
		g.add_child(MeshKit.box_node(Vector3(0.6, 7.0, 0.6), steel, Vector3(side * span, 3.5, 0)))
	g.add_child(MeshKit.box_node(Vector3(span * 2.0 + 0.6, 1.3, 0.8), steel, Vector3(0, 7.2, 0)))
	var banner := TexKit.emissive(Color(0.55, 0.2, 0.95), 1.6)
	g.add_child(MeshKit.box_node(Vector3(span * 1.6, 0.9, 0.05), banner, Vector3(0, 7.2, -0.43)))
	g.add_child(MeshKit.box_node(Vector3(span * 1.6, 0.9, 0.05), banner, Vector3(0, 7.2, 0.43)))
	# start lights (3x red, 1x green)
	_start_lights.clear()
	for k in 4:
		var col := Color(1.0, 0.1, 0.05) if k < 3 else Color(0.1, 1.0, 0.2)
		var m := TexKit.emissive(col, 0.0)
		for face: float in [-1.0, 1.0]:
			var s := MeshKit.sphere_node(0.32, m, Vector3(-1.8 + k * 1.2, 5.9, 0.35 * face))
			g.add_child(s)
		_start_lights.append(m)
	# spectator stands and flags next to the start
	var stand_mat := TexKit.std(Color(0.3, 0.3, 0.34), 0.7)
	var stand := MeshKit.box_node(Vector3(4.0, 2.5, 30.0), stand_mat, Vector3(span + 7.0, 1.25, 0))
	g.add_child(stand)
	for k in 5:
		var step_box := MeshKit.box_node(Vector3(1.2, 0.5, 30.0), stand_mat, Vector3(span + 5.6 + k * 0.7, 2.5 + k * 0.5, 0))
		g.add_child(step_box)
	var roof := MeshKit.box_node(Vector3(6.0, 0.2, 31.0), TexKit.std(Color(0.35, 0.12, 0.55), 0.5), Vector3(span + 7.5, 6.5, 0))
	g.add_child(roof)
	# gantry pillars, grandstand and its roof are solid
	Colliders.add_trimesh(g)


## state: 0 = off, 1..3 = number of red lights lit, 4 = green
func set_start_lights(state: int) -> void:
	for k in _start_lights.size():
		var m: StandardMaterial3D = _start_lights[k]
		var on := (k < 3 and state >= k + 1 and state <= 3) or (k == 3 and state == 4)
		m.emission_energy_multiplier = 6.0 if on else 0.0


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
## Returns [index, progress_from_start (0..length), lateral_offset]
func project(pos: Vector3, hint: int = -1) -> Array:
	var n := samples.size()
	var best := -1
	var best_d := 1e20
	if hint >= 0:
		for k in range(-12, 13):
			var i := (hint + k + n) % n
			var d := Vector2(pos.x - samples[i].x, pos.z - samples[i].z).length_squared()
			if d < best_d:
				best_d = d
				best = i
	if best < 0 or best_d > 30.0 * 30.0:
		best = nearest_index(pos)
	var p := samples[best]
	var rel := pos - p
	var along := dists[best] + rel.dot(tangents[best])
	var lateral := rel.dot(rights[best])
	var prog := fposmod(along - start_dist, length)
	return [best, prog, lateral]


func nearest_index(pos: Vector3) -> int:
	var cx := int(floor(pos.x / CELL))
	var cz := int(floor(pos.z / CELL))
	var best := -1
	var best_d := 1e20
	for radius: int in [1, 3, 8]:
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var key := Vector2i(cx + dx, cz + dz)
				if not _grid.has(key):
					continue
				for i in _grid[key]:
					var s: Vector3 = samples[i]
					var d := Vector2(pos.x - s.x, pos.z - s.z).length_squared()
					if d < best_d:
						best_d = d
						best = i
		if best >= 0:
			return best
	# fallback: brute force
	for i in samples.size():
		var d := Vector2(pos.x - samples[i].x, pos.z - samples[i].z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return maxi(best, 0)


## Distance from `pos` to the centerline, 1e9 when far away (> ~60 m). Where the road is wider than
## its base width (half_w) the extra width is taken off, so "distance < half_w + x" checks (scenery,
## AI, road tests) work the same on the widened parts.
func distance_to_center(pos: Vector3) -> float:
	var cx := int(floor(pos.x / CELL))
	var cz := int(floor(pos.z / CELL))
	var best_d := 1e18
	var best_i := -1
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var key := Vector2i(cx + dx, cz + dz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				var s: Vector3 = samples[i]
				var dd := Vector2(pos.x - s.x, pos.z - s.z).length_squared()
				if dd < best_d:
					best_d = dd
					best_i = i
	if best_d >= 1e17:
		return 1e9
	return maxf(sqrt(best_d) - (hws[best_i] - half_w), 0.0)


## Distance to the road edge (R, 0..8 m) and gravel-trap weight (G) at 1 m resolution, shared by the
## terrain (gravel shoulder and traps) and the grass (kept off both).
## Returns {"tex": ImageTexture, "origin": Vector2, "inv_size": Vector2}.
func edge_data() -> Dictionary:
	if _edge.is_empty():
		_compute_edge()
	return _edge


## `sliced`: hand frames back to the loading screen while stamping (world build).
func _compute_edge(sliced := false) -> void:
	# 1 m texels; 2 m on the long data tracks (a distance field interpolates well, 60 MB would not)
	var px := 2.0 if elevated else 1.0
	var b: Rect2 = bounds.grow(max_half_w() + 12.0)
	var origin := b.position
	var w := int(ceil(b.size.x / px))
	var h := int(ceil(b.size.y / px))
	var best := PackedFloat32Array()
	best.resize(w * h)
	best.fill(1e9)
	var data := PackedByteArray()
	data.resize(w * h * 2)
	for k in w * h:
		data[k * 2] = 255
	var reach := int(ceil((max_half_w() + 8.0) / px))
	for i in samples.size():
		if sliced and i % 256 == 0:
			await Game.load_tick()
		var s: Vector3 = samples[i]
		var r: Vector3 = rights[i]
		var tw := trap[i]
		var cx := int((s.x - origin.x) / px)
		var cz := int((s.z - origin.y) / px)
		for dz in range(-reach, reach + 1):
			var gz := cz + dz
			if gz < 0 or gz >= h:
				continue
			var wz := origin.y + (gz + 0.5) * px - s.z
			for dx in range(-reach, reach + 1):
				var gx := cx + dx
				if gx < 0 or gx >= w:
					continue
				var wx := origin.x + (gx + 0.5) * px - s.x
				var dd := wx * wx + wz * wz
				var k := gz * w + gx
				if dd >= best[k]:
					continue
				best[k] = dd
				var edge := sqrt(dd) - hws[i]
				data[k * 2] = int(clampf(edge / 8.0, 0.0, 1.0) * 255.0)
				var side := wx * r.x + wz * r.z
				var g := absf(tw) if tw * side > 0.0 else 0.0
				data[k * 2 + 1] = int(g * 255.0)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RG8, data)
	_edge = {"tex": ImageTexture.create_from_image(img), "origin": origin, "inv_size": Vector2(1.0 / (w * px), 1.0 / (h * px))}


## Grip multiplier & surface name at a world position, given the track index nearby.
func surface_at(pos: Vector3, idx: int) -> Array:
	var rel := pos - samples[idx]
	var side_d := rel.dot(rights[idx])
	var lat := absf(side_d)
	var hw_i: float = hws[idx] if idx < hws.size() else half_w
	if lat <= hw_i:
		var g := 1.0 - 0.18 * wetness
		var pd := puddle_at(pos, idx)
		if pd > 0.0:
			g *= 1.0 - 0.5 * pd
		return [g, "asphalt"]
	if curb_mask[idx] == 1 and lat <= hw_i + 1.4:
		return [0.97 * (1.0 - 0.3 * wetness), "curb"]
	if trap.size() > idx and trap[idx] * side_d > 0.0 and absf(trap[idx]) > 0.4 and lat < hw_i + trap_w:
		return [0.5 * (1.0 - 0.1 * wetness), "gravel"]
	if ground_fn.is_valid():
		var g2: Array = ground_fn.call(pos)
		if not g2.is_empty():
			return g2
	return [float(def["offroad_grip"]) * (1.0 - 0.12 * wetness), str(def["ground"])]


func transform_at(idx: int, lateral := 0.0, height := 0.5) -> Transform3D:
	var n := samples.size()
	idx = (idx % n + n) % n
	var b := Basis.looking_at(tangents[idx], Vector3.UP)
	return Transform3D(b, edge_point(idx, lateral) + Vector3(0, height, 0))


func grid_transform(slot: int) -> Transform3D:
	var row := slot / 2
	var col := slot % 2
	var back := 9.0 + row * 10.0
	var idx := start_index - int(round(back / SPACING))
	var lateral := (-1.0 if col == 0 else 1.0) * half_w * 0.32
	return transform_at(idx, lateral, 0.45)


func sample_count() -> int:
	return samples.size()


func minimap_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	# ~1200 points at most: plenty for a minimap, cheap to draw on the 20 km track
	for i in range(0, samples.size(), maxi(3, samples.size() / 1200)):
		pts.append(Vector2(samples[i].x, samples[i].z))
	return pts


func register_lamp_light(l: Light3D) -> void:
	_lamp_lights.append(l)
