extends Node3D
## Tyre smoke / dust particles per wheel, skidmarks and exhaust backfire flames.

const TexKit = preload("res://scripts/util/tex_kit.gd")

var car   # car.gd
var _smokes: Array = []
var _flames: Array = []
var _nitro_flames: Array = []
var _flash: OmniLight3D
var _flash_t := 0.0
var _key_base := 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_key_base = car.get_instance_id() * 8
	for i in 4:
		_smokes.append(_make_smoke(i >= 2))
	for p in car.body.exhaust_points:
		var fl := _make_flame()
		fl.set_meta("local", p)
		_flames.append(fl)
		var nf := _make_flame(true)
		nf.set_meta("local", p)
		_nitro_flames.append(nf)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.5, 0.15)
	_flash.omni_range = 5.0
	_flash.light_energy = 0.0
	_flash.visible = false
	add_child(_flash)
	car.backfire.connect(_on_backfire)


func _make_smoke(rear: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 170 if rear else 90
	p.lifetime = 3.2
	p.local_coords = false
	p.emitting = false
	p.fixed_fps = 60
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 40, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 70.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 2.4
	m.gravity = Vector3(0, 0.3, 0)
	m.damping_min = 0.7
	m.damping_max = 1.4
	m.scale_min = 0.7
	m.scale_max = 1.3
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.angular_velocity_min = -25.0
	m.angular_velocity_max = 25.0
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.3
	var sc := Curve.new()
	sc.max_value = 4.0
	sc.add_point(Vector2(0.0, 0.4))
	sc.add_point(Vector2(0.35, 1.8))
	sc.add_point(Vector2(1.0, 3.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.92, 0.92, 0.94, 0.62))
	grad.set_color(1, Color(0.85, 0.85, 0.88, 0.0))
	grad.add_point(0.35, Color(0.9, 0.9, 0.92, 0.38))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 1.7)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = TexKit.smoke_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


func _make_flame(nitro := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24 if not nitro else 40
	p.lifetime = 0.12 if not nitro else 0.09
	p.one_shot = not nitro
	p.explosiveness = 0.9 if not nitro else 0.0
	p.emitting = false
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0, 1)
	m.spread = 12.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 8.0
	m.gravity = Vector3.ZERO
	m.scale_min = 0.5
	m.scale_max = 1.0
	var grad := Gradient.new()
	if nitro:
		grad.set_color(0, Color(0.6, 0.8, 1.0, 1.0))
		grad.set_color(1, Color(0.2, 0.3, 1.0, 0.0))
	else:
		grad.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
		grad.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = TexKit.smoke_texture()
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _on_backfire() -> void:
	for f in _flames:
		var fl: GPUParticles3D = f
		fl.restart()
		fl.emitting = true
	_flash_t = 0.12


func _process(delta: float) -> void:
	if car == null or car.wheels.size() < 4:
		return
	var speed: float = car.speed
	for i in 4:
		var w: Dictionary = car.wheels[i]
		var p: GPUParticles3D = _smokes[i]
		var slip: float = w["slip"]
		var surf: String = w["surface"]
		var grounded: bool = w["grounded"]
		var contact: Vector3 = w["contact"]
		var threshold := 3.2 if i >= 2 else 5.0
		var pm: ParticleProcessMaterial = p.process_material
		var offroad := surf != "asphalt" and surf != "curb"
		var on := false
		var ratio := 0.0
		if grounded and offroad and speed > 6.0:
			on = true
			ratio = clampf(speed / 40.0 + slip / 15.0, 0.1, 0.8)
			pm.color = Color(0.55, 0.47, 0.35) if surf == "grass" else Color(0.7, 0.7, 0.68)
		elif grounded and slip > threshold:
			on = true
			ratio = clampf((slip - threshold) / 9.0, 0.15, 1.0)
			pm.color = Color(1, 1, 1)
		p.global_position = contact + Vector3(0, 0.25, 0)
		p.emitting = on
		if on:
			p.amount_ratio = ratio
		# skidmarks
		if car.skidmarks:
			var key := _key_base + i
			if grounded and not offroad and slip > 2.2:
				car.skidmarks.add_mark(key, contact, 0.22, clampf(slip / 12.0, 0.25, 0.85))
			else:
				car.skidmarks.break_mark(key)
	# exhaust flames follow the car
	var xf: Transform3D = car.global_transform
	for f in _flames + _nitro_flames:
		var fl: GPUParticles3D = f
		var lp: Vector3 = fl.get_meta("local")
		fl.global_transform = Transform3D(xf.basis, xf * lp)
	var nitro_on: bool = car.nitro_active
	for f in _nitro_flames:
		(f as GPUParticles3D).emitting = nitro_on
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.visible = true
		_flash.light_energy = 3.0 * (_flash_t / 0.12)
		if _flames.size() > 0:
			_flash.global_position = (_flames[0] as GPUParticles3D).global_position
	else:
		_flash.visible = false
