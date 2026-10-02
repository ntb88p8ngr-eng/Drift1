extends Node3D
## Neo Tokyo's street furniture that a car can knock over: streetlights, the concrete utility poles
## (with the little security light every one carries and the wires between them) and the fire
## hydrants. Drawn instanced (one MultiMesh per 96 m chunk and kind), solid for the cars (one static
## body, a cylinder each). A car that hits one fast enough snaps it off just above the foot – the
## stump stays – and the rest flies off as debris (debris.gd: it never pushes the car): a post is
## kicked at its base so the top swings back over the car, its light goes out (city_lights.gd skips
## dark emitters) and a pole's wires come down; a hydrant's top is thrown off and a fountain of
## water shoots up from the broken main for a minute.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Sfx = preload("res://scripts/util/sfx_kit.gd")
const Debris = preload("res://scripts/util/debris.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")

const CHUNK := 96.0
const HEIGHT := 8.4
const BREAK_Y := 0.35
const ARMS := [2.2, 3.4]       # streetlight arm lengths: narrow and wide streets
const POLE_H := 10.0           # utility pole
const POLE_BREAK := 0.5
const HYD_SCALE := 1.9
const HYD_BREAK := 0.08        # the hydrant snaps above its base flange (unscaled)
const CELL := 16.0             # hit-check grid
const RANGE := 520.0
const FOUNTAIN_TIME := 60.0
const MAX_FOUNTAINS := 6
## Per kind: collider [radius, height], how high up it breaks, mass of the part that flies off.
const KINDS := {
	"lamp0": [0.14, HEIGHT, BREAK_Y, 110.0], "lamp1": [0.14, HEIGHT, BREAK_Y, 110.0],
	"upole1": [0.18, POLE_H, POLE_BREAK, 160.0], "upole-1": [0.18, POLE_H, POLE_BREAK, 160.0],
	"hydrant": [0.24, 1.3, HYD_BREAK * HYD_SCALE, 35.0],
}

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
## {kind, xf: Transform3D at the foot, light: emitter index or -1, broken, shape, mm, slot,
##  spans: the wire spans hanging on it}
var poles: Array = []
var spans: Array = []          # [pole a, pole b, MultiMesh, slot]
var stats := {}
var _grid := {}
var _meshes := {}
var _lens_mat: ShaderMaterial
var _metal: StandardMaterial3D
var _paint: StandardMaterial3D
var _body: StaticBody3D
var _shapes := {}
var _debris: Array = []
var _fountains: Array = []     # [jet, splash, sound, time left]


## A streetlight at p, its arm reaching out over the road (towards `face`).
func add(p: Vector3, face: Vector3, hw: float) -> void:
	var arm := 0 if hw * 0.55 < 2.8 else 1
	var head := p + Vector3(0, HEIGHT - 0.27, 0) + face * float(ARMS[arm])
	var li := emitters.size()
	emitters.append([head - Vector3(0, 0.2, 0), Color(1.0, 0.9, 0.74), 22.0, 4.5, 1])
	poles.append({"kind": "lamp%d" % arm, "xf": Transform3D(Basis.looking_at(face, Vector3.UP), p), "light": li, "broken": false, "spans": []})


## A utility pole at p beside a street running along `along`; its security light hangs over the
## street (towards `inward`). Returns its index (for the wires).
func add_utility_pole(p: Vector3, along: Vector3, inward: Vector3) -> int:
	var basis := Basis.looking_at(along, Vector3.UP)
	var sgn := 1 if basis.x.dot(inward) >= 0.0 else -1
	var li := emitters.size()
	emitters.append([p + Vector3(0, 5.05, 0) + basis.x * (0.9 * sgn), Color(0.88, 0.95, 1.0), 13.0, 2.2, 1])
	poles.append({"kind": "upole%d" % sgn, "xf": Transform3D(basis, p), "light": li, "broken": false, "spans": []})
	return poles.size() - 1


## Sagging wires between utility poles a and b (they come down when either breaks).
func add_span(a: int, b: int) -> void:
	spans.append([a, b, null, -1])
	(poles[a]["spans"] as Array).append(spans.size() - 1)
	(poles[b]["spans"] as Array).append(spans.size() - 1)


func add_hydrant(p: Vector3, face: Vector3) -> void:
	poles.append({"kind": "hydrant", "xf": Transform3D(Basis.looking_at(face, Vector3.UP), p), "light": -1, "broken": false, "spans": []})


func build(p_world) -> void:
	world = p_world
	_make_meshes()
	_body = StaticBody3D.new()
	_body.name = "LampColliders"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	for kind in KINDS:
		var cyl := CylinderShape3D.new()
		cyl.radius = float(KINDS[kind][0])
		cyl.height = float(KINDS[kind][1])
		_shapes[kind] = cyl
	var kinds: Array = KINDS.keys()
	var chunks := {}
	for k in poles.size():
		var pl: Dictionary = poles[k]
		var o: Vector3 = (pl["xf"] as Transform3D).origin
		var cs := CollisionShape3D.new()
		cs.shape = _shapes[pl["kind"]]
		cs.position = o + Vector3(0, float(KINDS[pl["kind"]][1]) * 0.5, 0)
		_body.add_child(cs)
		pl["shape"] = cs
		var g := Vector2i(int(floor(o.x / CELL)), int(floor(o.z / CELL)))
		if not _grid.has(g):
			_grid[g] = []
		_grid[g].append(k)
		var key := Vector3i(int(floor(o.x / CHUNK)), int(floor(o.z / CHUNK)), kinds.find(pl["kind"]))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(k)
	for key: Vector3i in chunks:
		var ids: Array = chunks[key]
		var centre := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
		var kind: String = kinds[key.z]
		var mm := _multimesh(_meshes["full_" + kind], ids.size())
		for j in ids.size():
			var pl: Dictionary = poles[ids[j]]
			var xf: Transform3D = pl["xf"]
			if kind == "hydrant":
				xf = Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * HYD_SCALE), xf.origin)
			mm.set_instance_transform(j, Transform3D(xf.basis, xf.origin - centre))
			pl["mm"] = mm
			pl["slot"] = j
		_chunk_node(mm, centre, "%s_%d_%d" % [kind, key.x, key.y], 200.0 if kind == "hydrant" else RANGE)
	# the wires: one unit span stretched from pole to pole
	var wchunks := {}
	for si in spans.size():
		var a: Vector3 = (poles[spans[si][0]]["xf"] as Transform3D).origin
		var b: Vector3 = (poles[spans[si][1]]["xf"] as Transform3D).origin
		var m := (a + b) * 0.5
		var key := Vector2i(int(floor(m.x / CHUNK)), int(floor(m.z / CHUNK)))
		if not wchunks.has(key):
			wchunks[key] = []
		wchunks[key].append(si)
	for key: Vector2i in wchunks:
		var ids: Array = wchunks[key]
		var centre := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
		var mm := _multimesh(_meshes["wires"], ids.size())
		for j in ids.size():
			var sp: Array = spans[ids[j]]
			var a: Vector3 = (poles[sp[0]]["xf"] as Transform3D).origin
			var b: Vector3 = (poles[sp[1]]["xf"] as Transform3D).origin
			var d := b - a
			var x := Vector3(-d.z, 0, d.x).normalized()
			mm.set_instance_transform(j, Transform3D(Basis(x, Vector3.UP, d), a - centre))
			sp[2] = mm
			sp[3] = j
		_chunk_node(mm, centre, "wires_%d_%d" % [key.x, key.y], 360.0)
	for pl in poles:
		var nm: String = {"lamp0": "streetlights", "lamp1": "streetlights", "upole1": "utility_poles", "upole-1": "utility_poles"}.get(pl["kind"], "hydrants")
		stats[nm] = int(stats.get(nm, 0)) + 1
	stats["wire_spans"] = spans.size()


func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _chunk_node(mm: MultiMesh, centre: Vector3, label: String, range_m: float) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.position = centre
	mmi.visibility_range_end = range_m
	mmi.visibility_range_end_margin = 30.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)


func set_night(n: float) -> void:
	if _lens_mat:
		_lens_mat.set_shader_parameter("night", n)


func _physics_process(delta: float) -> void:
	if world == null or poles.is_empty():
		return
	Debris.calm(_debris)
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
					var r: float = KINDS[pl["kind"]][0]
					if absf(lp.x) < 1.0 + r and absf(lp.z) < 2.3 + r + reach and absf(lp.y) < 3.0:
						_break(k, rb, v)


func _process(delta: float) -> void:
	for k in range(_fountains.size() - 1, -1, -1):
		var f: Array = _fountains[k]
		f[3] = float(f[3]) - delta
		if float(f[3]) <= 0.0:
			(f[0] as GPUParticles3D).emitting = false
			(f[1] as GPUParticles3D).emitting = false
			var snd: AudioStreamPlayer3D = f[2]
			snd.volume_db -= delta * 20.0
			if float(f[3]) < -3.0:
				for nd in [f[0], f[1], f[2]]:
					(nd as Node).queue_free()
				_fountains.remove_at(k)


func _break(k: int, car: RigidBody3D, v: Vector3) -> void:
	var pl: Dictionary = poles[k]
	var kind: String = pl["kind"]
	pl["broken"] = true
	# off at once (deferred, the broken post spawned inside its own still solid foot for a step)
	(pl["shape"] as CollisionShape3D).disabled = true
	(pl["mm"] as MultiMesh).set_instance_transform(int(pl["slot"]), Transform3D(Basis.IDENTITY, Vector3(0, -500, 0)))
	if int(pl["light"]) >= 0:
		(emitters[int(pl["light"])] as Array)[3] = 0.0
	for si in pl["spans"]:
		var sp: Array = spans[si]
		if sp[2] != null:
			(sp[2] as MultiMesh).set_instance_transform(int(sp[3]), Transform3D(Basis.IDENTITY, Vector3(0, -500, 0)))
	var xf: Transform3D = pl["xf"]
	var spec: Array = KINDS[kind]
	var hydrant := kind == "hydrant"
	# the stump stays
	var stub := MeshInstance3D.new()
	stub.mesh = _meshes["stub_" + kind]
	add_child(stub)
	stub.global_transform = xf
	if hydrant:
		stub.scale = Vector3.ONE * HYD_SCALE
	# the rest snaps off
	var b := RigidBody3D.new()
	b.name = "BrokenLamp"
	b.mass = float(spec[3])
	Debris.make(b)
	b.add_collision_exception_with(_body)
	b.continuous_cd = true
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["upper_" + kind]
	b.add_child(mi)
	if hydrant:
		mi.scale = Vector3.ONE * HYD_SCALE
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.2
		cyl.height = 1.15
		cs.shape = cyl
		cs.position = Vector3(0, float(spec[2]) + 0.58, 0)
		b.add_child(cs)
	else:
		var h: float = spec[1]
		b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		b.center_of_mass = Vector3(0, h * 0.45, 0)
		var pole := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = float(spec[0]) - 0.02
		cyl.height = h - float(spec[2])
		pole.shape = cyl
		pole.position = Vector3(0, (h + float(spec[2])) * 0.5, 0)
		b.add_child(pole)
		var top := CollisionShape3D.new()
		var tb := BoxShape3D.new()
		if kind.begins_with("lamp"):
			var arm: float = ARMS[int(kind.substr(4))]
			tb.size = Vector3(0.5, 0.25, arm + 0.5)
			top.position = Vector3(0, HEIGHT - 0.15, -arm * 0.5)
		else:
			tb.size = Vector3(1.8, 1.1, 0.2)
			top.position = Vector3(0, 9.05, 0)
		top.shape = tb
		b.add_child(top)
	add_child(b)
	b.global_transform = xf
	_debris.append(b)
	var dir := Vector3(v.x, 0, v.z).normalized()
	var spd := minf(Vector2(v.x, v.z).length(), 30.0)
	# the motion set directly: an impulse on a body created this very step used the engine's
	# default mass (1 kg, no inertia) – the post flew off at 900 m/s and took the car with it
	if hydrant:
		b.linear_velocity = dir * spd * 0.6 + Vector3.UP * (3.0 + spd * 0.2)
		b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))
		_fountain(xf.origin + Vector3(0, float(spec[2]) + 0.05, 0))
		Sfx.play(self, "pole_hit", -6.0, xf.origin + Vector3(0, 0.5, 0), randf_range(1.3, 1.5))
	else:
		# kicked at its foot: the top swings back over the car
		b.linear_velocity = dir * spd * 0.5 + Vector3.UP * 2.0
		b.angular_velocity = Vector3(-dir.z, 0, dir.x) * clampf(spd * 0.2, 0.8, 3.0)
		Sfx.play(self, "pole_hit", 0.0, xf.origin + Vector3(0, 1.0, 0), randf_range(0.8, 0.95) if kind.begins_with("upole") else randf_range(0.9, 1.1))
	# the car feels it
	car.apply_central_impulse(-dir * car.mass * spd * (0.02 if hydrant else 0.05))
	stats["broken"] = int(stats.get("broken", 0)) + 1


## A jet of water from a broken hydrant: a tall spray falling back around it, a splash at its foot
## and the hiss, for a minute.
func _fountain(at: Vector3) -> void:
	if _fountains.size() >= MAX_FOUNTAINS:
		(_fountains[0] as Array)[3] = minf(float(_fountains[0][3]), 0.0)
	var water := StandardMaterial3D.new()
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	water.vertex_color_use_as_albedo = true
	water.albedo_color = Color(0.85, 0.92, 1.0, 0.7)
	water.roughness = 0.1
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	q.material = water
	var jet := _particles(320, 1.8, 6.0, 10.0, 13.0, ramp, q, AABB(Vector3(-5, -1, -5), Vector3(10, 11, 10)))
	(jet.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	(jet.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.06
	add_child(jet)
	jet.global_position = at
	var splash := _particles(120, 0.7, 75.0, 1.5, 3.5, ramp, q, AABB(Vector3(-4, -1, -4), Vector3(8, 4, 8)))
	var pm2 := splash.process_material as ParticleProcessMaterial
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm2.emission_ring_axis = Vector3.UP
	pm2.emission_ring_radius = 1.2
	pm2.emission_ring_inner_radius = 0.2
	pm2.emission_ring_height = 0.05
	add_child(splash)
	splash.global_position = Vector3(at.x, at.y - 0.1, at.z)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = Sfx.get_sound("hydrant_spray")
	snd.unit_size = 5.0
	snd.max_distance = 70.0
	snd.volume_db = -4.0
	add_child(snd)
	snd.global_position = at + Vector3(0, 1.5, 0)
	snd.play()
	_fountains.append([jet, splash, snd, FOUNTAIN_TIME])
	stats["fountains"] = int(stats.get("fountains", 0)) + 1


static func _particles(amount: int, life: float, spread: float, v0: float, v1: float, ramp: Texture2D, mesh: Mesh, box: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.color_ramp = ramp
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.visibility_aabb = box
	return p


# ---------------------------------------------------------------------------
# Meshes
# ---------------------------------------------------------------------------
func _make_meshes() -> void:
	_metal = StandardMaterial3D.new()
	_metal.vertex_color_use_as_albedo = true
	_metal.metallic = 0.55
	_metal.roughness = 0.45
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.roughness = 0.7
	_lens_mat = ShaderMaterial.new()
	_lens_mat.shader = Shader.new()
	_lens_mat.shader.code = LENS_SHADER
	var grey := Color(0.42, 0.43, 0.45)
	for arm in ARMS.size():
		_meshes["full_lamp%d" % arm] = _lamp_mesh(float(ARMS[arm]), 0.0)
		_meshes["upper_lamp%d" % arm] = _lamp_mesh(float(ARMS[arm]), BREAK_Y)
		_meshes["stub_lamp%d" % arm] = _stub(BREAK_Y, 0.16, grey, _metal)
	for sgn in [1, -1]:
		_meshes["full_upole%d" % sgn] = _pole_mesh(sgn, 0.0)
		_meshes["upper_upole%d" % sgn] = _pole_mesh(sgn, POLE_BREAK)
		_meshes["stub_upole%d" % sgn] = _stub(POLE_BREAK, 0.3, Color(0.6, 0.6, 0.58), _paint)
	_meshes["full_hydrant"] = _hydrant_mesh(0.0)
	_meshes["upper_hydrant"] = _hydrant_mesh(HYD_BREAK)
	var st := MeshKit.new_st()
	Props._cyl(st, Vector3.ZERO, Vector3(0, HYD_BREAK, 0), 0.14, 0.14, Color(0.8, 0.1, 0.08), 10)
	Props._cyl(st, Vector3(0, HYD_BREAK, 0), Vector3(0, HYD_BREAK + 0.04, 0), 0.07, 0.07, Color(0.2, 0.2, 0.22), 8)
	_meshes["stub_hydrant"] = MeshKit.commit(st, _paint)
	_meshes["wires"] = _wire_mesh()


## The stump: a short piece of the post with a torn edge.
func _stub(h: float, w: float, col: Color, mat: Material) -> ArrayMesh:
	var st := MeshKit.new_st()
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), Vector3(w * 2.2, 0.06, w * 2.2), col.darkened(0.3))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, w), col)
	MeshKit.box(st, Transform3D(Basis(Vector3(1, 0, 0), 0.5), Vector3(0.03, h + 0.05, 0.02)), Vector3(w * 0.6, 0.12, 0.03), col.darkened(0.15))
	MeshKit.box(st, Transform3D(Basis(Vector3(0, 0, 1), -0.6), Vector3(-0.04, h + 0.03, -0.03)), Vector3(0.03, 0.09, w * 0.6), col.darkened(0.15))
	return MeshKit.commit(st, mat)


## Streetlight: pole (from `from_y` up), arm out along -Z, the head and its glowing lens.
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


## Concrete utility pole (from `from_y` up): two crossarms across the street (the wires' ends), a
## transformer, the yellow plate, and the security light on an arm towards local ±X (sgn).
func _pole_mesh(sgn: int, from_y: float) -> ArrayMesh:
	var st := MeshKit.new_st()
	var conc := Color(0.6, 0.6, 0.58)
	Props._cyl(st, Vector3(0, from_y, 0), Vector3(0, POLE_H, 0), lerpf(0.16, 0.12, from_y / POLE_H), 0.12, conc, 8)
	for y: float in [8.6, 9.5]:
		Props._b(st, Vector3(0, y, 0), Vector3(1.8, 0.1, 0.1), Color(0.35, 0.35, 0.37))
	Props._cyl(st, Vector3(-0.3 * sgn, 6.8, 0), Vector3(-0.3 * sgn, 7.6, 0), 0.25, 0.25, Color(0.55, 0.57, 0.6), 8)
	Props._b(st, Vector3(0, 2.5, -0.17), Vector3(0.35, 1.2, 0.03), Color(0.95, 0.85, 0.2))
	# the security light's arm
	Props._b(st, Vector3(0.45 * sgn, 5.3, 0), Vector3(0.9, 0.06, 0.06), Color(0.4, 0.4, 0.42))
	Props._b(st, Vector3(0.9 * sgn, 5.24, 0), Vector3(0.5, 0.08, 0.22), Color(0.35, 0.35, 0.37))
	var mesh := MeshKit.commit(st, _paint)
	var lens := MeshKit.new_st()
	MeshKit.box(lens, Transform3D(Basis.IDENTITY, Vector3(0.9 * sgn, 5.19, 0)), Vector3(0.42, 0.03, 0.18), Color.WHITE)
	return MeshKit.commit(lens, _lens_mat, mesh)


## Japanese street hydrant (unscaled; drawn at HYD_SCALE), from `from_y` up.
func _hydrant_mesh(from_y: float) -> ArrayMesh:
	var st := MeshKit.new_st()
	var red := Color(0.8, 0.1, 0.08)
	if from_y <= 0.0:
		Props._cyl(st, Vector3(0, 0, 0), Vector3(0, 0.08, 0), 0.14, 0.14, red, 10)
	Props._cyl(st, Vector3(0, maxf(from_y, 0.08), 0), Vector3(0, 0.62, 0), 0.1, 0.1, red, 10)
	Props._cyl(st, Vector3(0, 0.62, 0), Vector3(0, 0.72, 0), 0.11, 0.06, red, 10)
	Props._cyl(st, Vector3(-0.17, 0.45, 0), Vector3(0.17, 0.45, 0), 0.045, 0.045, red, 8)
	return MeshKit.commit(st, _paint)


## Four wires of a span along +Z from 0 to 1 (stretched to the span by the instance), at the
## crossarms' ends, sagging 0.6 m in the middle: thin crossed ribbons (they stay thin stretched).
func _wire_mesh() -> ArrayMesh:
	var st := MeshKit.new_st()
	var col := Color(0.05, 0.05, 0.05)
	var up := Vector3(0, 0.015, 0)
	var sd := Vector3(0.015, 0, 0)
	for wy: float in [8.6, 9.5]:
		for wx: float in [-0.8, 0.8]:
			var segs := 8
			for s in segs:
				var u0 := float(s) / segs
				var u1 := float(s + 1) / segs
				var p0 := Vector3(wx, wy - sin(u0 * PI) * 0.6, u0)
				var p1 := Vector3(wx, wy - sin(u1 * PI) * 0.6, u1)
				MeshKit.quad(st, p0 - up, p1 - up, p1 + up, p0 + up, Vector3(1, 0, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
				MeshKit.quad(st, p0 - sd, p1 - sd, p1 + sd, p0 + sd, Vector3(0, 1, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.6
	return MeshKit.commit(st, mat)
