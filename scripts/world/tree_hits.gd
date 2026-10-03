extends Node3D
## Every tree near the roads can be hit: drawn instanced (in several LOD MultiMeshes at once), a
## car arriving at its trunk fells it – the tree vanishes from every LOD set, a real copy of it
## topples over away from the car (debris: it never pushes the car back) and the stump stays. A car
## creeping into a trunk just stops against it.

const MMUtil = preload("res://scripts/util/mm_util.gd")
const Debris = preload("res://scripts/util/debris.gd")
const Sfx = preload("res://scripts/util/sfx_kit.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const CELL := 8.0
const FELL_SPEED := 6.0        # m/s: slower than this the trunk just stops the car
const MAX_FALLEN := 30
const CUT := 0.6              # above the tree's origin (which sits 0.3 m in the ground): the stump         # older fallen trees freeze where they lie
## Labels of the instanced sets that draw trees (all LODs of the forest, the city's street trees).
const MAIN := ["Trees_hi", "City_tree", "City_sakura"]
const OTHER := ["Trees_shadow", "Trees_mid", "Trees_far", "Trees_2d"]

var world
var terrain
var stats := {}
## key -> {xf, sets: [[mm, idx]], mesh, custom, r, h, down}
var _trees := {}
var _grid := {}
var _fallen: Array = []
var _debris: Array = []
var _stump_mat: StandardMaterial3D


static func _key(o: Vector3) -> Vector3i:
	return Vector3i(int(round(o.x * 8.0)), int(round(o.y * 8.0)), int(round(o.z * 8.0)))


## Called for every instanced set the scenery emits (items: [world Transform3D, custom Color]).
func register_set(label: String, mm: MultiMesh, items: Array) -> void:
	var main := MAIN.has(label)
	if not main and not OTHER.has(label):
		return
	var aabb: AABB = mm.mesh.get_aabb() if mm.mesh else AABB()
	for idx in items.size():
		var xf: Transform3D = items[idx][0]
		var k := _key(xf.origin)
		var t = _trees.get(k)
		if t == null:
			if not main:
				continue
			# the forest: only the trees a car can reach (the deep woods stay as they are)
			if label == "Trees_hi" and terrain != null and float(terrain.distance_to_road(xf.origin.x, xf.origin.z)) > 90.0:
				continue
			var sx := Vector2(xf.basis.x.x, xf.basis.x.z).length()
			t = {"xf": xf, "sets": [], "mesh": mm.mesh, "custom": items[idx][1],
				"r": clampf(0.28 * sx, 0.15, 0.6), "h": maxf(aabb.end.y * xf.basis.y.length(), 2.0), "down": false}
			_trees[k] = t
			var g := Vector2i(int(floor(xf.origin.x / CELL)), int(floor(xf.origin.z / CELL)))
			if not _grid.has(g):
				_grid[g] = []
			_grid[g].append(t)
			stats["trees"] = int(stats.get("trees", 0)) + 1
		(t["sets"] as Array).append([mm, idx])


func _physics_process(delta: float) -> void:
	if world == null or _grid.is_empty():
		return
	Debris.calm(_debris)
	for car in world.cars.values():
		if not is_instance_valid(car) or not car.visible or not (car is RigidBody3D):
			continue
		var rb := car as RigidBody3D
		var v := rb.linear_velocity
		var sp := Vector2(v.x, v.z).length()
		if sp < 0.5:
			continue
		var cp := rb.global_position
		var inv := rb.global_transform.affine_inverse()
		var reach := sp * delta * 2.0
		var c := Vector2i(int(floor(cp.x / CELL)), int(floor(cp.z / CELL)))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for t in _grid.get(c + Vector2i(dx, dz), []):
					if t["down"]:
						continue
					var o: Vector3 = (t["xf"] as Transform3D).origin
					var lp: Vector3 = inv * o
					var r: float = t["r"]
					if absf(lp.x) < 0.95 + r and absf(lp.z) < 2.2 + r + reach and lp.y > -3.5 and lp.y < 2.0:
						if sp >= FELL_SPEED:
							_fell(t, rb, v)
						else:
							# a trunk is a trunk: no further towards it
							var to := Vector3(o.x - cp.x, 0, o.z - cp.z).normalized()
							var into := v.dot(to)
							if into > 0.0:
								rb.linear_velocity = v - to * into * 1.3


func _fell(t: Dictionary, car: RigidBody3D, v: Vector3) -> void:
	t["down"] = true
	for s in t["sets"]:
		MMUtil.hide(s[0], int(s[1]))
	var xf: Transform3D = t["xf"]
	var h: float = t["h"]
	var r: float = t["r"]
	var dir := Vector3(v.x, 0, v.z).normalized()
	var spd := minf(Vector2(v.x, v.z).length(), 40.0)
	var axis := Vector3.UP.cross(dir).normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.RIGHT
	var pieces := _slices(t["mesh"])
	if pieces.is_empty():
		_fall_whole(t, dir, spd, axis)
	else:
		# the tree breaks: the lower trunk tips over, the upper trunk and the crown chunks fly apart
		var tip := Basis(axis, 0.08)
		var base := xf.origin + Vector3(0, CUT, 0)
		for k in pieces.size():
			var pc: Array = pieces[k]
			var box: AABB = pc[1]
			var centre_l := box.get_center()
			# the piece's centre in the world (the tree's scale and turn applied), from the cut
			var off: Vector3 = xf.basis * centre_l - Vector3(0, CUT, 0)
			var b := RigidBody3D.new()
			b.name = "TreePiece"
			var size: Vector3 = (xf.basis.get_scale() * box.size).abs()
			b.mass = clampf(size.x * size.y * size.z * (60.0 if k < 2 else 12.0), 8.0, 400.0)
			Debris.make(b)
			b.angular_damp = 0.8
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = pc[0]
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D(xf.basis, -(xf.basis * centre_l)))
			mm.set_instance_custom_data(0, t["custom"])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			b.add_child(mmi)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(maxf(size.x * 0.7, 0.3), maxf(size.y * 0.8, 0.3), maxf(size.z * 0.7, 0.3))
			cs.shape = shape
			b.add_child(cs)
			add_child(b)
			b.global_transform = Transform3D(tip, base + tip * off)
			# the higher the piece, the more it is thrown; crown chunks scatter sideways
			var up := centre_l.y / maxf(h / maxf(xf.basis.get_scale().y, 0.01), 1.0)
			var side := Vector3(off.x, 0, off.z).normalized() if Vector2(off.x, off.z).length() > 0.2 else Vector3.ZERO
			b.linear_velocity = dir * spd * (0.1 + 0.35 * up) + side * randf_range(0.5, 2.5) * up + Vector3.UP * randf_range(0.0, 2.0) * up
			b.angular_velocity = axis * clampf(0.4 + spd * 0.04, 0.4, 1.8) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * up * 1.5
			_debris.append(b)
			_fallen.append(b)
		while _fallen.size() > MAX_FALLEN * 4:
			var old = _fallen.pop_front()
			if is_instance_valid(old):
				(old as RigidBody3D).freeze = true
		stats["pieces"] = int(stats.get("pieces", 0)) + pieces.size()
	_stump(xf, r)
	# the car takes the blow
	car.apply_central_impulse(-dir * car.mass * spd * clampf(0.12 + r * 0.25, 0.12, 0.3))
	Sfx.play(self, "pole_hit", 2.0, xf.origin + Vector3(0, 1.0, 0), randf_range(0.5, 0.6))
	Sfx.play(self, "pole_hit", -4.0, xf.origin + Vector3(0, h * 0.5, 0), randf_range(1.2, 1.4))
	stats["felled"] = int(stats.get("felled", 0)) + 1


func _stump(xf: Transform3D, r: float) -> void:
	if _stump_mat == null:
		_stump_mat = StandardMaterial3D.new()
		_stump_mat.albedo_color = Color(0.32, 0.24, 0.17)
		_stump_mat.roughness = 0.95
	var stump := MeshKit.cyl_node(r * 1.05, r * 1.15, CUT, _stump_mat, xf.origin + Vector3(0, CUT * 0.5, 0), Vector3.ZERO, 10)
	add_child(stump)
	var top := MeshKit.cyl_node(r * 0.95, r * 0.95, 0.02, TexKit.std(Color(0.78, 0.66, 0.48), 0.9), xf.origin + Vector3(0, CUT + 0.01, 0), Vector3.ZERO, 10)
	add_child(top)


## The whole tree as one falling body (when its mesh can't be cut into pieces).
func _fall_whole(t: Dictionary, dir: Vector3, spd: float, axis: Vector3) -> void:
	var xf: Transform3D = t["xf"]
	var h: float = t["h"]
	var r: float = t["r"]
	var b := RigidBody3D.new()
	b.name = "FallingTree"
	b.mass = clampf(h * 40.0, 120.0, 900.0)
	Debris.make(b)
	b.angular_damp = 1.2
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	b.center_of_mass = Vector3(0, h * 0.4, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = t["mesh"]
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(xf.basis, Vector3(0, -CUT, 0)))
	mm.set_instance_custom_data(0, t["custom"])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	b.add_child(mmi)
	var trunk := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = maxf(h * 0.6, r * 2.0 + 0.1)
	trunk.shape = cap
	trunk.position = Vector3(0, h * 0.3, 0)
	b.add_child(trunk)
	var crown := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = clampf(h * 0.18, 0.6, 3.0)
	crown.shape = sph
	crown.position = Vector3(0, h * 0.7 - CUT, 0)
	b.add_child(crown)
	add_child(b)
	b.global_transform = Transform3D(Basis(axis, 0.08), xf.origin + Vector3(0, CUT, 0))
	b.linear_velocity = dir * spd * 0.12
	b.angular_velocity = axis * clampf(0.4 + spd * 0.03, 0.4, 1.4)
	_debris.append(b)
	_fallen.append(b)
	if _fallen.size() > MAX_FALLEN:
		var old = _fallen.pop_front()
		if is_instance_valid(old):
			(old as RigidBody3D).freeze = true


## A tree model cut into pieces (cached per mesh): lower trunk, middle, and the crown in four
## chunks round the stem – every triangle goes to the piece its centre lies in. [ArrayMesh, AABB].
static var _slice_cache := {}


static func _slices(mesh: Mesh) -> Array:
	if mesh == null:
		return []
	if _slice_cache.has(mesh):
		return _slice_cache[mesh]
	var out: Array = []
	var top := mesh.get_aabb().end.y
	if top <= 0.5 or not (mesh is ArrayMesh):
		_slice_cache[mesh] = out
		return out
	var parts: Array = []          # per piece: Array of [surface arrays dict, material]
	for k in 6:
		parts.append([])
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		var verts = arr[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or (verts as PackedVector3Array).is_empty():
			continue
		var vv: PackedVector3Array = verts
		var idx = arr[Mesh.ARRAY_INDEX]
		var ii: PackedInt32Array = idx if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0 else PackedInt32Array(range(vv.size()))
		var buckets: Array = []          # (plain Arrays: packed arrays would be filled as copies)
		for k in 6:
			buckets.append([])
		for q in range(0, ii.size() - 2, 3):
			var c := (vv[ii[q]] + vv[ii[q + 1]] + vv[ii[q + 2]]) / 3.0
			var piece := 0
			if c.y > top * 0.55:
				piece = 2 + (int(floor((atan2(c.z, c.x) + PI) / (PI * 0.5))) % 4)
			elif c.y > top * 0.3:
				piece = 1
			(buckets[piece] as Array).append_array([ii[q], ii[q + 1], ii[q + 2]])
		for k in 6:
			var tri := PackedInt32Array(buckets[k])
			if tri.is_empty():
				continue
			# only the vertices this piece uses, re-indexed
			var remap := {}
			var nv := PackedVector3Array()
			var nn := PackedVector3Array()
			var nuv := PackedVector2Array()
			var nc := PackedColorArray()
			var norms = arr[Mesh.ARRAY_NORMAL]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var cols = arr[Mesh.ARRAY_COLOR]
			var has_n: bool = norms is PackedVector3Array and (norms as PackedVector3Array).size() == vv.size()
			var has_uv: bool = uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == vv.size()
			var has_c: bool = cols is PackedColorArray and (cols as PackedColorArray).size() == vv.size()
			var ni := PackedInt32Array()
			ni.resize(tri.size())
			for q in tri.size():
				var o: int = tri[q]
				if not remap.has(o):
					remap[o] = nv.size()
					nv.append(vv[o])
					if has_n:
						nn.append(norms[o])
					if has_uv:
						nuv.append(uvs[o])
					if has_c:
						nc.append(cols[o])
				ni[q] = remap[o]
			var na := []
			na.resize(Mesh.ARRAY_MAX)
			na[Mesh.ARRAY_VERTEX] = nv
			if has_n:
				na[Mesh.ARRAY_NORMAL] = nn
			if has_uv:
				na[Mesh.ARRAY_TEX_UV] = nuv
			if has_c:
				na[Mesh.ARRAY_COLOR] = nc
			na[Mesh.ARRAY_INDEX] = ni
			(parts[k] as Array).append([na, mesh.surface_get_material(si)])
	for k in 6:
		if (parts[k] as Array).is_empty():
			continue
		var am := ArrayMesh.new()
		for sp in parts[k]:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sp[0])
			am.surface_set_material(am.get_surface_count() - 1, sp[1])
		out.append([am, am.get_aabb()])
	_slice_cache[mesh] = out
	return out
