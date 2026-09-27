extends Node3D
## Stormy night outside the menu garage: dark cloud sky with lightning (flashing clouds and a jagged
## bolt), a cold flash of light falling through the gate and the skylights (it also shows in the car
## paint), rain around the hall and wet asphalt outside the gate. Silent: no rain or thunder sound.

const TexKit = preload("res://scripts/util/tex_kit.gd")

const SKY_SHADER := """
shader_type sky;

uniform float flash = 0.0;          // current lightning brightness
uniform float bolt = 0.0;           // visibility of the bolt itself
uniform vec3 flash_dir = vec3(0.3, 0.4, -0.8);
uniform float bolt_seed = 1.0;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float h1(float x, float s) { return fract(sin(x * 12.9898 + s * 78.233) * 43758.5453); }

// one row of high-rises around the horizon: returns colour (rgb) and coverage (a)
// n = buildings around the full circle, hmin/hmax = roof heights (tangent of the elevation)
vec4 city_layer(vec3 d, float n, float hmin, float hmax, float win_h, vec3 body, float seed, float flash_lit) {
	float e = d.y / max(length(d.xz), 1e-4);
	float x = (atan(d.z, d.x) / 6.2831853 + 0.5) * n;
	float cell = floor(x);
	float fx = fract(x);
	float r = h1(cell, seed);
	float r2 = h1(cell, seed + 3.1);
	// some lots are empty, buildings don't fill their lot completely
	float inset = 0.06 + 0.12 * r2;
	if (r2 < 0.12 || fx < inset || fx > 1.0 - inset) {
		return vec4(0.0);
	}
	float top = mix(hmin, hmax, pow(r, 1.7));
	// stepped roofs on some towers
	if (h1(cell, seed + 5.7) > 0.6 && abs(fx - 0.5) > 0.22) {
		top *= 0.82;
	}
	if (e > top) {
		// aviation light on the roof of the tall ones
		float tall = step(0.62, r);
		float blink = step(0.5, fract(TIME * 0.5 + r * 7.0));
		float dotl = exp(-(pow((fx - 0.5) * 60.0, 2.0) + pow((e - top - win_h * 0.6) / win_h * 2.0, 2.0)));
		return vec4(vec3(1.0, 0.08, 0.05) * 3.0, dotl * tall * blink);
	}
	vec3 col = body * (0.8 + 0.4 * r2) + vec3(0.35, 0.4, 0.55) * flash_lit * 0.05;
	// windows: a grid on each facade, a part of them lit
	float cols = floor(5.0 + r * 7.0);
	float wx = (fx - inset) / (1.0 - 2.0 * inset) * cols;
	float wy = e / win_h;
	vec2 wid = vec2(floor(wx), floor(wy));
	vec2 wf = vec2(fract(wx), fract(wy));
	float in_win = step(0.22, wf.x) * step(wf.x, 0.78) * step(0.28, wf.y) * step(wf.y, 0.78);
	float lit_hash = h1(wid.x + wid.y * 37.0 + cell * 911.0, seed + 1.3);
	float lit = step(0.63 - 0.2 * r2, lit_hash);
	// now and then a light switches on / off
	lit *= step(0.02, fract(lit_hash * 13.0 + floor(TIME * 0.05 + lit_hash * 4.0) * 0.37));
	float tone = h1(wid.x * 3.0 + wid.y + cell, seed + 9.0);
	vec3 wc = tone < 0.55 ? vec3(1.0, 0.72, 0.4) : (tone < 0.85 ? vec3(0.85, 0.9, 1.0) : vec3(0.5, 0.95, 0.9));
	col += wc * in_win * lit * (0.5 + 0.8 * lit_hash);
	// a bright band of shop signs at the foot of some buildings
	if (r2 > 0.8 && e < win_h * 1.6 && e > win_h * 0.6) {
		col += vec3(0.9, 0.2, 0.7) * 0.6;
	}
	return vec4(col, 1.0);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 fd = normalize(flash_dir);
	// night sky under a thick storm cover, orange city glow low on the horizon
	vec3 col = mix(vec3(0.03, 0.03, 0.038), vec3(0.008, 0.01, 0.018), pow(clamp(h, 0.0, 1.0), 0.45));
	col += vec3(0.1, 0.05, 0.025) * exp(-max(h, 0.0) * 14.0) * 0.6;
	float near_flash = pow(max(dot(d, fd), 0.0), 4.0);
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12);
		float t = TIME * 0.018;
		float n = fbm(uv * 0.55 + vec2(t, t * 0.35));
		float n2 = fbm(uv * 1.6 - vec2(t * 1.7, 0.0) + vec2(4.0, 1.0));
		float dens = smoothstep(0.3, 0.72, n);
		vec3 cloud = vec3(0.028, 0.03, 0.038) * (0.55 + 0.9 * n2);
		col = mix(col, cloud, dens * 0.92);
		// lightning inside the clouds: the whole sky brightens, the clouds around the strike glow
		col += vec3(0.5, 0.56, 0.8) * flash * (0.06 + near_flash * 1.6) * (0.35 + dens * 0.9 + n2 * 0.4);
		// the bolt: a jagged line from the cloud base down to the horizon near the strike direction
		if (bolt > 0.001 && dot(d, fd) > 0.8) {
			vec3 right = normalize(cross(fd, vec3(0.0, 1.0, 0.0)));
			vec3 upv = cross(right, fd);
			vec2 q = vec2(dot(d, right), dot(d, upv)) / dot(d, fd);
			float v = q.y;
			if (v < 0.08 && h > 0.0) {
				float x = (vnoise(vec2(v * 9.0, bolt_seed)) - 0.5) * 0.09 + (vnoise(vec2(v * 34.0, bolt_seed * 3.1)) - 0.5) * 0.025;
				float core = exp(-abs(q.x - x) / 0.0016);
				float halo = exp(-abs(q.x - x) / 0.02);
				// a side branch
				float bx = x + (0.08 - v) * 0.35 * sign(vnoise(vec2(bolt_seed, 7.0)) - 0.5);
				float branch = exp(-abs(q.x - bx) / 0.0012) * step(-0.12, v) * 0.6;
				col += vec3(0.85, 0.9, 1.0) * bolt * (core * 6.0 + branch * 4.0 + halo * 0.5);
			}
		}
	} else {
		// dark wet land below the horizon
		col = mix(col * 0.6, vec3(0.006, 0.007, 0.009), clamp(-h * 6.0, 0.0, 1.0)) + vec3(0.2, 0.22, 0.3) * flash * 0.04;
	}
	// the city around the horizon: a far row in the haze, a nearer row of taller towers in front
	if (h < 0.3 && h > -0.08) {
		vec3 haze = mix(vec3(0.05, 0.045, 0.05), vec3(0.1, 0.06, 0.035), 0.5);
		vec4 far_c = city_layer(d, 170.0, 0.012, 0.075, 0.0032, vec3(0.03, 0.03, 0.036), 1.0, flash);
		col = mix(col, mix(far_c.rgb, haze, 0.35), far_c.a);
		vec4 near_c = city_layer(d, 70.0, 0.02, 0.19, 0.0075, vec3(0.012, 0.013, 0.018), 2.0, flash);
		col = mix(col, near_c.rgb, near_c.a);
	}
	COLOR = col;
}
"""

var sky_mat: ShaderMaterial
var light: DirectionalLight3D
var _rain_mats: Array = []
var _next := 3.0
var _pulses: Array = []       # [start time, strength]
var _t := 0.0


## hall: floor rectangle of the garage (x/z) – rain falls only outside of it.
func setup(env: Environment, hall: Rect2) -> void:
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# the hall's fog must not swallow the sky (the city outside the gate)
	env.fog_sky_affect = 0.0
	# the lightning: a cold directional light that falls in through the openings
	light = DirectionalLight3D.new()
	light.light_color = Color(0.72, 0.78, 1.0)
	light.light_energy = 0.0
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 60.0
	light.visible = false
	add_child(light)
	_build_ground(hall)
	_build_rain(hall)


func _build_ground(hall: Rect2) -> void:
	# wet asphalt around the hall (just below the hall floor, so it never shows inside)
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	var mat := StandardMaterial3D.new()
	var at: Texture2D = TexKit.photo_texture("asphalt_albedo.jpg")
	if at:
		mat.albedo_texture = at
		mat.normal_enabled = true
		mat.normal_texture = TexKit.photo_texture("asphalt_normal.png")
		mat.normal_scale = 0.25
	mat.albedo_color = Color(0.1, 0.1, 0.11)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / 1.2, 1.0 / 1.2, 1.0 / 1.2)
	mat.roughness = 0.12
	mat.metallic_specular = 0.7
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(hall.get_center().x, -0.03, hall.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_rain(hall: Rect2) -> void:
	var outer := hall.grow(1.5)
	var reach := 14.0
	# four slabs of rain around the hall
	var slabs := [
		Rect2(outer.position.x - reach, outer.position.y - reach, outer.size.x + reach * 2.0, reach),   # back
		Rect2(outer.position.x - reach, outer.end.y, outer.size.x + reach * 2.0, reach),                 # front
		Rect2(outer.position.x - reach, outer.position.y, reach, outer.size.y),                          # left
		Rect2(outer.end.x, outer.position.y, reach, outer.size.y),                                       # right
	]
	var q := clampi(Game.quality(), 0, 3)
	for r in slabs:
		var rect: Rect2 = r
		var p := GPUParticles3D.new()
		p.amount = int(rect.size.x * rect.size.y * [0.6, 0.9, 1.3, 1.6][q])
		p.lifetime = 0.95
		p.preprocess = 1.0
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = Vector3(rect.get_center().x, 14.0, rect.get_center().y)
		p.visibility_aabb = AABB(Vector3(-rect.size.x, -20, -rect.size.y), Vector3(rect.size.x * 2.0, 30, rect.size.y * 2.0))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(rect.size.x * 0.5, 0.5, rect.size.y * 0.5)
		pm.direction = Vector3(0.1, -1, 0.05)
		pm.spread = 3.0
		pm.initial_velocity_min = 15.0
		pm.initial_velocity_max = 18.0
		pm.gravity = Vector3.ZERO
		p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.014, 0.55)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.albedo_color = Color(0.6, 0.65, 0.75, 0.12)
		quad.material = m
		_rain_mats.append(m)
		p.draw_pass_1 = quad
		add_child(p)


func _strike() -> void:
	var az := randf() * TAU
	var el := randf_range(0.18, 0.5)
	var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	sky_mat.set_shader_parameter("flash_dir", dir)
	sky_mat.set_shader_parameter("bolt_seed", randf() * 100.0)
	light.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), Vector3.ZERO)
	_pulses.clear()
	var t0 := _t
	var n := randi_range(2, 4)
	for k in n:
		_pulses.append([t0, randf_range(0.5, 1.0) if k > 0 else 1.0])
		t0 += randf_range(0.06, 0.18)


func _process(delta: float) -> void:
	_t += delta
	_next -= delta
	if _next <= 0.0:
		_next = randf_range(5.0, 13.0)
		_strike()
	var f := 0.0
	var b := 0.0
	for p in _pulses:
		var age := _t - float(p[0])
		if age >= 0.0:
			var e := float(p[1]) * exp(-age / 0.07)
			f = maxf(f, e)
			b = maxf(b, float(p[1]) * exp(-age / 0.05))
	sky_mat.set_shader_parameter("flash", f)
	sky_mat.set_shader_parameter("bolt", b)
	light.visible = f > 0.01
	light.light_energy = f * 2.2
	for m in _rain_mats:
		(m as StandardMaterial3D).albedo_color = Color(0.6 + f * 0.4, 0.65 + f * 0.35, 0.75 + f * 0.25, 0.12 + f * 0.35)
