extends RefCounted
## Roads drawn in the world editor: a smooth curve (Catmull-Rom) through the clicked points, a
## ribbon of the chosen width and surface laid on the ground (or the ground levelled under it),
## kerb-free edges, solid to drive on. It always lies on the ground: a height above 0 makes it
## that thick (sides down into the ground), below 0 sinks it into a dug-out bed.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const SURFACES := [["asphalt", "Asphalt"], ["concrete", "Beton"], ["gravel", "Schotter"], ["dirt", "Erde"]]
const STEP := 2.0
const LIFT := 0.08

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
	var h := float(r.get("height", 0.0))
	if h < -0.01:
		# sunk: the smoothed ground line minus the depth, the ground dug out under it
		var ys := PackedFloat32Array()
		for p in line:
			ys.append(float(terrain.height_at(p.x, p.z)))
		for _it in 4:
			var ys2 := ys.duplicate()
			for i in range(1, ys.size() - 1):
				ys2[i] = (ys[i - 1] + ys[i] * 2.0 + ys[i + 1]) * 0.25
			ys = ys2
		for i in line.size():
			line[i] = Vector3(line[i].x, ys[i] + h, line[i].z)
		if flatten_ground:
			_level_under(terrain, line, w * 0.5 + 0.8, 5.0)
		flatten_ground = true      # (the surface follows the line, not the ground)
	elif flatten_ground:
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
		_level_under(terrain, line, w * 0.5 + 0.8, 5.0)
	# a positive height is the road's thickness: the surface lies that far above the ground right
	# under it, the sides go down into the ground – a solid layer, never a gap underneath
	var thick := maxf(h, 0.0)
	var lift := LIFT + float(r.get("lift", 0.0))
	# across the road every ~1 m, so a laid road follows the ground between its edges too
	var across := maxi(int(ceil(w / 1.0)), 1)
	var st := MeshKit.new_st()
	var sides := MeshKit.new_st()
	var v := 0.0
	for i in line.size() - 1:
		var a: Vector3 = line[i]
		var b: Vector3 = line[i + 1]
		var da := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)])
		var db := (line[mini(i + 2, line.size() - 1)] - line[i])
		var na := Vector3(-da.z, 0, da.x).normalized()
		var nb := Vector3(-db.z, 0, db.x).normalized()
		var l := a.distance_to(b)
		var row_a: Array = []
		var row_b: Array = []
		for k in across + 1:
			var f := float(k) / across - 0.5
			row_a.append(_surface_pt(terrain, a + na * w * f, flatten_ground, thick, lift))
			row_b.append(_surface_pt(terrain, b + nb * w * f, flatten_ground, thick, lift))
		for k in across:
			var u0 := lerpf(0.15, 0.85, float(k) / across)
			var u1 := lerpf(0.15, 0.85, float(k + 1) / across)
			MeshKit.quad(st, row_a[k], row_a[k + 1], row_b[k + 1], row_b[k], Vector3.UP, Vector2(u0, v), Vector2(u1, v), Vector2(u1, v + l), Vector2(u0, v + l))
		# the edges down into the ground
		for e in [[0, -1.0], [across, 1.0]]:
			var ta: Vector3 = row_a[e[0]]
			var tb: Vector3 = row_b[e[0]]
			var ga := Vector3(ta.x, float(terrain.height_at(ta.x, ta.z)) - 0.4, ta.z)
			var gb := Vector3(tb.x, float(terrain.height_at(tb.x, tb.z)) - 0.4, tb.z)
			# (always: no gap shows under an edge, even over a dip between two points)
			_both(sides, ta, tb, gb, ga, (na + nb).normalized() * float(e[1]))
		v += l
	var mesh := MeshKit.commit(st, material(str(r.get("surface", "asphalt")), world))
	MeshKit.commit(sides, material("concrete" if str(r.get("surface", "asphalt")) == "asphalt" else str(r.get("surface", "asphalt")), world), mesh)
	return mesh


## A point of the road surface: on the ground (or on the levelled bed's line height) plus the
## thickness – never above a gap.
static func _surface_pt(terrain, p: Vector3, on_line: bool, thick: float, lift: float) -> Vector3:
	var g := float(terrain.height_at(p.x, p.z))
	var y := p.y if on_line else g
	return Vector3(p.x, maxf(y, g) + thick + lift, p.z)


## A quad facing `n` (MeshKit turns it that way round).
static func _both(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	MeshKit.quad(st, a, b, c, d, n)


## Every ground vertex near the road takes the height of the nearest point of it (just under the
## surface), blending back into the ground over `falloff`.
static func _level_under(terrain, line: PackedVector3Array, half: float, falloff: float) -> void:
	var c: float = terrain.CELL
	var o: Vector2 = terrain.origin
	var nx: int = terrain.nx
	var nz: int = terrain.nz
	var reach := half + falloff
	var best := {}      # vertex index -> [distance, height]
	for i in line.size() - 1:
		var a := Vector2(line[i].x, line[i].z)
		var b := Vector2(line[i + 1].x, line[i + 1].z)
		var ix0 := maxi(int(floor((minf(a.x, b.x) - reach - o.x) / c)), 0)
		var iz0 := maxi(int(floor((minf(a.y, b.y) - reach - o.y) / c)), 0)
		var ix1 := mini(int(ceil((maxf(a.x, b.x) + reach - o.x) / c)), nx - 1)
		var iz1 := mini(int(ceil((maxf(a.y, b.y) + reach - o.y) / c)), nz - 1)
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 1e-6)
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var v := Vector2(o.x + ix * c, o.y + iz * c)
				var t := clampf((v - a).dot(ab) / l2, 0.0, 1.0)
				var d := v.distance_to(a + ab * t)
				if d > reach:
					continue
				var idx := iz * nx + ix
				var cur = best.get(idx)
				if cur == null or d < float(cur[0]):
					best[idx] = [d, lerpf(line[i].y, line[i + 1].y, t)]
	var hs: PackedFloat32Array = terrain.heights
	for idx in best:
		var e: Array = best[idx]
		var k := 1.0 - smoothstep(half, half + falloff, float(e[0]))
		hs[idx] = lerpf(hs[idx], float(e[1]) - 0.2, k)
	terrain.heights = hs


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
	if float(r.get("height", 0.0)) > 0.01:
		flat = false        # (a thick road lies on the ground as it is)
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
	# no grass growing through it
	if world.get("grass") and is_instance_valid(world.grass):
		var pts: Array = []
		for p in r["pts"]:
			pts.append(p if p is Vector3 else Vector3(p[0], p[1], p[2]))
		var line := centre_line(world, pts)
		var half := float(r.get("width", 10.0)) * 0.5
		var gid := [world.grass.add_clear_line(line, half)]      # (shared by both handlers)
		# taken out (deleted, undone) the grass grows back; put back in, it is cleared again
		body.tree_exiting.connect(func():
			if is_instance_valid(world.grass):
				world.grass.remove_clear_line(gid[0]))
		body.tree_entered.connect(func():
			if is_instance_valid(world.grass):
				world.grass.remove_clear_line(gid[0])
				gid[0] = world.grass.add_clear_line(line, half))
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
