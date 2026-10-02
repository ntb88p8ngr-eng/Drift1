extends Node3D
## Neo Tokyo's streetlights as breakable objects. Drawn instanced (one MultiMesh per 96 m chunk),
## solid for the cars (one static body, a cylinder per pole). A car that hits one fast enough
## snaps it off just above the foot – the stump stays – and the rest is kicked away at its base so
## the top swings back onto the car. Its light goes out (city_lights.gd skips dark emitters).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Sfx = preload("res://scripts/util/sfx_kit.gd")

const CHUNK := 96.0
const HEIGHT := 8.4
const BREAK_Y := 0.35
const ARMS := [2.2, 3.4]       # arm lengths: narrow and wide streets
const CELL := 16.0             # hit-check grid
const RANGE := 520.0

const LENS_SHADER := """
shader_type spatial;
uniform float night = 0.0;
void fragment() {
	ALBEDO = vec3(0.9, 0.86, 0.78) * 0.6;
	ROUGHNESS = 0.3;
	EMISSION = vec3(1.0, 0.93, 0.8) * mix(0.05, 4.0, night);
}
"""

var emitters: Array            # the city's light emitters (shared array): a broken lamp's goes dark
var world
## {xf: Transform3D at the foot (-Z towards the road), arm: 0/1, light: emitter index, broken,
##  shape: CollisionShape3D, mm: MultiMesh, slot: int}
var poles: Array = []
var stats := {}
var _grid := {}
var _meshes := {}
var _lens_mat: ShaderMaterial
var _metal: StandardMaterial3D
var _body: StaticBody3D
var _shape: CylinderShape3D


## A streetlight at p, its arm reaching out over the road (towards `face`).
func add(p: Vector3, face: Vector3, hw: float) -> void:
	var arm := 0 if hw * 0.55 < 2.8 else 1
	var basis := Basis.looking_at(face, Vector3.UP)
	var head := p + Vector3(0, HEIGHT - 0.27, 0) + face * float(ARMS[arm])
	var li := emitters.size()
	emitters.append([head - Vector3(0, 0.2, 0), Color(1.0, 0.9, 0.74), 22.0, 4.5, 1])
	poles.append({"xf": Transform3D(basis, p), "arm": arm, "light": li, "broken": false})


func build(p_world) -> void:
	world = p_world
	_make_meshes()
	_body = StaticBody3D.new()
	_body.name = "LampColliders"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_shape = CylinderShape3D.new()
	_shape.radius = 0.14
	_shape.height = HEIGHT
	var chunks := {}
	for k in poles.size():
		var pl: Dictionary = poles[k]
		var o: Vector3 = (pl["xf"] as Transform3D).origin
		var cs := CollisionShape3D.new()
		cs.shape = _shape
		cs.position = o + Vector3(0, HEIGHT * 0.5, 0)
		_body.add_child(cs)
		pl["shape"] = cs
		var g := Vector2i(int(floor(o.x / CELL)), int(floor(o.z / CELL)))
		if not _grid.has(g):
			_grid[g] = []
		_grid[g].append(k)
		var key := Vector3i(int(floor(o.x / CHUNK)), int(floor(o.z / CHUNK)), int(pl["arm"]))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(k)
	for key: Vector3i in chunks:
		var ids: Array = chunks[key]
		var centre := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes["full%d" % key.z]
		mm.instance_count = ids.size()
		for j in ids.size():
			var pl: Dictionary = poles[ids[j]]
			var xf: Transform3D = pl["xf"]
			mm.set_instance_transform(j, Transform3D(xf.basis, xf.origin - centre))
			pl["mm"] = mm
			pl["slot"] = j
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Lamps_%d_%d_%d" % [key.x, key.y, key.z]
		mmi.multimesh = mm
		mmi.position = centre
		mmi.visibility_range_end = RANGE
		mmi.visibility_range_end_margin = 30.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	stats["streetlights"] = poles.size()


func set_night(n: float) -> void:
	if _lens_mat:
		_lens_mat.set_shader_parameter("night", n)


func _physics_process(delta: float) -> void:
	if world == null or poles.is_empty():
		return
	for car in world.cars.values():
		if not is_instance_valid(car) or not car.visible or not (car is RigidBody3D):
			continue
		var rb := car as RigidBody3D
		var v := rb.linear_velocity
		var sp := Vector2(v.x, v.z).length()
		if sp < 3.0:
			continue          # parking against it doesn't knock it over
		var cp := rb.global_position
		var inv := rb.global_transform.affine_inverse()
		var reach := sp * delta * 3.0 + 0.5
		var c := Vector2i(int(floor(cp.x / CELL)), int(floor(cp.z / CELL)))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for k in _grid.get(c + Vector2i(dx, dz), []):
					var pl: Dictionary = poles[k]
					if pl["broken"]:
						continue
					var lp: Vector3 = inv * (pl["xf"] as Transform3D).origin
					if absf(lp.x) < 1.2 and absf(lp.z) < 2.4 + reach and absf(lp.y) < 3.0:
						_break(k, rb, v)


func _break(k: int, car: RigidBody3D, v: Vector3) -> void:
	var pl: Dictionary = poles[k]
	pl["broken"] = true
	(pl["shape"] as CollisionShape3D).set_deferred("disabled", true)
	(pl["mm"] as MultiMesh).set_instance_transform(int(pl["slot"]), Transform3D(Basis.IDENTITY, Vector3(0, -500, 0)))
	(emitters[int(pl["light"])] as Array)[3] = 0.0
	var xf: Transform3D = pl["xf"]
	var arm: int = pl["arm"]
	# the stump stays
	var stub := MeshInstance3D.new()
	stub.mesh = _meshes["stub"]
	add_child(stub)
	stub.global_transform = xf
	# the rest snaps off: kicked at its foot, the top swings back over the car
	var b := RigidBody3D.new()
	b.name = "BrokenLamp"
	b.mass = 110.0
	b.collision_layer = 8
	b.collision_mask = 1 | 2 | 4 | 8
	b.continuous_cd = true
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	b.center_of_mass = Vector3(0, 3.6, -0.4)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["upper%d" % arm]
	b.add_child(mi)
	var pole := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.12
	cyl.height = HEIGHT - BREAK_Y
	pole.shape = cyl
	pole.position = Vector3(0, (HEIGHT + BREAK_Y) * 0.5, 0)
	b.add_child(pole)
	var top := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(0.5, 0.25, float(ARMS[arm]) + 0.5)
	top.shape = tb
	top.position = Vector3(0, HEIGHT - 0.15, -float(ARMS[arm]) * 0.5)
	b.add_child(top)
	add_child(b)
	b.global_transform = xf
	var dir := Vector3(v.x, 0, v.z).normalized()
	var spd := minf(Vector2(v.x, v.z).length(), 30.0)
	b.call_deferred("apply_impulse", dir * b.mass * spd * 0.55 + Vector3.UP * b.mass * 2.5, xf.basis * Vector3(0, 0.6, 0))
	b.call_deferred("apply_torque_impulse", Vector3(-dir.z, 0, dir.x) * b.mass * spd * 0.9)
	# the car feels it
	car.apply_central_impulse(-dir * car.mass * spd * 0.05)
	Sfx.play(self, "pole_hit", 0.0, xf.origin + Vector3(0, 1.0, 0), randf_range(0.9, 1.1))
	stats["broken"] = int(stats.get("broken", 0)) + 1


# ---------------------------------------------------------------------------
# Meshes
# ---------------------------------------------------------------------------
func _make_meshes() -> void:
	_metal = StandardMaterial3D.new()
	_metal.vertex_color_use_as_albedo = true
	_metal.metallic = 0.55
	_metal.roughness = 0.45
	_lens_mat = ShaderMaterial.new()
	_lens_mat.shader = Shader.new()
	_lens_mat.shader.code = LENS_SHADER
	for arm in ARMS.size():
		_meshes["full%d" % arm] = _lamp_mesh(float(ARMS[arm]), 0.0)
		_meshes["upper%d" % arm] = _lamp_mesh(float(ARMS[arm]), BREAK_Y)
	var st := MeshKit.new_st()
	var grey := Color(0.42, 0.43, 0.45)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), Vector3(0.36, 0.06, 0.36), grey.darkened(0.3))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, BREAK_Y * 0.5, 0)), Vector3(0.16, BREAK_Y, 0.16), grey)
	# the torn edge: a couple of bent bits of tube
	MeshKit.box(st, Transform3D(Basis(Vector3(1, 0, 0), 0.5), Vector3(0.03, BREAK_Y + 0.05, 0.02)), Vector3(0.1, 0.12, 0.03), grey.darkened(0.15))
	MeshKit.box(st, Transform3D(Basis(Vector3(0, 0, 1), -0.6), Vector3(-0.04, BREAK_Y + 0.03, -0.03)), Vector3(0.03, 0.09, 0.1), grey.darkened(0.15))
	_meshes["stub"] = MeshKit.commit(st, _metal)


## Pole (from `from_y` up), arm out along -Z, the head and its glowing lens.
func _lamp_mesh(arm: float, from_y: float) -> ArrayMesh:
	var st := MeshKit.new_st()
	var grey := Color(0.42, 0.43, 0.45)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, (HEIGHT + from_y) * 0.5, 0)), Vector3(0.16, HEIGHT - from_y, 0.16), grey)
	if from_y <= 0.0:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), Vector3(0.36, 0.06, 0.36), grey.darkened(0.3))
	else:
		MeshKit.box(st, Transform3D(Basis(Vector3(1, 0, 0), -0.5), Vector3(0.02, from_y + 0.02, 0.02)), Vector3(0.1, 0.1, 0.03), grey.darkened(0.15))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT - 0.1, -arm * 0.5)), Vector3(0.1, 0.1, arm), grey)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT - 0.15, -arm)), Vector3(0.45, 0.18, 0.9), grey.darkened(0.2))
	var mesh := MeshKit.commit(st, _metal)
	var lens := MeshKit.new_st()
	MeshKit.box(lens, Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT - 0.27, -arm)), Vector3(0.36, 0.04, 0.7), Color.WHITE)
	return MeshKit.commit(lens, _lens_mat, mesh)
