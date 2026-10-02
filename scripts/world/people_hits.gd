extends Node3D
## People can be run over: every instanced person (city pedestrians, spectators, crowds, pit crews)
## is registered here with its MultiMesh slot. A car that runs into one fast enough knocks them
## apart into their blocks – shoes, legs, hips, arms, hands, torso, neck, head, hair – as small
## rigid bodies flying off with the car's momentum. The pieces lie around for a while, then shrink
## away (a cap on how many there are at once keeps the physics cheap).

const Sfx = preload("res://scripts/util/sfx_kit.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const Debris = preload("res://scripts/util/debris.gd")

const CELL := 8.0
## The blocks are debris (debris.gd): the car knocks them about, they never push the car.
const MAX_PIECES := 360
const PIECE_LIFE := 24.0
## The person mesh's blocks (crowd.gd person_mesh): [centre, size, part] – part: 0 pants,
## 1 shirt, 2 skin, 3 hair, 4 shoes.
const PARTS := [
	[Vector3(-0.1, 0.045, -0.03), Vector3(0.12, 0.09, 0.27), 4], [Vector3(0.1, 0.045, -0.03), Vector3(0.12, 0.09, 0.27), 4],
	[Vector3(-0.1, 0.5, 0), Vector3(0.14, 0.82, 0.16), 0], [Vector3(0.1, 0.5, 0), Vector3(0.14, 0.82, 0.16), 0],
	[Vector3(-0.27, 1.27, 0), Vector3(0.11, 0.34, 0.12), 1], [Vector3(0.27, 1.27, 0), Vector3(0.11, 0.34, 0.12), 1],
	[Vector3(-0.27, 0.95, 0), Vector3(0.09, 0.3, 0.1), 2], [Vector3(0.27, 0.95, 0), Vector3(0.09, 0.3, 0.1), 2],
	[Vector3(0, 0.95, 0), Vector3(0.36, 0.2, 0.2), 0], [Vector3(0, 1.22, 0), Vector3(0.42, 0.52, 0.24), 1],
	[Vector3(0, 1.51, 0), Vector3(0.1, 0.08, 0.1), 2], [Vector3(0, 1.64, -0.01), Vector3(0.19, 0.22, 0.21), 2],
	[Vector3(0, 1.765, 0.01), Vector3(0.2, 0.06, 0.22), 3]]

var world
var _grid := {}                 # Vector2i -> Array of entries [MultiMesh, index, Transform3D, custom, alive]
var _pieces: Array = []         # [RigidBody3D, age]
var _rng := RandomNumberGenerator.new()
var _box_meshes := {}
var _mats := {}
var stats := {}
## Parked cars: [MultiMesh, index, Transform3D, custom, kind, static body, awake] by grid cell.
var _cars := {}
var _awake: Array = []          # the parked cars that became bodies (speed-capped)


func _ready() -> void:
	_rng.seed = 3131


## One person drawn as instance `index` of `mm` at the world transform `xf`.
func register(mm: MultiMesh, index: int, xf: Transform3D, custom: Color) -> void:
	var o := xf.origin
	var key := Vector2i(int(floor(o.x / CELL)), int(floor(o.z / CELL)))
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append([mm, index, xf, custom, true])
	stats["people"] = int(stats.get("people", 0)) + 1


## A parked car drawn as instance `index` of `mm`, solid through `body`: becomes a real car body
## (it rolls and slides away, pushes back with its weight) when a car comes at it.
func register_car(mm: MultiMesh, index: int, xf: Transform3D, custom: Color, kind: String, body: Node3D) -> void:
	var o := xf.origin
	var key := Vector2i(int(floor(o.x / CELL)), int(floor(o.z / CELL)))
	if not _cars.has(key):
		_cars[key] = []
	_cars[key].append([mm, index, xf, custom, kind, body, false])
	stats["parked_cars"] = int(stats.get("parked_cars", 0)) + 1


func _wake_cars() -> void:
	for k in range(_awake.size() - 1, -1, -1):
		var b = _awake[k]
		if not is_instance_valid(b):
			_awake.remove_at(k)
			continue
		var rb := b as RigidBody3D
		if rb.linear_velocity.length_squared() > 30.0 * 30.0:
			rb.linear_velocity = rb.linear_velocity.normalized() * 30.0
	for car in world.cars.values():
		if not is_instance_valid(car) or not car.visible or not (car is RigidBody3D):
			continue
		var rb := car as RigidBody3D
		var sp := rb.linear_velocity.length()
		if sp < 1.5:
			continue
		var cp := rb.global_position
		var inv := rb.global_transform.affine_inverse()
		var c := Vector2i(int(floor(cp.x / CELL)), int(floor(cp.z / CELL)))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for e in _cars.get(c + Vector2i(dx, dz), []):
					if bool(e[6]):
						continue
					var lp: Vector3 = inv * (e[2] as Transform3D).origin
					if absf(lp.x) < 3.2 and absf(lp.z) < 4.6 + sp * 0.025 and absf(lp.y) < 2.5:
						_wake(e)


func _wake(e: Array) -> void:
	e[6] = true
	var mm: MultiMesh = e[0]
	mm.set_instance_transform(int(e[1]), Transform3D(Basis.IDENTITY, Vector3(0, -2000, 0)))
	var xf: Transform3D = e[2]
	var kind: String = e[4]
	var sz: Vector3 = Props.CAR_SIZES[kind]
	if is_instance_valid(e[5]):
		(e[5] as Node).queue_free()
	var b := RigidBody3D.new()
	b.name = "ParkedCar"
	b.mass = 1150.0
	b.collision_layer = 8
	b.collision_mask = 1 | 2 | 4 | 8 | 16
	b.continuous_cd = true
	b.angular_damp = 0.5
	b.linear_damp = 0.15
	# drawn the same way (the prop shader takes the paint from the instance data)
	var one := MultiMesh.new()
	one.transform_format = MultiMesh.TRANSFORM_3D
	one.use_custom_data = true
	one.mesh = mm.mesh
	one.instance_count = 1
	one.set_instance_transform(0, Transform3D.IDENTITY)
	one.set_instance_custom_data(0, e[3])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = one
	b.add_child(mmi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(sz.x, sz.y - 0.2, sz.z)
	cs.shape = bs
	cs.position = Vector3(0, sz.y * 0.5 + 0.1, 0)
	b.add_child(cs)
	add_child(b)
	b.global_transform = xf
	_awake.append(b)
	stats["cars_woken"] = int(stats.get("cars_woken", 0)) + 1


func _physics_process(delta: float) -> void:
	if world == null:
		return
	if not _cars.is_empty():
		_wake_cars()
	if _grid.is_empty():
		return
	for car in world.cars.values():
		if not is_instance_valid(car) or not car.visible or not (car is RigidBody3D):
			continue
		var rb := car as RigidBody3D
		var v := rb.linear_velocity
		var sp := v.length()
		if sp < 4.0:
			continue
		var cp := rb.global_position
		var inv := rb.global_transform.affine_inverse()
		var reach := sp * delta * 2.0 + 0.3
		var c := Vector2i(int(floor(cp.x / CELL)), int(floor(cp.z / CELL)))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for e in _grid.get(c + Vector2i(dx, dz), []):
					if not bool(e[4]):
						continue
					var lp: Vector3 = inv * (e[2] as Transform3D).origin
					if absf(lp.x) < 1.15 and absf(lp.z) < 2.45 + reach and lp.y > -2.2 and lp.y < 1.2:
						_burst(e, v)
	# the old pieces shrink away (and none ever flies off faster than a car throws it)
	for k in range(_pieces.size() - 1, -1, -1):
		var pc: Array = _pieces[k]
		pc[1] = float(pc[1]) + delta
		var body: RigidBody3D = pc[0]
		if not is_instance_valid(body):
			_pieces.remove_at(k)
			continue
		if body.linear_velocity.length_squared() > Debris.MAX_V * Debris.MAX_V:
			body.linear_velocity = body.linear_velocity.normalized() * Debris.MAX_V
		if float(pc[1]) > PIECE_LIFE:
			var s := 1.0 - (float(pc[1]) - PIECE_LIFE) / 1.5
			if s <= 0.0:
				body.queue_free()
				_pieces.remove_at(k)
			else:
				(body.get_child(0) as Node3D).scale = Vector3.ONE * s


func _burst(e: Array, v: Vector3) -> void:
	e[4] = false
	var mm: MultiMesh = e[0]
	mm.set_instance_transform(int(e[1]), Transform3D(Basis.IDENTITY, Vector3(0, -2000, 0)))
	var xf: Transform3D = e[2]
	var custom: Color = e[3]
	var shirt := Color(custom.r, custom.g, custom.b)
	var overall := custom.a > 1.5
	var cols := [
		shirt if overall else [Color(0.08, 0.1, 0.18), Color(0.3, 0.28, 0.25), Color(0.55, 0.5, 0.38)][_rng.randi() % 3],
		shirt,
		Color(0.95, 0.76, 0.62).lerp(Color(0.42, 0.27, 0.18), _rng.randf()),
		Color(0.05, 0.04, 0.03).lerp(Color(0.45, 0.32, 0.18), _rng.randf() * _rng.randf()),
		Color(0.05, 0.05, 0.05) if overall or _rng.randf() < 0.5 else Color(0.9, 0.9, 0.9)]
	var spd := minf(v.length(), 35.0)
	var dir := v / maxf(v.length(), 0.01)
	for part in PARTS:
		if _pieces.size() >= MAX_PIECES:
			var old: Array = _pieces.pop_front()
			if is_instance_valid(old[0]):
				(old[0] as Node).queue_free()
		var size: Vector3 = part[1]
		var b := RigidBody3D.new()
		b.mass = maxf(size.x * size.y * size.z * 900.0, 0.4)
		Debris.make(b)
		b.continuous_cd = true
		var mi := MeshInstance3D.new()
		mi.mesh = _box(size)
		mi.material_override = _mat(cols[int(part[2])])
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.global_transform = Transform3D(xf.basis.orthonormalized(), xf * (part[0] as Vector3))
		# thrown along with the car, up and apart
		var spread := Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0)) * spd * 0.25
		b.linear_velocity = dir * spd * _rng.randf_range(0.6, 1.05) + spread + Vector3.UP * (2.0 + spd * _rng.randf_range(0.12, 0.3))
		b.angular_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * (4.0 + spd * 0.4)
		_pieces.append([b, 0.0])
	Sfx.play(self, "body_hit", -2.0, xf.origin + Vector3(0, 1.0, 0), _rng.randf_range(0.9, 1.15))
	stats["run_over"] = int(stats.get("run_over", 0)) + 1


func _box(size: Vector3) -> BoxMesh:
	var key := size
	if not _box_meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_box_meshes[key] = bm
	return _box_meshes[key]


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html(false)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]
