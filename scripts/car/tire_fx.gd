extends Node3D
## Tyre smoke / dust particles per wheel, skidmarks, exhaust backfire flames and nitro flames.
## The flames are children of the car body (local coordinates), so they always sit exactly in the
## exhaust tips, even at high speed.

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
	var r: float = car.body.exhaust_radius
	for p in car.body.exhaust_points:
		var fl := _make_flame(false, r)
		fl.position = p
		_flames.append(fl)
		var nf := _make_flame(true, r)
		nf.position = p
		_nitro_flames.append(nf)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.5, 0.15)
	_flash.omni_range = 5.0
	_flash.light_energy = 0.0
	_flash.visible = false
	car.body.add_child(_flash)
	if car.body.exhaust_points.size() > 0:
		var avg := Vector3.ZERO
		for p in car.body.exhaust_points:
			avg += p
		_flash.position = avg / float(car.body.exhaust_points.size()) + Vector3(0, 0.1, 0.4)
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


func _make_flame(nitro: bool, pipe_r: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var size := clampf(pipe_r * 5.0, 0.12, 0.34)
	p.amount = 40 if nitro else 24
	p.lifetime = 0.1 if nitro else 0.12
	p.one_shot = not nitro
	p.explosiveness = 0.0 if nitro else 0.9
	p.emitting = false
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 4))
	var m := ParticleProcessMaterial.new()
	# car space: +Z points out of the tail pipe
	m.direction = Vector3(0, 0, 1)
	m.spread = 7.0 if nitro else 12.0
	m.initial_velocity_min = 5.0 if nitro else 4.0
	m.initial_velocity_max = 9.0 if nitro else 8.0
	m.gravity = Vector3.ZERO
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = pipe_r * 0.6
	m.scale_min = 0.7
	m.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.55))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1.0, 0.25))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	var grad := Gradient.new()
	if nitro:
		grad.set_color(0, Color(0.85, 0.95, 1.0, 1.0))
		grad.set_color(1, Color(0.35, 0.2, 1.0, 0.0))
		grad.add_point(0.35, Color(0.3, 0.55, 1.0, 0.9))
	else:
		grad.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
		grad.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
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
	car.body.add_child(p)
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
		var wet: float = car.track.wetness if car.track else 0.0
		if grounded and not offroad and wet > 0.25 and speed > 9.0 and slip <= threshold:
			# spray from wet asphalt
			on = true
			ratio = clampf(speed / 60.0 * wet, 0.08, 0.55) * (1.0 if i >= 2 else 0.6)
			pm.color = Color(0.82, 0.85, 0.9, 0.55)
		elif grounded and offroad and speed > 6.0:
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
	# nitro flames (the emitters are parented to the car body)
	var nitro_on: bool = car.nitro_active
	for f in _nitro_flames:
		(f as GPUParticles3D).emitting = nitro_on
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.visible = true
		_flash.light_color = Color(1.0, 0.5, 0.15)
		_flash.light_energy = 3.0 * (_flash_t / 0.12)
	elif nitro_on:
		_flash.visible = true
		_flash.light_color = Color(0.35, 0.5, 1.0)
		_flash.light_energy = 1.6 + randf() * 0.6
	else:
		_flash.visible = false
