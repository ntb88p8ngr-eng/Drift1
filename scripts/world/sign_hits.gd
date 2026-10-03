extends Node3D
## Road signs can be knocked down: every sign board on its post(s) (details.gd – chevrons, curve
## warnings, speed limits, direction boards, bus stops) is drawn instanced; a car that hits one
## snaps it off – the instances vanish and the board flies off on its post as one loose body
## (debris: it never pushes the car).

const MMUtil = preload("res://scripts/util/mm_util.gd")
const Debris = preload("res://scripts/util/debris.gd")
const Sfx = preload("res://scripts/util/sfx_kit.gd")

const CELL := 8.0
const LABELS := ["Prop_sign", "Prop_post"]

var world
var stats := {}
## {foot: Vector3, top: float, width: float, parts: [[mm, idx, world xf, custom]], down}
var _signs: Array = []
var _by_key := {}
var _grid := {}
var _debris: Array = []


static func _key(o: Vector3) -> Vector3i:
	return Vector3i(int(round(o.x * 8.0)), int(round(o.y * 8.0)), int(round(o.z * 8.0)))


## A sign as placed: the board's and the posts' transforms (their instances are matched later).
func add_sign(board: Transform3D, posts: Array, foot: Vector3) -> void:
	var s := {"foot": foot, "top": board.origin.y - foot.y + board.basis.y.length() * 0.5,
		"width": board.basis.x.length(), "parts": [], "down": false}
	_signs.append(s)
	_by_key[_key(board.origin)] = s
	for p in posts:
		_by_key[_key((p as Transform3D).origin)] = s
	var g := Vector2i(int(floor(foot.x / CELL)), int(floor(foot.z / CELL)))
	if not _grid.has(g):
		_grid[g] = []
	_grid[g].append(s)
	stats["signs"] = int(stats.get("signs", 0)) + 1


## Called for every instanced set the scenery emits: links the board and post instances.
func register_set(label: String, mm: MultiMesh, items: Array) -> void:
	if not LABELS.has(label):
		return
	for idx in items.size():
		var xf: Transform3D = items[idx][0]
		var s = _by_key.get(_key(xf.origin))
		if s != null:
			(s["parts"] as Array).append([mm, idx, xf, items[idx][1]])


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
		if sp < 2.5:
			continue
		var cp := rb.global_position
		var inv := rb.global_transform.affine_inverse()
		var reach := sp * delta * 2.0
		var c := Vector2i(int(floor(cp.x / CELL)), int(floor(cp.z / CELL)))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for s in _grid.get(c + Vector2i(dx, dz), []):
					if s["down"] or (s["parts"] as Array).is_empty():
						continue
					var lp: Vector3 = inv * (s["foot"] as Vector3)
					var half_w: float = float(s["width"]) * 0.5
					if absf(lp.x) < 1.0 + half_w and absf(lp.z) < 2.3 + reach + 0.2 and lp.y > -3.0 and lp.y < 1.5:
						_break(s, rb, v)


func _break(s: Dictionary, car: RigidBody3D, v: Vector3) -> void:
	s["down"] = true
	var foot: Vector3 = s["foot"]
	var b := RigidBody3D.new()
	b.name = "BrokenSign"
	b.mass = 18.0 + float(s["width"]) * 10.0
	Debris.make(b)
	b.continuous_cd = true
	for part in s["parts"]:
		MMUtil.hide(part[0], int(part[1]))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = (part[0] as MultiMesh).mesh
		mm.instance_count = 1
		var xf: Transform3D = part[2]
		mm.set_instance_transform(0, Transform3D(xf.basis, xf.origin - foot))
		mm.set_instance_custom_data(0, part[3])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		b.add_child(mmi)
	var top: float = maxf(float(s["top"]), 1.0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(float(s["width"]), 0.3), top, 0.25)
	cs.shape = box
	cs.position = Vector3(0, top * 0.5, 0)
	b.add_child(cs)
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	b.center_of_mass = Vector3(0, top * 0.6, 0)
	add_child(b)
	b.global_transform = Transform3D(Basis.IDENTITY, foot + Vector3(0, 0.05, 0))
	var dir := Vector3(v.x, 0, v.z).normalized()
	var spd := minf(Vector2(v.x, v.z).length(), 30.0)
	# knocked at its foot: the board swings over and tumbles away
	b.linear_velocity = dir * spd * 0.7 + Vector3.UP * (1.5 + spd * 0.12)
	b.angular_velocity = Vector3(-dir.z, 0, dir.x) * clampf(spd * 0.25, 1.0, 5.0) + Vector3(0, randf_range(-2, 2), 0)
	_debris.append(b)
	car.apply_central_impulse(-dir * car.mass * spd * 0.01)
	Sfx.play(self, "pole_hit", -4.0, foot + Vector3(0, 1.0, 0), randf_range(1.4, 1.7))
	stats["broken"] = int(stats.get("broken", 0)) + 1
