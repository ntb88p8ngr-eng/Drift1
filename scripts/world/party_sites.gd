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
]
const RLGL_START := 10.0          # start line (m along)
const PK_START := 10.0
const KOTH_ZONE_R := 5.0
const DONUT_R := 16.0             # a donut counts within this distance of your spot

var track: Node3D
var sites := {}                   # id -> {"i0": start sample, "len": metres, "p0": race progress at the start}
var koth_zone: Node3D
var rlgl_lamps: Array = []        # [red material, green material]
var _course: Node3D


## Chooses the stretches. Always succeeds on a closed track.
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
	var k := clampf(float(track.length) * 0.9 / total, 0.45, 1.0)
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
			continue
		used.append([best, cnt])
		var p0 := fposmod(float(track.dists[best]) - float(track.start_dist), float(track.length))
		sites[id] = {"i0": best, "len": len, "p0": p0}
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


func clear_course() -> void:
	if _course:
		remove_child(_course)
		_course.free()
		_course = null
	koth_zone = null
	rlgl_lamps = []


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
	var wood := _mat(Color(0.55, 0.38, 0.2), 0.8)
	var tyre := _mat(Color(0.08, 0.08, 0.09), 0.9)
	var hazard := _mat(Color(1.0, 0.75, 0.05), 0.6, 0.3)
	var barrier := _mat(Color(0.92, 0.92, 0.94), 0.5)
	var mud := _mat(Color(0.33, 0.24, 0.15), 1.0)
	var k: float = float(sites[id]["len"]) / 210.0     # shorter on short tracks
	_line(id, PK_START)
	_line(id, pk_finish())
	_gantry(id, pk_finish() + 5.0, "OFFROAD-PARKOUR", Color(1.0, 0.7, 0.2))
	# mud patches: the whole stretch is dirt (grip set by the minigame)
	for m in 9:
		_paint(id, (20.0 + m * 20.0) * k, (m % 3 - 1) * hw * 0.4, Vector2(hw * 1.1, 9.0), mud)
	# 1) tyre-stack slalom
	for m in 5:
		var lat := (-1.0 if m % 2 == 0 else 1.0) * hw * 0.38
		_block(id, (22.0 + m * 9.0) * k, lat, Vector3(2.0, 1.6, 2.0), tyre, 0.0, 0.8)
	# 2) log bumps across the road
	for m in 6:
		_block(id, 70.0 * k + m * 3.5, 0.0, Vector3(hw * 2.0 - 0.6, 0.28, 0.45), wood, 0.0, 0.14)
	# 3) kicker ramps (take off, land on the road)
	for m in 2:
		var along := (100.0 + m * 22.0) * k
		var lat2 := (-1.0 if m == 0 else 1.0) * hw * 0.3
		var rl := 7.0
		var rh := 1.1
		var ang := atan2(rh, rl)
		_block(id, along, lat2, Vector3(hw * 1.1, 0.4, Vector2(rl, rh).length()), hazard, ang, rh * 0.5 - 0.15)
	# 4) chicane walls
	for m in 4:
		var side := -1.0 if m % 2 == 0 else 1.0
		_block(id, (150.0 + m * 10.0) * k, side * hw * 0.42, Vector3(hw * 1.16, 1.0, 0.7), barrier, 0.0, 0.5)
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
