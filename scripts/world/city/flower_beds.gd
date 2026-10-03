extends Node3D
## Flower beds in the parks and green corners of Neo Tokyo: dense clumps of flowers on dark soil.
## A car that drives through flattens every flower under it – they lie down in the direction it
## went and lose their colour – so a drift through a bed plows a visible track into it, with a puff
## of petals.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")

const SPACING := 0.32
const PALETTES := [
	[Color(0.95, 0.18, 0.25), Color(1.0, 0.55, 0.7), Color(0.98, 0.95, 0.92)],    # red, pink, white
	[Color(1.0, 0.82, 0.1), Color(1.0, 0.5, 0.08), Color(0.98, 0.95, 0.92)],      # yellow, orange
	[Color(0.55, 0.3, 0.9), Color(0.3, 0.45, 1.0), Color(0.95, 0.95, 1.0)],       # purple, blue
	[Color(1.0, 0.45, 0.75), Color(0.95, 0.2, 0.5), Color(1.0, 0.85, 0.3)],       # tulips
]

const FLOWER_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
varying vec4 tint;
void vertex() {
	tint = INSTANCE_CUSTOM;
	// a gentle sway in the wind (only for the ones still standing)
	float sway = sin(TIME * 1.7 + (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).x * 1.3) * 0.03 * VERTEX.y * tint.a;
	VERTEX.x += sway;
}
void fragment() {
	// vertex alpha 1 = the blossom (instance colour), 0 = stem and leaves
	vec3 c = mix(COLOR.rgb, tint.rgb * COLOR.rgb, COLOR.a);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	BACKLIGHT = c * 0.25;
}
"""

var world
## per bed: {rect: Rect2 (world xz, rotated beds use their bounding box), mm, items: [[xf, col, down]]}
var _beds: Array = []
var _petals: GPUParticles3D
var _petal_t := 0.0
var stats := {"beds": 0, "flowers": 0, "flattened": 0}
static var _mesh: ArrayMesh
static var _mat: ShaderMaterial


## A rectangular bed (size x by z, turned by yaw) at c on the ground.
func add_bed(c: Vector3, size: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var pal: Array = PALETTES[rng.randi() % PALETTES.size()]
	var items: Array = []
	var nx := int(size.x / SPACING)
	var nz := int(size.y / SPACING)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for iz in nz:
		for ix in nx:
			var lp := Vector3((ix + 0.5) * SPACING - size.x * 0.5 + rng.randf_range(-0.1, 0.1), 0.0,
				(iz + 0.5) * SPACING - size.y * 0.5 + rng.randf_range(-0.1, 0.1))
			var p := c + basis * lp + Vector3(0, 0.06, 0)
			var k := rng.randf_range(0.75, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k, k)), p)
			# stripes of colour across the bed, a few odd ones in between
			var band := int(float(iz) / maxf(nz, 1) * 3.0) % pal.size()
			var col: Color = pal[band] if rng.randf() < 0.85 else pal[rng.randi() % pal.size()]
			items.append([xf, col, false])
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	# the soil
	var soil := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 0.3, 0.1, size.y + 0.3)
	soil.mesh = box
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.13, 0.09, 0.06)
	sm.roughness = 0.95
	soil.material_override = sm
	add_child(soil)
	soil.global_transform = Transform3D(basis, c + Vector3(0, 0.03, 0))
	_beds.append({"rect": Rect2(lo, hi - lo).grow(0.3), "items": items, "mm": null})
	stats["beds"] += 1
	stats["flowers"] += items.size()


func build(p_world) -> void:
	world = p_world
	if _mesh == null:
		_mesh = _flower_mesh()
		_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = FLOWER_SHADER
		_mat.shader = sh
	for bed in _beds:
		var items: Array = bed["items"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _mesh
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			var col: Color = items[i][1]
			mm.set_instance_custom_data(i, Color(col.r, col.g, col.b, 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 160.0
		add_child(mmi)
		bed["mm"] = mm
	_petals = GPUParticles3D.new()
	_petals.amount = 160
	_petals.lifetime = 1.6
	_petals.one_shot = false
	_petals.emitting = false
	_petals.explosiveness = 0.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.1, 1.6)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.5, 0.7))
	grad.set_color(1, Color(1.0, 0.9, 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_petals.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.05)
	var qm := StandardMaterial3D.new()
	qm.vertex_color_use_as_albedo = true
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = qm
	_petals.draw_pass_1 = q
	add_child(_petals)


func _physics_process(delta: float) -> void:
	if world == null or _beds.is_empty():
		return
	_petal_t -= delta
	if _petal_t <= 0.0 and _petals:
		_petals.emitting = false
	for car in world.cars.values():
		if not is_instance_valid(car) or not car.visible or not (car is Node3D):
			continue
		var xf: Transform3D = (car as Node3D).global_transform
		var cp := xf.origin
		var v := Vector3.ZERO
		if car is RigidBody3D:
			v = (car as RigidBody3D).linear_velocity
		if Vector2(v.x, v.z).length() < 0.8:
			continue
		var c2 := Vector2(cp.x, cp.z)
		for bed in _beds:
			if not (bed["rect"] as Rect2).grow(2.6).has_point(c2):
				continue
			_plow(bed, xf, v)


## Every standing flower under the car (its footprint, a little wider than the body) is laid down.
func _plow(bed: Dictionary, car_xf: Transform3D, v: Vector3) -> void:
	var inv := car_xf.affine_inverse()
	var items: Array = bed["items"]
	var mm: MultiMesh = bed["mm"]
	var dir := Vector3(v.x, 0, v.z).normalized()
	var axis := Vector3(dir.z, 0, -dir.x)       # lies down forwards, the way the car went
	var n := 0
	for i in items.size():
		var it: Array = items[i]
		if it[2]:
			continue
		var xf: Transform3D = it[0]
		var lp: Vector3 = inv * xf.origin
		if absf(lp.x) > 1.05 or absf(lp.z) > 2.35 or absf(lp.y) > 1.5:
			continue
		it[2] = true
		n += 1
		var flat := Basis(axis, deg_to_rad(randf_range(70.0, 88.0))) * xf.basis.scaled(Vector3(0.85, 0.85, 0.85))
		mm.set_instance_transform(i, Transform3D(flat, xf.origin - Vector3(0, 0.03, 0)))
		var col: Color = it[1]
		var dull := col.lerp(Color(0.25, 0.22, 0.12), 0.55)
		mm.set_instance_custom_data(i, Color(dull.r, dull.g, dull.b, 0.0))
	if n > 0:
		stats["flattened"] += n
		if _petals:
			_petals.global_position = car_xf.origin + Vector3(0, 0.2, 0)
			_petals.emitting = true
			_petal_t = 0.25


## One flower clump: three thin stems with leaves, a blossom on each (vertex alpha 1 marks it).
static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.16, 0.36, 0.1, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf_range(-0.3, 0.3)
		var base := Vector3(cos(a), 0, sin(a)) * 0.05
		var h := rng.randf_range(0.28, 0.42)
		var top := base + Vector3(cos(a) * 0.05, h, sin(a) * 0.05)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.012
		_quad(st, base - side, base + side, top + side, top - side, green)
		# a leaf
		var lm := base + (top - base) * 0.35
		var lt := lm + Vector3(cos(a + 0.8) * 0.09, 0.05, sin(a + 0.8) * 0.09)
		_quad(st, lm - side * 2.0, lm + side * 2.0, lt + side, lt - side, green)
		# the blossom: two crossed petal cards and a flat one
		var r := rng.randf_range(0.045, 0.065)
		var head := Color(1, 1, 1, 1)
		_quad(st, top + Vector3(-r, -r * 0.5, 0), top + Vector3(r, -r * 0.5, 0), top + Vector3(r, r, 0), top + Vector3(-r, r, 0), head)
		_quad(st, top + Vector3(0, -r * 0.5, -r), top + Vector3(0, -r * 0.5, r), top + Vector3(0, r, r), top + Vector3(0, r, -r), head)
		_quad(st, top + Vector3(-r, r * 0.3, -r), top + Vector3(r, r * 0.3, -r), top + Vector3(r, r * 0.3, r), top + Vector3(-r, r * 0.3, r), head)
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)
