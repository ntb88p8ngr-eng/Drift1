extends Node3D
## Life in the air around the player: birds by day (crows and small birds over the forests, gulls at
## the harbour, vultures circling high over the desert, crows over Tokyo), bats and fireflies at
## night in the forests, leaves drifting down from the trees, sand blowing across the desert, steam
## rising from manholes in the city. It all stays with the camera: the particles run on the GPU,
## each flock is one MultiMesh moved here (a few dozen transforms a frame).

const TexKit = preload("res://scripts/util/tex_kit.gd")

const FOREST := ["ridge", "gruene_hoelle"]
const SAND_WIND := Vector3(1.0, 0.0, 0.35)      # (desert.gd WIND)

const BIRD_SHADER := """
shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform vec3 col : source_color = vec3(0.05);
uniform float flap_rate = 8.0;
uniform float glide = 0.0;       // share of the time spent gliding (gulls, vultures)
void vertex() {
	float ph = INSTANCE_CUSTOM.r * 6.2831;
	float w = abs(VERTEX.x);
	float g = mix(1.0, smoothstep(0.4, 1.0, sin(TIME * 0.6 + ph * 3.0)), glide);
	VERTEX.y += sin(TIME * flap_rate + ph) * w * 0.85 * g + w * 0.12 * (1.0 - g);
}
void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
"""

var world
var night := 0.0
var _flocks: Array = []
var _leaves: GPUParticles3D
var _flies: GPUParticles3D
var _sand: GPUParticles3D
var rng := RandomNumberGenerator.new()
var stats := {}


class Flock:
	var mmi: MultiMeshInstance3D
	var n := 0
	var centre := Vector3.ZERO
	var radius := 60.0
	var height := Vector2(20, 40)
	var speed := 9.0
	var angle := 0.0
	var dir := 1.0
	var offs: Array = []          # per bird: [radial offset, height offset, angle offset]
	var at_night := false         # bats: out at night only (birds by day only)
	var erratic := 0.0
	var size := 1.0
	var vis := 0.0
	var placed := false


func setup(p_world) -> void:
	world = p_world
	var id: String = world.track.track_id
	rng.seed = hash(id) + 77
	night = float(world.atmosphere.night)
	world.atmosphere.night_changed.connect(func(n: float) -> void: night = n)
	var q := clampi(Game.quality(), 0, 3)
	var amount_k: float = [0.4, 0.7, 1.0, 1.3][q]
	if Game.is_desert(id):
		_add_flock(4, 2.0, Color(0.12, 0.09, 0.07), 7.0, 50.0, Vector2(55, 85), 3.0, 0.9)
		_add_flock(5, 0.45, Color(0.25, 0.2, 0.16), 11.0, 30.0, Vector2(8, 16), 14.0, 0.2)
		_sand = _sand_drift(int(60 * amount_k))
	elif id == "harbor":
		_add_flock(8, 1.3, Color(0.92, 0.92, 0.9), 9.0, 50.0, Vector2(18, 35), 5.0, 0.6)
		_add_flock(6, 1.3, Color(0.9, 0.9, 0.88), 8.0, 70.0, Vector2(30, 50), 4.5, 0.7)
	elif Game.is_city(id):
		_add_flock(7, 0.9, Color(0.03, 0.03, 0.04), 10.0, 60.0, Vector2(35, 70), 7.0, 0.3)
		_steam_vents()
	else:
		_add_flock(6, 0.9, Color(0.03, 0.03, 0.04), 10.0, 70.0, Vector2(25, 45), 7.0, 0.3)
		_add_flock(14, 0.42, Color(0.22, 0.17, 0.12), 13.0, 40.0, Vector2(12, 28), 15.0, 0.0)
		if FOREST.has(id):
			var bats := _add_flock(9, 0.38, Color(0.02, 0.02, 0.025), 9.0, 16.0, Vector2(6, 14), 18.0, 0.0)
			bats.at_night = true
			bats.erratic = 1.0
			_leaves = _falling_leaves(int(110 * amount_k))
			_flies = _fireflies(int(80 * amount_k))


# ---------------------------------------------------------------------------
# Birds
# ---------------------------------------------------------------------------
static var _bird_mesh: ArrayMesh


## A bird seen from below: a slim body and two swept wings (span 1 m at scale 1; the wing tips flap
## in the shader).
static func bird_mesh() -> ArrayMesh:
	if _bird_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tris := [
			# body
			[Vector3(0, 0, -0.32), Vector3(0.05, 0, 0.0), Vector3(-0.05, 0, 0.0)],
			[Vector3(0.05, 0, 0.0), Vector3(0, 0, 0.22), Vector3(-0.05, 0, 0.0)],
			# tail
			[Vector3(0, 0, 0.16), Vector3(0.07, 0, 0.3), Vector3(-0.07, 0, 0.3)],
			# wings: inner and outer part, swept back
			[Vector3(0.04, 0, -0.1), Vector3(0.25, 0, -0.06), Vector3(0.04, 0, 0.06)],
			[Vector3(0.25, 0, -0.06), Vector3(0.5, 0, 0.08), Vector3(0.22, 0, 0.06)],
			[Vector3(0.04, 0, 0.06), Vector3(0.25, 0, -0.06), Vector3(0.22, 0, 0.06)],
			[Vector3(-0.04, 0, -0.1), Vector3(-0.25, 0, -0.06), Vector3(-0.04, 0, 0.06)],
			[Vector3(-0.25, 0, -0.06), Vector3(-0.5, 0, 0.08), Vector3(-0.22, 0, 0.06)],
			[Vector3(-0.04, 0, 0.06), Vector3(-0.25, 0, -0.06), Vector3(-0.22, 0, 0.06)],
		]
		for t in tris:
			st.set_normal(Vector3.UP)
			for v in t:
				st.add_vertex(v)
		_bird_mesh = st.commit()
	return _bird_mesh


func _add_flock(n: int, size: float, col: Color, speed: float, radius: float, height: Vector2, flap: float, glide: float) -> Flock:
	var f := Flock.new()
	f.n = n
	f.size = size
	f.speed = speed
	f.radius = radius
	f.height = height
	f.dir = 1.0 if rng.randf() < 0.5 else -1.0
	f.angle = rng.randf() * TAU
	for i in n:
		f.offs.append([rng.randf_range(-6.0, 6.0) * (radius / 50.0), rng.randf_range(-3.0, 3.0), rng.randf_range(0.0, 0.45) + i * 0.02])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = bird_mesh()
	mm.instance_count = n
	for i in n:
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = BIRD_SHADER
	mat.set_shader_parameter("col", col)
	mat.set_shader_parameter("flap_rate", flap)
	mat.set_shader_parameter("glide", glide)
	f.mmi = MultiMeshInstance3D.new()
	f.mmi.name = "Flock"
	f.mmi.multimesh = mm
	f.mmi.material_override = mat
	f.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.mmi.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))
	add_child(f.mmi)
	_flocks.append(f)
	stats["birds"] = int(stats.get("birds", 0)) + n
	return f


func _update_flock(f: Flock, cam: Vector3, fwd: Vector3, dt: float) -> void:
	var want := 1.0 if (night > 0.6) == f.at_night else 0.0
	f.vis = move_toward(f.vis, want, dt * 0.25)
	# far behind or never placed: a new spot somewhere ahead (out there they are only specks)
	if not f.placed:
		f.vis = want
	if not f.placed or Vector2(f.centre.x - cam.x, f.centre.z - cam.z).length() > 420.0:
		var a := atan2(fwd.x, fwd.z) + rng.randf_range(-0.9, 0.9)
		var d := rng.randf_range(60.0, 220.0) if f.placed else rng.randf_range(30.0, 160.0)
		f.centre = cam + Vector3(sin(a), 0.0, cos(a)) * d
		f.placed = true
	# the circle drifts along a little
	f.centre += Vector3(cos(f.angle * 0.13), 0.0, sin(f.angle * 0.11)) * dt * f.speed * 0.15
	f.angle += f.speed / f.radius * dt * f.dir
	var g: float = world.terrain.height_at(f.centre.x, f.centre.z)
	var mm := f.mmi.multimesh
	var t := Time.get_ticks_msec() * 0.001
	var s := f.size * f.vis
	for i in f.n:
		var o: Array = f.offs[i]
		var a: float = f.angle + float(o[2]) * f.dir
		var r: float = f.radius + float(o[0])
		var h: float = lerpf(f.height.x, f.height.y, 0.5 + 0.5 * sin(t * 0.07 + i)) + float(o[1])
		var pos := f.centre + Vector3(cos(a) * r, 0.0, sin(a) * r) + Vector3(0, g + h, 0)
		if f.erratic > 0.0:
			pos += Vector3(sin(t * 3.1 + i * 1.7), sin(t * 4.3 + i) * 0.6, cos(t * 2.7 + i * 2.3)) * 2.5 * f.erratic
		var tan := Vector3(-sin(a), 0.0, cos(a)) * f.dir
		var b := Basis.looking_at(tan, Vector3.UP)
		# banked into the turn
		b = b.rotated(tan, -0.35 * f.dir)
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * maxf(s, 0.0001)), pos))
	f.mmi.visible = f.vis > 0.01


# ---------------------------------------------------------------------------
# Particles round the camera
# ---------------------------------------------------------------------------
func _particles(amount: int, lifetime: float, pm: ParticleProcessMaterial, quad: Vector2, mat: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 4)
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.process_material = pm
	p.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = quad
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	return p


static func _gradient_tex(cols: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(cols)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static var _leaf_tex: ImageTexture


## A leaf for the particles: a pointed oval with a midrib (white: the particle colour tints it).
static func leaf_shape() -> ImageTexture:
	if _leaf_tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var u := (x + 0.5) / 32.0 * 2.0 - 1.0
				var v := (y + 0.5) / 32.0 * 2.0 - 1.0
				var w := 0.55 * (1.0 - v * v)
				var a := clampf((w - absf(u)) * 12.0, 0.0, 1.0)
				var rib := 0.8 if absf(u) < 0.05 else 1.0
				img.set_pixel(x, y, Color(rib, rib, rib, a))
		img.generate_mipmaps()
		_leaf_tex = ImageTexture.create_from_image(img)
	return _leaf_tex


func _falling_leaves(amount: int) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(32, 5, 32)
	pm.direction = Vector3(1, -0.2, 0.4)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -0.75, 0)
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.06
	pm.turbulence_influence_max = 0.16
	pm.color_initial_ramp = _gradient_tex([Color(0.86, 0.66, 0.2), Color(0.78, 0.4, 0.12), Color(0.55, 0.33, 0.15), Color(0.62, 0.62, 0.22)], [0.0, 0.35, 0.7, 1.0])
	pm.color_ramp = _gradient_tex([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.1, 0.85, 1.0])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = leaf_shape()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.roughness = 0.8
	stats["leaves"] = amount
	return _particles(amount, 10.0, pm, Vector2(0.09, 0.07), mat)


func _fireflies(amount: int) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 1.3, 28)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	# blinking: on, off, on again
	pm.color_ramp = _gradient_tex([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.05), Color(1, 1, 1, 1), Color(1, 1, 1, 0)],
		[0.0, 0.15, 0.3, 0.55, 0.7, 1.0])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TexKit.smoke_texture()
	mat.albedo_color = Color(0.85, 1.0, 0.35)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.emission_enabled = true
	mat.emission = Color(0.7, 1.0, 0.25)
	mat.emission_energy_multiplier = 3.0
	stats["fireflies"] = amount
	var p := _particles(amount, 6.0, pm, Vector2(0.12, 0.12), mat)
	p.emitting = false
	return p


func _sand_drift(amount: int) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38, 0.4, 38)
	pm.direction = SAND_WIND.normalized()
	pm.spread = 8.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.0
	pm.scale_max = 2.4
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.color_ramp = _gradient_tex([Color(0.86, 0.7, 0.5, 0.0), Color(0.86, 0.7, 0.5, 0.16), Color(0.86, 0.7, 0.5, 0.0)], [0.0, 0.4, 1.0])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TexKit.smoke_texture(true)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	stats["sand"] = amount
	return _particles(amount, 3.5, pm, Vector2(2.4, 0.9), mat)


## Neo Tokyo: manholes in the road with steam coming up, every 150-250 m along the route.
func _steam_vents() -> void:
	var tr = world.track
	var n: int = tr.sample_count()
	var cover := CylinderMesh.new()
	cover.top_radius = 0.38
	cover.bottom_radius = 0.38
	cover.height = 0.02
	cover.radial_segments = 16
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.12, 0.12, 0.12)
	cm.metallic = 0.6
	cm.roughness = 0.45
	cover.material = cm
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.15, 0.25, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _gradient_tex([Color(0.9, 0.9, 0.92, 0.0), Color(0.9, 0.9, 0.92, 0.32), Color(0.9, 0.9, 0.92, 0.0)], [0.0, 0.15, 1.0])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TexKit.smoke_texture()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.roughness = 1.0
	# a faint glow of its own: at night it catches the neon and the street lights
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.57, 0.62)
	mat.emission_energy_multiplier = 0.4
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	q.material = mat
	var d := rng.randf_range(60.0, 160.0)
	while d < tr.length - 40.0:
		var i: int = tr.index_at(d)
		d += rng.randf_range(150.0, 250.0)
		var hw: float = tr.hws[i]
		var mid: Vector3 = tr.edge_point(i, 0.0)
		if mid.y - world.terrain.height_at(mid.x, mid.z) > 1.0:
			continue      # (up on the expressway)
		var lat := hw * rng.randf_range(0.25, 0.55) * (1.0 if rng.randf() < 0.5 else -1.0)
		var pos: Vector3 = tr.edge_point(i, lat) + Vector3(0, tr.ROAD_Y + 0.005, 0)
		var lid := MeshInstance3D.new()
		lid.mesh = cover
		lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lid.visibility_range_end = 160.0
		add_child(lid)
		lid.global_position = pos
		var p := GPUParticles3D.new()
		p.amount = 12
		p.lifetime = 3.5
		p.preprocess = 3.5
		p.local_coords = false
		p.process_material = pm
		p.draw_pass_1 = q
		p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 9, 8))
		p.visibility_range_end = 150.0
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		p.global_position = pos + Vector3(0, 0.05, 0)
		stats["steam"] = int(stats.get("steam", 0)) + 1


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or world == null:
		return
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	for f in _flocks:
		_update_flock(f, cp, fwd, dt)
	if _leaves:
		_leaves.global_position = cp + fwd * 10.0 + Vector3(0, 9.0, 0)
	if _flies:
		var g: float = world.terrain.height_at(cp.x, cp.z)
		_flies.global_position = Vector3(cp.x, g + 1.6, cp.z) + fwd * 8.0
		_flies.emitting = night > 0.55
	if _sand:
		var gs: float = world.terrain.height_at(cp.x, cp.z)
		_sand.global_position = Vector3(cp.x, gs + 0.5, cp.z) - SAND_WIND.normalized() * 12.0


func stats_text() -> String:
	return str(stats)
