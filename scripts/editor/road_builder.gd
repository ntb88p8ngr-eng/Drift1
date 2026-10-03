extends RefCounted
## Roads drawn in the world editor: a smooth curve (Catmull-Rom) through the clicked points, a
## ribbon of the chosen width and surface laid on the ground (or the ground levelled under it),
## kerb-free edges, solid to drive on.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const SURFACES := [["asphalt", "Asphalt"], ["concrete", "Beton"], ["gravel", "Schotter"], ["dirt", "Erde"]]
const STEP := 2.0
const LIFT := 0.06

static var _mats := {}


## The centre line: points every STEP metres along the curve through `pts` (on the ground).
static func centre_line(world, pts: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2:
		return out
	var n := pts.size()
	for i in n - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		var segs := maxi(int(p1.distance_to(p2) / STEP), 1)
		for k in segs:
			var t := float(k) / segs
			var t2 := t * t
			var t3 := t2 * t
			var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			out.append(p)
	out.append(pts[n - 1])
	return out


## The road's mesh (levelling the ground under it first when `flatten_ground`).
static func make_mesh(world, r: Dictionary, flatten_ground: bool) -> ArrayMesh:
	var pts: Array = []
	for p in r["pts"]:
		pts.append(p if p is Vector3 else Vector3(p[0], p[1], p[2]))
	var line := centre_line(world, pts)
	if line.size() < 2:
		return null
	var w: float = float(r.get("width", 10.0))
	var terrain = world.terrain
	if flatten_ground:
		# a smooth bed: the line's own height (smoothed), the ground levelled to it
		var ys := PackedFloat32Array()
		for p in line:
			ys.append(float(terrain.height_at(p.x, p.z)))
		for _it in 3:
			var ys2 := ys.duplicate()
			for i in range(1, ys.size() - 1):
				ys2[i] = (ys[i - 1] + ys[i] * 2.0 + ys[i + 1]) * 0.25
			ys = ys2
		for i in line.size():
			line[i] = Vector3(line[i].x, ys[i], line[i].z)
			terrain.level_to(line[i], w * 0.5 + 1.0, 4.0, ys[i] - 0.03)
	var st := MeshKit.new_st()
	var v := 0.0
	for i in line.size() - 1:
		var a: Vector3 = line[i]
		var b: Vector3 = line[i + 1]
		var da := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)])
		var db := (line[mini(i + 2, line.size() - 1)] - line[i])
		var na := Vector3(-da.z, 0, da.x).normalized()
		var nb := Vector3(-db.z, 0, db.x).normalized()
		var l := a.distance_to(b)
		var q := [a - na * w * 0.5, a + na * w * 0.5, b + nb * w * 0.5, b - nb * w * 0.5]
		for k in 4:
			var qp: Vector3 = q[k]
			var gy: float = qp.y if flatten_ground else float(terrain.height_at(qp.x, qp.z))
			q[k] = Vector3(qp.x, gy + LIFT, qp.z)
		MeshKit.quad(st, q[0], q[1], q[2], q[3], Vector3.UP, Vector2(0.15, v), Vector2(0.85, v), Vector2(0.85, v + l), Vector2(0.15, v + l))
		v += l
	return MeshKit.commit(st, material(str(r.get("surface", "asphalt")), world))


static func material(surface: String, world) -> Material:
	if surface == "asphalt" and world.track and world.track.road_material:
		return world.track.road_material
	if _mats.has(surface):
		return _mats[surface]
	var m: Material
	match surface:
		"concrete":
			m = TexKit.ground_material(Color(0.55, 0.55, 0.53), Color(0.6, 0.6, 0.58), Color(0.5, 0.5, 0.48), 0.85, 4.0)
		"gravel":
			m = TexKit.ground_material(Color(0.5, 0.47, 0.42), Color(0.42, 0.4, 0.36), Color(0.58, 0.55, 0.5), 0.95)
		"dirt":
			m = TexKit.ground_material(Color(0.33, 0.25, 0.16), Color(0.27, 0.2, 0.13), Color(0.38, 0.3, 0.2), 0.95)
		_:
			m = TexKit.road_material(Color(0.07, 0.07, 0.08))
	_mats[surface] = m
	return m


## The finished road in the world: mesh + a collider to drive on.
static func build(holder: Node3D, world, r: Dictionary) -> StaticBody3D:
	var flat := bool(r.get("flatten", false))
	var mesh := make_mesh(world, r, flat)
	if mesh == null:
		return null
	if flat:
		var t = world.terrain
		_rebuild_near(world, r)
		t.refresh_collision()
	var body := StaticBody3D.new()
	body.name = "Road"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("road", r)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	holder.add_child(body)
	return body


static func _rebuild_near(world, r: Dictionary) -> void:
	var t = world.terrain
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in r["pts"]:
		var v: Vector3 = p if p is Vector3 else Vector3(p[0], p[1], p[2])
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	var pad := float(r.get("width", 10.0)) + 10.0
	var o: Vector2 = t.origin
	var c: float = t.CELL
	t.rebuild_region(int((lo.x - pad - o.x) / c), int((lo.y - pad - o.y) / c), int((hi.x + pad - o.x) / c) + 1, int((hi.y + pad - o.y) / c) + 1)
