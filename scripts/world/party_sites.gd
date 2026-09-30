extends Node3D
## Party mode: the minigames are played on the track itself. plan() picks a stretch of road for every
## minigame (as straight as possible, not overlapping); build_course() puts up its props (traffic light,
## obstacles, zone) only for the time of the minigame – clear_course() takes them away again, so the
## race track is free afterwards. Positions along a stretch: `along` metres from its start (in the race
## direction), `lateral` metres to the right of the centreline.

const TexKit = preload("res://scripts/util/tex_kit.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")

## id, length of the stretch (m)
const COURSES := [
	["rlgl", 190.0],
	["parkour", 210.0],
	["koth", 110.0],
	["donut", 120.0],
	["bowling", 95.0],
	["arena", 110.0],
]
const RLGL_START := 10.0          # start line (m along)
const PK_START := 10.0
const KOTH_ZONE_R := 5.0
const DONUT_R := 16.0             # a donut counts within this distance of your spot
const BOWL_START := 8.0
const ARENA_WALL := 4.0           # the arena's end walls, m in from both ends of its stretch

var track: Node3D
var sites := {}                   # id -> {"i0": start sample, "len": metres, "p0": race progress at the start}
var koth_zone: Node3D
var rlgl_lamps: Array = []        # [red material, green material]
var pin_mesh: ArrayMesh
var mud_spots: Array = []         # parkour: [centre, radius] of the mud patches (less grip)
var _course: Node3D


## Chooses the stretches (apart from each other where the track is long enough). Always succeeds on
## a closed track.
func plan(p_track: Node3D) -> bool:
	track = p_track
	var n: int = track.sample_count()
	var sp: float = track.SPACING
	# heading change per sample (prefix sums): how curvy a window is
	var turn := PackedFloat32Array()
	turn.resize(n * 2 + 1)
	turn[0] = 0.0
	for k in n * 2:
		var a: Vector3 = track.tangents[k % n]
		var b: Vector3 = track.tangents[(k + 1) % n]
		turn[k + 1] = turn[k] + absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
	var used: Array = []          # [start sample, sample count]
	# short tracks (the playground): all stretches shrink so that they fit around the lap
	var total := 0.0
	for c in COURSES:
		total += float(c[1]) + 40.0
	var k := clampf(float(track.length) * 0.9 / total, 0.62, 1.0)
	for c in COURSES:
		var id: String = c[0]
		var len := float(c[1]) * k
		var cnt := int(ceil(len / sp)) + 10
		var best := -1
		var best_turn := 1e9
		for i in range(0, n, 4):
			if _overlaps(i, cnt, used, n):
				continue
			var t := turn[i + cnt] - turn[i]
			if t < best_turn:
				best_turn = t
				best = i
		if best < 0:
			# no free stretch left (short tracks): share one – the props only stand during their game
			for i in range(0, n, 4):
				var t2 := turn[i + cnt] - turn[i]
				if t2 < best_turn:
					best_turn = t2
					best = i
		if best < 0:
			continue
		used.append([best, cnt])
		var p0 := fposmod(float(track.dists[best]) - float(track.start_dist), float(track.length))
		sites[id] = {"i0": best, "len": len, "p0": p0}
	# the balloon battle is fought in the arena
	if sites.has("arena"):
		sites["balloon"] = sites["arena"]
	return not sites.is_empty()


func _overlaps(i: int, cnt: int, used: Array, n: int) -> bool:
	for u in used:
		var a: int = u[0]
		var m: int = u[1]
		# circular distance between the two windows, with 20 m spare
		var gap := 10
		if posmod(i - a, n) < m + gap or posmod(a - i, n) < cnt + gap:
			return true
	return false


## World transform at a point of a stretch (the car's -z looks in the race direction).
func course_xf(id: String, along: float, lateral := 0.0, height := 0.0) -> Transform3D:
	var s: Dictionary = sites[id]
	var idx := int(s["i0"]) + int(round(along / float(track.SPACING)))
	return track.transform_at(idx, lateral, height)


## Metres along the stretch at world position p (negative before its start).
func progress(id: String, p: Vector3, hint := -1) -> float:
	var proj: Array = track.project(p, hint)
	return wrapf(float(proj[1]) - float(sites[id]["p0"]), -float(track.length) * 0.5, float(track.length) * 0.5)


## Start position for grid slot `slot` of `count` cars.
func start_xf(id: String, slot: int, count: int) -> Transform3D:
	var hw: float = float(track.half_w) - 2.2
	match id:
		"rlgl", "parkour":
			# rows of three across the road, behind the start line
			var row := slot / 3
			var col := slot % 3
			var in_row := mini(count - row * 3, 3)
			var lat := (col - (in_row - 1) * 0.5) * minf(hw, 4.6)
			return course_xf(id, (RLGL_START if id == "rlgl" else PK_START) - 4.0 - row * 7.0, lat, 0.6)
		"koth":
			return course_xf(id, 20.0 + slot * 9.0, (1.0 if slot % 2 == 0 else -1.0) * hw * 0.5, 0.6)
		"bowling":
			# everybody bowls on their own pins from the same spot (the others are ghosts here)
			return course_xf(id, BOWL_START - 4.0, 0.0, 0.6)
		"arena", "balloon":
			return arena_spawn(slot)
	return course_xf(id, donut_along(slot), 0.0, 0.6)


func donut_along(slot: int) -> float:
	return 10.0 + (slot % 8) * minf(14.0, (float(sites["donut"]["len"]) - 12.0) / 8.0)


func rlgl_finish() -> float:
	return float(sites["rlgl"]["len"]) - 15.0


func pk_finish() -> float:
	return float(sites["parkour"]["len"]) - 10.0


func pk_checkpoints() -> Array:
	var l: float = sites["parkour"]["len"]
	return [0.0, l * 0.26, l * 0.5, l * 0.71]


## Parkour: respawn at the last checkpoint passed.
func checkpoint_xf(along: float) -> Transform3D:
	return course_xf("parkour", along + 3.0, 0.0, 0.6)


## King of the zone: the zone's spot (along, lateral) for step k of a match with this seed.
func koth_spot(seed_v: int, k: int) -> Vector2:
	var len: float = sites["koth"]["len"]
	if k == 0:
		return Vector2(len * 0.5, 0.0)
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_v, k])
	return Vector2(r.randf_range(12.0, len - 12.0), r.randf_range(-1.0, 1.0) * maxf(float(track.half_w) - KOTH_ZONE_R - 0.5, 0.0))


# ---------------------------------------------------------------------------
# Courses (built for the minigame only)
# ---------------------------------------------------------------------------
func build_course(id: String) -> void:
	clear_course()
	_course = Node3D.new()
	_course.name = "Course_" + id
	add_child(_course)
	match id:
		"rlgl":
			_build_rlgl()
		"parkour":
			_build_parkour()
		"koth":
			_build_koth()
		"donut":
			_build_donut()
		"bowling":
			_build_bowling()
		"arena", "balloon":
			_build_arena()


func clear_course() -> void:
	if _course:
		remove_child(_course)
		_course.free()
		_course = null
	koth_zone = null
	rlgl_lamps = []
	mud_spots = []


func _mat(c: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	return TexKit.std(c, rough, 0.0, c, emit)


## Solid block with collision at a point of the stretch (size: x across, y up, z along).
func _block(id: String, along: float, lateral: float, size: Vector3, mat: Material, pitch := 0.0, y := 0.0) -> void:
	var xf := course_xf(id, along, lateral, 0.0)
	xf = xf * Transform3D(Basis.from_euler(Vector3(pitch, 0, 0)), Vector3(0, float(track.ROAD_Y) + y, 0))
	var mi := MeshKit.box_node(size, mat)
	_course.add_child(mi)
	mi.global_transform = xf
	Colliders.add_box(_course, xf, size)


## Flat marking on the road (no collision).
func _paint(id: String, along: float, lateral: float, size: Vector2, mat: Material) -> void:
	var xf := course_xf(id, along, lateral, float(track.ROAD_Y) + 0.012)
	var mi := MeshKit.box_node(Vector3(size.x, 0.02, size.y), mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_course.add_child(mi)
	mi.global_transform = xf


func _line(id: String, along: float) -> void:
	var hw: float = track.half_w
	var n := int(hw * 2.0 / 1.5)
	var white := _mat(Color.WHITE, 0.7)
	var black := _mat(Color(0.08, 0.08, 0.08), 0.7)
	for i in n:
		for r in 2:
			_paint(id, along + r * 0.75, -hw + 0.75 + i * 1.5, Vector2(1.5, 0.75), white if (i + r) % 2 == 0 else black)


## A gantry across the road with a sign (and optionally the traffic light).
func _gantry(id: String, along: float, text: String, color: Color, light := false) -> void:
	var hw: float = float(track.half_w) + 0.8
	var pole := _mat(Color(0.1, 0.1, 0.12), 0.5)
	var xf := course_xf(id, along, 0.0, 0.0)
	var root := Node3D.new()
	_course.add_child(root)
	root.global_transform = xf
	for x: float in [-hw, hw]:
		root.add_child(MeshKit.box_node(Vector3(0.5, 8.0, 0.5), pole, Vector3(x, 4.0, 0)))
		Colliders.add_box(_course, xf * Transform3D(Basis.IDENTITY, Vector3(x, 4.0, 0)), Vector3(0.5, 8.0, 0.5))
	root.add_child(MeshKit.box_node(Vector3(hw * 2.0, 0.6, 0.6), pole, Vector3(0, 7.9, 0)))
	root.add_child(MeshKit.box_node(Vector3(12.0, 1.6, 0.3), _mat(Color(0.06, 0.03, 0.1), 0.5), Vector3(0, 9.0, 0)))
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = text
		l.font_size = 100
		l.outline_size = 20
		l.modulate = color
		l.pixel_size = 0.009
		l.position = Vector3(0, 9.0, 0.17 * side)
		l.rotation = Vector3(0, 0.0 if side > 0.0 else PI, 0)
		root.add_child(l)
	if light:
		root.add_child(MeshKit.box_node(Vector3(7.0, 3.4, 1.2), _mat(Color(0.05, 0.05, 0.06), 0.4), Vector3(0, 5.9, 0)))
		var red := _mat(Color(1.0, 0.1, 0.05), 0.3, 0.2)
		var green := _mat(Color(0.1, 1.0, 0.3), 0.3, 0.2)
		# the lamps face the cars coming up the stretch (+z of the gantry)
		root.add_child(MeshKit.sphere_node(1.2, red, Vector3(-1.8, 5.9, 0.6), Vector3(1, 1, 0.4)))
		root.add_child(MeshKit.sphere_node(1.2, green, Vector3(1.8, 5.9, 0.6), Vector3(1, 1, 0.4)))
		rlgl_lamps = [red, green]


func _build_rlgl() -> void:
	_line("rlgl", RLGL_START)
	_line("rlgl", rlgl_finish())
	_gantry("rlgl", rlgl_finish() + 6.0, "ROTES LICHT · GRÜNES LICHT", Color(1.0, 0.35, 0.35), true)
	set_rlgl_light(0)


## -1 off, 0 red, 1 green
func set_rlgl_light(state: int) -> void:
	if rlgl_lamps.is_empty():
		return
	(rlgl_lamps[0] as StandardMaterial3D).emission_energy_multiplier = 8.0 if state == 0 else 0.15
	(rlgl_lamps[1] as StandardMaterial3D).emission_energy_multiplier = 8.0 if state == 1 else 0.15


func _build_parkour() -> void:
	var id := "parkour"
	var hw: float = track.half_w
	var hazard := _mat(Color(1.0, 0.75, 0.05), 0.6, 0.3)
	var len: float = sites[id]["len"]
	var k: float = len / 210.0     # shorter on short tracks
	# the same layout on every machine (seeded by the stretch), but nothing lined up
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["parkour", int(sites[id]["i0"])])
	_line(id, PK_START)
	_line(id, pk_finish())
	_gantry(id, pk_finish() + 5.0, "OFFROAD-PARKOUR", Color(1.0, 0.7, 0.2))
	# mud: ragged patches all over the stretch, some wide, some narrow, overlapping
	mud_spots.clear()
	var a := PK_START + 4.0
	var n_mud := 0
	while a < pk_finish() - 4.0:
		var r := rng.randf_range(3.5, 8.0)
		_mud_patch(id, a + r * 0.6, rng.randf_range(-0.55, 0.55) * hw, r, rng, n_mud)
		a += r * rng.randf_range(1.1, 1.9)
		n_mud += 1
	# 1) tyre stacks, scattered in the first mud field (1–3 tyres, never in a neat row)
	var t_along := 22.0 * k
	for m in 6:
		t_along += rng.randf_range(6.0, 10.0) * k
		var lat := (-1.0 if m % 2 == 0 else 1.0) * rng.randf_range(0.15, 0.6) * hw
		_tyre_stack(id, t_along, lat, rng.randi_range(1, 3), rng)
		if rng.randf() < 0.4:
			_tyre_stack(id, t_along + rng.randf_range(-1.5, 1.5), lat + rng.randf_range(1.2, 1.6) * signf(-lat), 1, rng)
	# 2) log field: felled trunks lying every which way, thin enough to crawl over with the lift
	var f0 := 72.0 * k
	var f1 := 108.0 * k
	var n_logs := int(clampf(15.0 * k, 7.0, 15.0))
	for m in n_logs:
		var along := lerpf(f0, f1, (m + rng.randf_range(0.1, 0.9)) / n_logs)
		var r2 := rng.randf_range(0.13, 0.24)
		var l := rng.randf_range(2.8, minf(6.5, hw * 1.6))
		var yaw := rng.randf_range(-0.65, 0.65)
		if rng.randf() < 0.2:
			yaw = PI * 0.5 + rng.randf_range(-0.3, 0.3)   # now and then one lies along the road
			l = minf(l, 4.0)
		_log(id, along, rng.randf_range(-0.75, 0.75) * (hw - l * 0.3), yaw, r2, l, rng)
	# a pile at each side of the field: two trunks with a third in the groove on top
	for side: float in [-1.0, 1.0]:
		var pa := rng.randf_range(f0 + 4.0, f1 - 6.0)
		var pl := side * (hw - 1.3)
		var pr := rng.randf_range(0.3, 0.38)
		var pyaw := PI * 0.5 + rng.randf_range(-0.2, 0.2)
		var plen := rng.randf_range(5.0, 7.5)
		_log(id, pa, pl - 0.36 * pr / 0.35, pyaw, pr, plen, rng)
		_log(id, pa + rng.randf_range(-0.4, 0.4), pl + 0.36 * pr / 0.35, pyaw + rng.randf_range(-0.06, 0.06), pr * rng.randf_range(0.9, 1.05), plen * rng.randf_range(0.8, 1.0), rng)
		_log(id, pa + rng.randf_range(-0.8, 0.8), pl, pyaw + rng.randf_range(-0.1, 0.1), pr * 0.85, plen * rng.randf_range(0.6, 0.9), rng, pr * 1.55)
	# 3) plank kickers: different sizes, a bit skewed, propped up by a log
	var r_along := 118.0 * k
	for m in 3:
		r_along += rng.randf_range(10.0, 16.0) * k
		var rl := rng.randf_range(5.5, 8.0)
		var rh := rng.randf_range(0.8, 1.35)
		var rw := rng.randf_range(3.2, minf(5.0, hw * 0.9))
		var rlat := (-1.0 if m % 2 == 0 else 1.0) * rng.randf_range(0.1, 0.45) * hw
		_ramp(id, r_along, rlat, rng.randf_range(-0.22, 0.22), rl, rh, rw, rng)
	# 4) chicane of stacked trunks, alternating sides, not quite straight
	var c_along := 168.0 * k
	for m in 4:
		var side2 := -1.0 if m % 2 == 0 else 1.0
		var cl := hw * rng.randf_range(1.05, 1.2)
		var cyaw := rng.randf_range(-0.18, 0.18)
		var clat := side2 * (hw - cl * 0.5 + 0.3)
		var cr := rng.randf_range(0.27, 0.34)
		for j in 2:
			_log(id, c_along + (j - 0.5) * cr * 2.02, clat + rng.randf_range(-0.3, 0.3), cyaw + rng.randf_range(-0.04, 0.04), cr, cl * rng.randf_range(0.92, 1.05), rng)
		_log(id, c_along + rng.randf_range(-0.1, 0.1), clat + rng.randf_range(-0.5, 0.5), cyaw + rng.randf_range(-0.08, 0.08), cr * 0.9, cl * rng.randf_range(0.7, 0.95), rng, cr * 1.7)
		c_along += rng.randf_range(9.0, 12.0) * k
	# boulders along the edges
	for m in 7:
		var side3 := -1.0 if rng.randf() < 0.5 else 1.0
		_rock(id, rng.randf_range(PK_START + 10.0, pk_finish() - 8.0), side3 * rng.randf_range(hw - 1.8, hw - 0.6), rng.randf_range(0.45, 0.9), rng)
	# checkpoint arches
	for cz in pk_checkpoints():
		if float(cz) <= 0.0:
			continue
		var xf := course_xf(id, cz, 0.0, 0.0)
		for x: float in [-hw - 0.5, hw + 0.5]:
			var post := MeshKit.box_node(Vector3(0.35, 4.5, 0.35), hazard)
			_course.add_child(post)
			post.global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(x, 2.25, 0))
		var top := MeshKit.box_node(Vector3(hw * 2.0 + 1.0, 0.35, 0.35), hazard)
		_course.add_child(top)
		top.global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.5, 0))


## Frame on the road surface at a point of a stretch, turned by yaw (0 = across the road).
func _road_xf(id: String, along: float, lateral: float, yaw := 0.0, y := 0.0) -> Transform3D:
	return course_xf(id, along, lateral, 0.0) * Transform3D(Basis(Vector3.UP, yaw), Vector3(0, float(track.ROAD_Y) + y, 0))


## A felled trunk lying on the road (or on others: `y` = height of its axis above the road, 0 =
## resting on the road). Slightly irregular and tapered, bark and cut ends, a branch stub or two.
func _log(id: String, along: float, lateral: float, yaw: float, r: float, length: float, rng: RandomNumberGenerator, y := 0.0) -> void:
	var mats: Array = TexKit.log_materials()
	var xf := _road_xf(id, along, lateral, yaw, (y if y > 0.0 else r) - 0.02)
	xf = xf * Transform3D(Basis(Vector3.RIGHT, rng.randf_range(0.0, TAU)), Vector3.ZERO)   # roll: the knots end up anywhere
	var mesh := _log_mesh(r, length, rng, mats)
	var mi := MeshKit.mesh_instance(mesh, null)
	_course.add_child(mi)
	mi.global_transform = xf
	var body := StaticBody3D.new()
	body.collision_layer = Colliders.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r * 0.97
	shape.height = length
	cs.shape = shape
	cs.rotation = Vector3(0, 0, PI * 0.5)
	body.add_child(cs)
	_course.add_child(body)
	body.global_transform = xf


func _log_mesh(r: float, length: float, rng: RandomNumberGenerator, mats: Array) -> ArrayMesh:
	var segs := 14
	var rings := maxi(3, int(length / 0.5))
	var ph := rng.randf_range(0.0, TAU)
	var lump := rng.randf_range(0.03, 0.07)
	var taper := rng.randf_range(0.08, 0.2)
	var bend := rng.randf_range(-0.06, 0.06)
	var tone := Color(1.0, 1.0, 1.0).darkened(rng.randf_range(0.0, 0.25))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_pts: Array = []
	for i in rings + 1:
		var t := float(i) / rings
		var x := (t - 0.5) * length
		var rr := r * (1.0 + taper * 0.5 - taper * t) * (1.0 + rng.randf_range(-0.025, 0.025))
		var off := Vector3(0, bend * sin(t * PI) * length * 0.3, 0)
		var pts: Array = []
		for j in segs + 1:
			var ang := float(j) / segs * TAU
			var f := 1.0 + lump * sin(ang * 3.0 + ph) + lump * 0.5 * sin(ang * 5.0 + ph * 2.0)
			var n := Vector3(0, cos(ang), sin(ang))
			pts.append([Vector3(x, 0, 0) + off + n * rr * f, n, Vector2(float(j) / segs * 2.0, x * 0.45)])
		ring_pts.append(pts)
	for i in rings:
		for j in segs:
			var a: Array = ring_pts[i][j]
			var b: Array = ring_pts[i][j + 1]
			var c: Array = ring_pts[i + 1][j + 1]
			var d: Array = ring_pts[i + 1][j]
			var out: Vector3 = (a[1] as Vector3) + (c[1] as Vector3)
			MeshKit.tri(st, a[0], b[0], c[0], a[1], b[1], c[1], a[2], b[2], c[2], out, tone)
			MeshKit.tri(st, a[0], c[0], d[0], a[1], c[1], d[1], a[2], c[2], d[2], out, tone)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, mats[0])
	# cut ends
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in 2:
		var pts2: Array = ring_pts[0 if e == 0 else rings]
		var nx := Vector3(-1, 0, 0) if e == 0 else Vector3(1, 0, 0)
		var ctr := Vector3.ZERO
		for j in segs:
			ctr += pts2[j][0] as Vector3
		ctr /= float(segs)
		var uv := func(q: Vector3) -> Vector2: return Vector2(0.5 + (q - ctr).z / (r * 2.2), 0.5 + (q - ctr).y / (r * 2.2))
		for j in segs:
			var p0: Vector3 = pts2[j][0]
			var p1: Vector3 = pts2[j + 1][0]
			MeshKit.tri(st2, ctr, p0, p1, nx, nx, nx, uv.call(ctr), uv.call(p0), uv.call(p1), nx)
	st2.commit(mesh)
	mesh.surface_set_material(1, mats[1])
	return mesh


## 1–3 old tyres stacked, a little skewed, with one cylinder collider.
func _tyre_stack(id: String, along: float, lateral: float, count: int, rng: RandomNumberGenerator) -> void:
	var rub := TexKit.rubber()
	var h := 0.36
	for i in count:
		var xf := _road_xf(id, along, lateral, 0.0, h * (i + 0.5))
		xf.origin += xf.basis.x * rng.randf_range(-0.12, 0.12) + xf.basis.z * rng.randf_range(-0.12, 0.12)
		var tm := TorusMesh.new()
		tm.inner_radius = 0.3
		tm.outer_radius = 0.58
		tm.rings = 20
		tm.ring_segments = 10
		var mi := MeshKit.mesh_instance(tm, rub)
		_course.add_child(mi)
		mi.global_transform = xf * Transform3D(Basis.from_scale(Vector3(1, 1.3, 1)).rotated(Vector3.RIGHT, rng.randf_range(-0.06, 0.06)), Vector3.ZERO)
	var body := StaticBody3D.new()
	body.collision_layer = Colliders.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.6
	shape.height = h * count
	cs.shape = shape
	body.add_child(cs)
	_course.add_child(body)
	body.global_transform = _road_xf(id, along, lateral, 0.0, h * count * 0.5)


## A kicker of weathered planks on a log, skewed by `yaw`.
func _ramp(id: String, along: float, lateral: float, yaw: float, rl: float, rh: float, rw: float, rng: RandomNumberGenerator) -> void:
	var ang := atan2(rh, rl)
	var size := Vector3(rw, 0.18, Vector2(rl, rh).length())
	# yaw 0 = the ramp faces up the stretch (the +pitch raises the forward end, like _block)
	var xf := _road_xf(id, along, lateral, yaw, rh * 0.5 - 0.05) * Transform3D(Basis.from_euler(Vector3(ang, 0, 0)), Vector3.ZERO)
	var mi := MeshKit.box_node(size, TexKit.plank_material())
	_course.add_child(mi)
	mi.global_transform = xf
	Colliders.add_box(_course, xf, size)
	# the log it rests on (visual, squashed to fit under the high end)
	var mats: Array = TexKit.log_materials()
	var prop := MeshKit.mesh_instance(_log_mesh(0.2, rw + 0.6, rng, mats), null)
	_course.add_child(prop)
	prop.global_transform = _road_xf(id, along, lateral, yaw, 0.0) * Transform3D(Basis.IDENTITY, Vector3(0, (rh - 0.1) * 0.5, -rl * 0.5 + 0.4)) * Transform3D(Basis.from_scale(Vector3(1, (rh - 0.1) * 2.5, 1)), Vector3.ZERO)


## A boulder at the roadside.
func _rock(id: String, along: float, lateral: float, r: float, rng: RandomNumberGenerator) -> void:
	var xf := _road_xf(id, along, lateral, rng.randf_range(0.0, TAU), r * 0.35)
	var mi := MeshKit.sphere_node(r, TexKit.rock_material(), Vector3.ZERO, Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(0.6, 0.85), rng.randf_range(0.9, 1.2)))
	_course.add_child(mi)
	mi.global_transform = xf * Transform3D(Basis.from_scale(mi.scale), Vector3.ZERO)
	var body := StaticBody3D.new()
	body.collision_layer = Colliders.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = r * 0.85
	cs.shape = shape
	body.add_child(cs)
	_course.add_child(body)
	body.global_transform = xf


## A ragged mud patch flat on the road; remembered for the grip (mud_spots: [centre, radius]).
func _mud_patch(id: String, along: float, lateral: float, r: float, rng: RandomNumberGenerator, n: int) -> void:
	var hw: float = track.half_w
	lateral = clampf(lateral, -hw + r * 0.5, hw - r * 0.5)
	var xf := _road_xf(id, along, lateral, rng.randf_range(0.0, TAU), 0.012 + 0.002 * (n % 4))
	var segs := 30
	var ph := rng.randf_range(0.0, TAU)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sx := rng.randf_range(0.7, 1.0)
	var pts: Array = []
	for j in segs + 1:
		var ang := float(j) / segs * TAU
		var f := 1.0 + 0.18 * sin(ang * 2.0 + ph) + 0.1 * sin(ang * 5.0 + ph * 3.0)
		pts.append(Vector3(cos(ang) * r * f * sx, 0, sin(ang) * r * f * 1.25))
	for j in segs:
		# clockwise seen from above = front face up (the edge vertices carry alpha 0: the fade)
		var a: Vector3 = pts[j]
		var b: Vector3 = pts[j + 1]
		var tri: Array = [[Vector3.ZERO, 1.0], [a, 0.0], [b, 0.0]]
		if (a - Vector3.ZERO).cross(b - Vector3.ZERO).dot(Vector3.UP) > 0.0:
			tri = [[Vector3.ZERO, 1.0], [b, 0.0], [a, 0.0]]
		for v in tri:
			st.set_normal(Vector3.UP)
			st.set_color(Color(1, 1, 1, v[1]))
			st.add_vertex(v[0])
	var mesh := st.commit()
	var mi := MeshKit.mesh_instance(mesh, TexKit.mud_material(), false)
	_course.add_child(mi)
	mi.global_transform = xf
	mud_spots.append([xf.origin, r * 0.75])


## True when p is in one of the mud patches of the current course.
func in_mud(p: Vector3) -> bool:
	for m in mud_spots:
		var c: Vector3 = m[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(m[1]):
			return true
	return false


func _build_koth() -> void:
	var zm := CylinderMesh.new()
	zm.top_radius = KOTH_ZONE_R
	zm.bottom_radius = KOTH_ZONE_R
	zm.height = 3.0
	zm.cap_top = false
	zm.cap_bottom = false
	zm.radial_segments = 40
	var zmat := StandardMaterial3D.new()
	zmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	zmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	zmat.albedo_color = Color(1.0, 0.8, 0.1, 0.35)
	koth_zone = Node3D.new()
	_course.add_child(koth_zone)
	var wall := MeshKit.mesh_instance(zm, zmat, false)
	wall.position = Vector3(0, 1.5, 0)
	koth_zone.add_child(wall)
	var disc := CylinderMesh.new()
	disc.top_radius = KOTH_ZONE_R
	disc.bottom_radius = KOTH_ZONE_R
	disc.height = 0.02
	disc.radial_segments = 40
	var dmi := MeshKit.mesh_instance(disc, _mat(Color(1.0, 0.75, 0.1), 0.5, 1.5), false)
	dmi.position = Vector3(0, float(track.ROAD_Y) + 0.015, 0)
	koth_zone.add_child(dmi)
	var len: float = sites["koth"]["len"]
	_gantry("koth", -4.0, "KÖNIG DER ZONE", Color(1.0, 0.85, 0.2))
	_gantry("koth", len + 4.0, "KÖNIG DER ZONE", Color(1.0, 0.85, 0.2))
	place_zone(koth_spot(0, 0))


## Moves the zone to a spot (along, lateral) of the koth stretch.
func place_zone(spot: Vector2) -> void:
	if koth_zone:
		koth_zone.global_transform = course_xf("koth", spot.x, spot.y, 0.0)


func _build_donut() -> void:
	var ring_m := _mat(Color(1.0, 0.3, 0.7), 0.5, 1.0)
	for slot in 8:
		var xf := course_xf("donut", donut_along(slot), 0.0, float(track.ROAD_Y) + 0.012)
		var tm := TorusMesh.new()
		tm.inner_radius = 3.6
		tm.outer_radius = 3.9
		tm.rings = 40
		var ring := MeshKit.mesh_instance(tm, ring_m, false)
		_course.add_child(ring)
		ring.global_transform = xf * Transform3D(Basis.from_scale(Vector3(1, 0.05, 1)), Vector3.ZERO)
	_gantry("donut", -4.0, "DONUT-DUELL", Color(1.0, 0.4, 0.8))


# ---------------------------------------------------------------------------
# Auto-Bowling
# ---------------------------------------------------------------------------
func bowl_pins_along() -> float:
	return float(sites["bowling"]["len"]) * 0.72


func bowl_foul() -> float:
	return bowl_pins_along() - 16.0


func _build_bowling() -> void:
	var id := "bowling"
	var hw: float = track.half_w
	_line(id, BOWL_START)
	var lane := _mat(Color(0.95, 0.55, 0.1), 0.6, 0.4)
	# lane arrows and the foul line
	for m in 5:
		var lat := (m - 2) * minf(hw * 0.3, 1.8)
		_paint(id, bowl_foul() - 14.0 + absf(m - 2) * 1.6, lat, Vector2(0.5, 2.2), lane)
	_paint(id, bowl_foul(), 0.0, Vector2(hw * 2.0 - 0.4, 0.35), _mat(Color(1.0, 0.15, 0.1), 0.6, 0.8))
	# pin deck
	_paint(id, bowl_pins_along() - 1.5, 0.0, Vector2(minf(hw * 2.0 - 0.4, 9.0), 10.0), _mat(Color(0.75, 0.6, 0.4), 0.4))
	_gantry(id, float(sites[id]["len"]) + 2.0, "AUTO-BOWLING", Color(1.0, 0.6, 0.2))


## The ten pins, set up in their triangle (head pin nearest to the cars). Each machine has its own:
## they touch the world, the local car and each other only (other players drive through them).
func make_pins() -> Array:
	if pin_mesh == null:
		var st := MeshKit.new_st()
		var white := Color(0.95, 0.95, 0.93)
		var red := Color(0.8, 0.05, 0.05)
		var prof := [Vector2(0.0, 0.001), Vector2(0.02, 0.24), Vector2(0.3, 0.36), Vector2(0.55, 0.39), Vector2(0.85, 0.31),
			Vector2(1.08, 0.18)]
		MeshKit.lathe(st, prof, 20, white)
		MeshKit.lathe(st, [Vector2(1.08, 0.18), Vector2(1.18, 0.165), Vector2(1.3, 0.17)], 20, red)
		MeshKit.lathe(st, [Vector2(1.3, 0.17), Vector2(1.5, 0.225), Vector2(1.68, 0.2), Vector2(1.77, 0.11), Vector2(1.8, 0.001)], 20, white)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.25
		m.clearcoat_enabled = true
		pin_mesh = MeshKit.commit(st, m)
	var out: Array = []
	var gap := 1.55
	var i := 0
	for row in 4:
		for c in row + 1:
			var along := bowl_pins_along() + row * gap * 0.87
			var lat := (c - row * 0.5) * gap
			var pin := RigidBody3D.new()
			pin.mass = 7.0
			pin.collision_layer = 8     # props
			pin.collision_mask = 1 | 2 | 8
			pin.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			pin.center_of_mass = Vector3(0, 0.55, 0)
			var pm := PhysicsMaterial.new()
			pm.bounce = 0.35
			pm.friction = 0.5
			pin.physics_material_override = pm
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = 0.33
			sh.height = 1.8
			cs.shape = sh
			cs.position = Vector3(0, 0.9, 0)
			pin.add_child(cs)
			var mi := MeshKit.mesh_instance(pin_mesh, null)
			mi.rotation = Vector3(0, 0, PI * 0.5)
			pin.add_child(mi)
			_course.add_child(pin)
			pin.global_transform = _road_xf("bowling", along, lat, 0.0, 0.01)
			pin.set_meta("home", pin.global_transform)
			out.append(pin)
			i += 1
	return out


## Pins knocked over (tilted or pushed off their spot).
static func pins_down(pins: Array) -> int:
	var n := 0
	for p in pins:
		if not is_instance_valid(p):
			n += 1
			continue
		var home: Transform3D = (p as Node3D).get_meta("home")
		var xf: Transform3D = (p as Node3D).global_transform
		if xf.basis.y.dot(home.basis.y) < 0.8 or Vector2(xf.origin.x - home.origin.x, xf.origin.z - home.origin.z).length() > 0.9 or xf.origin.y < home.origin.y - 3.0:
			n += 1
	return n


static func reset_pins(pins: Array) -> void:
	for p in pins:
		if is_instance_valid(p):
			var b := p as RigidBody3D
			b.global_transform = b.get_meta("home")
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
			b.sleeping = false


# ---------------------------------------------------------------------------
# Arena (shoot-out)
# ---------------------------------------------------------------------------
func arena_len() -> float:
	return float(sites["arena"]["len"])


## Spawn spot `slot` (0..7) in the arena: spread over its length, alternating sides, facing inwards.
func arena_spawn(slot: int) -> Transform3D:
	var l := arena_len()
	var hw: float = track.half_w
	var s := slot % 8
	var along := lerpf(ARENA_WALL + 8.0, l - ARENA_WALL - 8.0, float(s % 4) / 3.0)
	var lat := (-1.0 if s % 2 == 0 else 1.0) * (hw - 2.6) * (1.0 if s < 4 else 0.3)
	var xf := course_xf("arena", along, lat, 0.6)
	if along > l * 0.5:
		xf.basis = xf.basis.rotated(xf.basis.y.normalized(), PI)
	return xf


## Spot k of the power-up coins (the same on every machine for the same seed).
func arena_pickup(seed_v: int, k: int) -> Transform3D:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_v, "pu", k])
	var hw: float = track.half_w
	return course_xf("arena", r.randf_range(ARENA_WALL + 6.0, arena_len() - ARENA_WALL - 6.0), r.randf_range(-1.0, 1.0) * (hw - 2.0), 1.2)


func _build_arena() -> void:
	var id := "arena"
	var hw: float = track.half_w
	var l := arena_len()
	var concrete := TexKit.std(Color(0.62, 0.62, 0.6), 0.9)
	var stripe := _mat(Color(1.0, 0.25, 0.1), 0.6, 0.6)
	var dark := _mat(Color(0.12, 0.12, 0.14), 0.7)
	# walls all round: across both ends and along both edges (following the road)
	for end: float in [ARENA_WALL, l - ARENA_WALL]:
		_block(id, end, 0.0, Vector3(hw * 2.0 + 1.6, 1.6, 0.8), concrete, 0.0, 0.8)
		_block(id, end, 0.0, Vector3(hw * 2.0 + 1.62, 0.3, 0.82), stripe, 0.0, 1.45)
	var seg := 4.0
	var a := ARENA_WALL
	while a < l - ARENA_WALL:
		for side: float in [-1.0, 1.0]:
			_block(id, a + seg * 0.5, side * (hw + 0.4), Vector3(0.8, 1.3, seg + 0.3), concrete, 0.0, 0.65)
			_block(id, a + seg * 0.5, side * (hw + 0.4), Vector3(0.82, 0.22, seg + 0.32), stripe if int(a / seg) % 2 == 0 else dark, 0.0, 1.2)
		a += seg
	# cover: container-sized blocks and barrier rows scattered in the middle
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["arena", int(sites[id]["i0"])])
	var n := int(clampf(l / 22.0, 3.0, 6.0))
	var cols := [Color(0.55, 0.12, 0.08), Color(0.1, 0.3, 0.55), Color(0.2, 0.45, 0.2), Color(0.7, 0.5, 0.1)]
	for m in n:
		var along := lerpf(ARENA_WALL + 16.0, l - ARENA_WALL - 16.0, (m + rng.randf_range(0.3, 0.7)) / n)
		var lat := (-1.0 if m % 2 == 0 else 1.0) * rng.randf_range(0.0, 0.45) * hw
		var yaw := rng.randf_range(-0.6, 0.6)
		var size := Vector3(rng.randf_range(2.4, 3.2), rng.randf_range(1.6, 2.6), rng.randf_range(3.5, 6.0))
		var xf := _road_xf(id, along, lat, yaw, size.y * 0.5)
		var mi := MeshKit.box_node(size, TexKit.container_material(cols[m % cols.size()]))
		_course.add_child(mi)
		mi.global_transform = xf
		Colliders.add_box(_course, xf, size)
	_gantry(id, ARENA_WALL - 3.0, "ARENA", Color(1.0, 0.3, 0.2))
	# floor markings: a big ring in the middle
	var ring := TorusMesh.new()
	ring.inner_radius = minf(hw - 1.5, 7.0)
	ring.outer_radius = ring.inner_radius + 0.5
	ring.rings = 48
	var rmi := MeshKit.mesh_instance(ring, _mat(Color(1.0, 0.3, 0.15), 0.6, 0.8), false)
	_course.add_child(rmi)
	rmi.global_transform = course_xf(id, l * 0.5, 0.0, float(track.ROAD_Y) + 0.012) * Transform3D(Basis.from_scale(Vector3(1, 0.04, 1)), Vector3.ZERO)
