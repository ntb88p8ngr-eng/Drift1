extends Node3D
## Builds a closed circuit from control points: road ribbon, curbs, walls, start gantry and ground.
## Also answers spatial queries (progress along the lap, surface type, respawn points).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
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
		"points": [Vector2(0, 0), Vector2(73, -71), Vector2(134, -100), Vector2(176, -71), Vector2(190, 0), Vector2(176, 71),
			Vector2(134, 100), Vector2(73, 71), Vector2(0, 0), Vector2(-73, -71), Vector2(-134, -100), Vector2(-176, -71),
			Vector2(-190, 0), Vector2(-176, 71), Vector2(-134, 100), Vector2(-73, 71)],
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

var _grid := {}
var _edge: Dictionary = {}
var _puddle_index := {}     # sample index -> Array of puddle ids
var _start_lights: Array = []
var _lamp_lights: Array = []


func build(id: String) -> void:
	track_id = id if DEFS.has(id) else "ridge"
	def = DEFS[track_id]
	width = def["width"]
	half_w = width * 0.5
	wall_base = half_w + float(def["runoff"])
	trap_w = minf(4.6, float(def["runoff"]) - 0.4)
	_sample_centerline()
	_compute_offsets()
	_build_grid()
	_build_ground()
	_build_road()
	_build_puddles()
	_build_curbs()
	_build_walls()
	_build_start()


# ---------------------------------------------------------------------------
# Centerline
# ---------------------------------------------------------------------------
static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


func _sample_centerline() -> void:
	var pts: Array = []
	for p in def["points"]:
		pts.append(Vector3(p.x, 0.0, p.y))
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
	tangents.resize(count)
	rights.resize(count)
	curvature.resize(count)
	for i in count:
		var t: Vector3 = (samples[(i + 1) % count] - samples[(i - 1 + count) % count]).normalized()
		tangents[i] = t
		rights[i] = t.cross(Vector3.UP).normalized()
	for i in count:
		var tp: Vector3 = tangents[(i - 2 + count) % count]
		var tn: Vector3 = tangents[(i + 2) % count]
		curvature[i] = tp.signed_angle_to(tn, Vector3.UP) / (4.0 * step)
	start_index = int(round(float(def["start_dist"]) / step)) % count
	start_dist = dists[start_index]
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in samples:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.z)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.z)
	bounds = Rect2(mn, mx - mn)


func _compute_offsets() -> void:
	var n := samples.size()
	off_left.resize(n)
	off_right.resize(n)
	curb_mask.resize(n)
	var min_off := half_w + 1.0
	for i in n:
		var k := curvature[i]
		var l := wall_base
		var r := wall_base
		if absf(k) > 1e-4:
			var radius := 1.0 / absf(k)
			if k > 0.0:
				l = clampf(radius - 4.0, min_off, wall_base)
			else:
				r = clampf(radius - 4.0, min_off, wall_base)
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
	wb.plane = Plane(Vector3.UP, -45.0)
	shape.shape = wb
	body.add_child(shape)
	add_child(body)


func _build_road() -> void:
	var st := MeshKit.new_st()
	var n := samples.size()
	for i in n:
		var i2 := (i + 1) % n
		var d0 := dists[i]
		var d1 := dists[i2] if i2 != 0 else length
		var a := samples[i] - rights[i] * half_w + Vector3(0, ROAD_Y, 0)
		var b := samples[i] + rights[i] * half_w + Vector3(0, ROAD_Y, 0)
		var c := samples[i2] + rights[i2] * half_w + Vector3(0, ROAD_Y, 0)
		var d := samples[i2] - rights[i2] * half_w + Vector3(0, ROAD_Y, 0)
		MeshKit.quad(st, a, b, c, d, Vector3.UP, Vector2(0, d0), Vector2(1, d0), Vector2(1, d1), Vector2(0, d1))
	var mat := TexKit.road_material(def["asphalt"])
	road_material = mat
	var mesh := MeshKit.commit(st, mat, null, true)
	var mi := MeshKit.mesh_instance(mesh, null, false)
	mi.name = "Road"
	add_child(mi)


## Puddles in dips of the road surface (fixed per track so every player has the same ones).
func _build_puddles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track_id) + 991
	var n := samples.size()
	var count := int(length / 32.0)
	var noise := FastNoiseLite.new()
	noise.seed = rng.seed
	noise.frequency = 0.35
	var px := 0.5   # metres per texel
	var rect := bounds.grow(width + 4.0)
	var w := int(ceil(rect.size.x / px))
	var h := int(ceil(rect.size.y / px))
	var data := PackedByteArray()
	data.resize(w * h)
	data.fill(0)
	for k in count:
		var i := rng.randi_range(0, n - 1)
		var lateral := rng.randf_range(-half_w + 1.0, half_w - 1.0)
		var c: Vector3 = samples[i] + rights[i] * lateral
		var la := rng.randf_range(1.2, 3.6)
		var lc := rng.randf_range(0.7, 1.8)
		var ang := rng.randf_range(-0.5, 0.5)
		var t: Vector3 = tangents[i].rotated(Vector3.UP, ang)
		var r: Vector3 = t.cross(Vector3.UP).normalized()
		puddles.append({"c": c, "t": t, "r": r, "la": la, "lc": lc})
		var id := puddles.size() - 1
		var span := int(ceil(la / SPACING)) + 1
		for d in range(-span, span + 1):
			var si := (i + d + n) % n
			if not _puddle_index.has(si):
				_puddle_index[si] = []
			_puddle_index[si].append(id)
		# stamp a soft, noisy ellipse into the mask
		var reach := int(ceil((la + 0.5) / px))
		var cx := int((c.x - rect.position.x) / px)
		var cz := int((c.z - rect.position.y) / px)
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var gx := cx + dx
				var gz := cz + dz
				if gx < 0 or gz < 0 or gx >= w or gz >= h:
					continue
				var wp := Vector3(rect.position.x + (gx + 0.5) * px, 0.0, rect.position.y + (gz + 0.5) * px)
				var rel := wp - c
				var e := Vector2(rel.dot(t) / la, rel.dot(r) / lc).length()
				var v := clampf(1.0 - e + noise.get_noise_2d(wp.x, wp.z) * 0.3, 0.0, 1.0)
				var idx := gz * w + gx
				data[idx] = maxi(data[idx], int(v * 255.0))
	var tex := ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_L8, data))
	road_material.set_shader_parameter("puddle_tex", tex)
	road_material.set_shader_parameter("puddle_rect", Vector4(rect.position.x, rect.position.y, 1.0 / (w * px), 1.0 / (h * px)))


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
			var a: Vector3 = samples[i] + r0 * (half_w - 0.2) + y
			var b: Vector3 = samples[i] + r0 * (half_w + curb_w) + yo
			var c: Vector3 = samples[i2] + r1 * (half_w + curb_w) + yo
			var d: Vector3 = samples[i2] + r1 * (half_w - 0.2) + y
			MeshKit.quad(st, a, b, c, d, Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
			# outer lip down to the ground
			var e: Vector3 = samples[i] + r0 * (half_w + curb_w + 0.15)
			var f: Vector3 = samples[i2] + r1 * (half_w + curb_w + 0.15)
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
			var i2 := (i + 1) % n
			var r0: Vector3 = rights[i] * side
			var r1: Vector3 = rights[i2] * side
			var a: Vector3 = samples[i] + r0 * offs[i]
			var b: Vector3 = samples[i2] + r1 * offs[i2]
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
			var p: Vector3 = samples[i] + rights[i] * side * (offs[i] + 0.12) + Vector3(0, 0.42, 0)
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
	g.global_transform = Transform3D(Basis.looking_at(t, Vector3.UP), p)
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


## Distance from `pos` to the centerline, 1e9 when far away (> ~60 m).
func distance_to_center(pos: Vector3) -> float:
	var cx := int(floor(pos.x / CELL))
	var cz := int(floor(pos.z / CELL))
	var best_d := 1e18
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var key := Vector2i(cx + dx, cz + dz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				var s: Vector3 = samples[i]
				best_d = minf(best_d, Vector2(pos.x - s.x, pos.z - s.z).length_squared())
	return sqrt(best_d) if best_d < 1e17 else 1e9


## Distance to the road edge (R, 0..8 m) and gravel-trap weight (G) at 1 m resolution, shared by the
## terrain (gravel shoulder and traps) and the grass (kept off both).
## Returns {"tex": ImageTexture, "origin": Vector2, "inv_size": Vector2}.
func edge_data() -> Dictionary:
	if not _edge.is_empty():
		return _edge
	var b: Rect2 = bounds.grow(half_w + 12.0)
	var origin := b.position
	var w := int(ceil(b.size.x))
	var h := int(ceil(b.size.y))
	var best := PackedFloat32Array()
	best.resize(w * h)
	best.fill(1e9)
	var data := PackedByteArray()
	data.resize(w * h * 2)
	for k in w * h:
		data[k * 2] = 255
	var reach := int(ceil(half_w + 8.0))
	for i in samples.size():
		var s: Vector3 = samples[i]
		var r: Vector3 = rights[i]
		var tw := trap[i]
		var cx := int(s.x - origin.x)
		var cz := int(s.z - origin.y)
		for dz in range(-reach, reach + 1):
			var gz := cz + dz
			if gz < 0 or gz >= h:
				continue
			var wz := origin.y + gz + 0.5 - s.z
			for dx in range(-reach, reach + 1):
				var gx := cx + dx
				if gx < 0 or gx >= w:
					continue
				var wx := origin.x + gx + 0.5 - s.x
				var dd := wx * wx + wz * wz
				var k := gz * w + gx
				if dd >= best[k]:
					continue
				best[k] = dd
				var edge := sqrt(dd) - half_w
				data[k * 2] = int(clampf(edge / 8.0, 0.0, 1.0) * 255.0)
				var side := wx * r.x + wz * r.z
				var g := absf(tw) if tw * side > 0.0 else 0.0
				data[k * 2 + 1] = int(g * 255.0)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RG8, data)
	_edge = {"tex": ImageTexture.create_from_image(img), "origin": origin, "inv_size": Vector2(1.0 / w, 1.0 / h)}
	return _edge


## Grip multiplier & surface name at a world position, given the track index nearby.
func surface_at(pos: Vector3, idx: int) -> Array:
	var rel := pos - samples[idx]
	var side_d := rel.dot(rights[idx])
	var lat := absf(side_d)
	if lat <= half_w:
		var g := 1.0 - 0.18 * wetness
		var pd := puddle_at(pos, idx)
		if pd > 0.0:
			g *= 1.0 - 0.5 * pd
		return [g, "asphalt"]
	if curb_mask[idx] == 1 and lat <= half_w + 1.4:
		return [0.97 * (1.0 - 0.3 * wetness), "curb"]
	if trap.size() > idx and trap[idx] * side_d > 0.0 and absf(trap[idx]) > 0.4 and lat < half_w + trap_w:
		return [0.5 * (1.0 - 0.1 * wetness), "gravel"]
	return [float(def["offroad_grip"]) * (1.0 - 0.12 * wetness), str(def["ground"])]


func transform_at(idx: int, lateral := 0.0, height := 0.5) -> Transform3D:
	var n := samples.size()
	idx = (idx % n + n) % n
	var b := Basis.looking_at(tangents[idx], Vector3.UP)
	return Transform3D(b, samples[idx] + rights[idx] * lateral + Vector3(0, height, 0))


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
	for i in range(0, samples.size(), 3):
		pts.append(Vector2(samples[i].x, samples[i].z))
	return pts


func register_lamp_light(l: Light3D) -> void:
	_lamp_lights.append(l)
