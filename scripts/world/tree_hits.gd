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
	# the tree that falls: the same mesh, drawn by a one-instance MultiMesh (keeps its tint)
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
	# trunk and crown
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
	# cut just above the stump, tipped a little already so it goes over away from the car
	var axis := Vector3.UP.cross(dir).normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.RIGHT
	b.global_transform = Transform3D(Basis(axis, 0.08), xf.origin + Vector3(0, CUT, 0))
	b.linear_velocity = dir * spd * 0.12
	b.angular_velocity = axis * clampf(0.4 + spd * 0.03, 0.4, 1.4)
	_debris.append(b)
	_fallen.append(b)
	if _fallen.size() > MAX_FALLEN:
		var old = _fallen.pop_front()
		if is_instance_valid(old):
			(old as RigidBody3D).freeze = true
	# the stump
	if _stump_mat == null:
		_stump_mat = StandardMaterial3D.new()
		_stump_mat.albedo_color = Color(0.32, 0.24, 0.17)
		_stump_mat.roughness = 0.95
	var stump := MeshKit.cyl_node(r * 1.05, r * 1.15, CUT, _stump_mat, xf.origin + Vector3(0, CUT * 0.5, 0), Vector3.ZERO, 10)
	add_child(stump)
	var top := MeshKit.cyl_node(r * 0.95, r * 0.95, 0.02, TexKit.std(Color(0.78, 0.66, 0.48), 0.9), xf.origin + Vector3(0, CUT + 0.01, 0), Vector3.ZERO, 10)
	add_child(top)
	# the car takes the blow
	car.apply_central_impulse(-dir * car.mass * spd * clampf(0.12 + r * 0.25, 0.12, 0.3))
	Sfx.play(self, "pole_hit", 2.0, xf.origin + Vector3(0, 1.0, 0), randf_range(0.5, 0.6))
	stats["felled"] = int(stats.get("felled", 0)) + 1
