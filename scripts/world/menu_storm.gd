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
// n = buildings around the full circle, hmin/hmax = roof heights (tangent of the elevation),
// win_h = floor height (same unit)
vec4 city_layer(vec3 d, float n, float hmin, float hmax, float win_h, float seed, float flash_lit) {
	float e = d.y / max(length(d.xz), 1e-4);
	float x = (atan(d.z, d.x) / 6.2831853 + 0.5) * n;
	float cell = floor(x);
	float fx = fract(x);
	float r = h1(cell, seed);           // height
	float r2 = h1(cell, seed + 3.1);    // lot use / facade style
	float r3 = h1(cell, seed + 7.7);    // material
	float r4 = h1(cell, seed + 11.3);   // how many lights are on
	float r5 = h1(cell, seed + 17.9);   // roof
	// lots of different widths; some are empty
	float inset = 0.03 + 0.2 * h1(cell, seed + 23.0);
	if (r2 < 0.1 || fx < inset || fx > 1.0 - inset) {
		return vec4(0.0);
	}
	float u = (fx - inset) / (1.0 - 2.0 * inset);   // 0..1 across the facade
	float top = mix(hmin, hmax, pow(r, 2.2));
	// roofs: stepped crown, slanted top, or a spire on the tall ones
	if (r5 > 0.55 && r5 < 0.8 && abs(u - 0.5) > 0.3) {
		top *= 0.86;
	} else if (r5 >= 0.8) {
		top -= abs(u - 0.5) * (top - hmin) * 0.25;
	}
	bool spire = r > 0.72 && r5 < 0.3;
	if (e > top) {
		float ex = e - top;
		if (spire && abs(u - 0.5) < 0.03 && ex < (top - hmin) * 0.35) {
			float blink = step(0.5, fract(TIME * 0.5 + r * 7.0));
			float tip = step((top - hmin) * 0.33, ex);
			return vec4(mix(vec3(0.02), vec3(1.0, 0.08, 0.05) * 3.0 * blink, tip), 1.0);
		}
		// aviation light on flat roofs of tall buildings
		float tall = step(0.62, r) * step(0.3, r5);
		float blink2 = step(0.5, fract(TIME * 0.45 + r2 * 5.0));
		float dotl = exp(-(pow((u - 0.5) * 70.0, 2.0) + pow(ex / win_h * 2.2 - 0.6, 2.0)));
		return vec4(vec3(1.0, 0.08, 0.05) * 3.0, dotl * tall * blink2);
	}
	// facade material: concrete, blue glass, brick, dark stone
	vec3 body = r3 < 0.3 ? vec3(0.034, 0.034, 0.037) : (r3 < 0.6 ? vec3(0.018, 0.026, 0.04) : (r3 < 0.8 ? vec3(0.036, 0.026, 0.022) : vec3(0.014, 0.014, 0.016)));
	float grain = vnoise(vec2(u * 30.0 + cell, e / win_h * 0.7));
	vec3 col = body * (0.8 + 0.4 * grain) + vec3(0.35, 0.4, 0.55) * flash_lit * 0.05;
	// the edge towards the city glow is a bit lighter (gives the towers some volume)
	col *= 0.85 + 0.3 * smoothstep(0.0, 1.0, u);
	float style = floor(r2 * 4.0);
	float floor_i = floor(e / win_h);
	float fy = fract(e / win_h);
	float cols = floor(10.0 + r * 16.0);
	float cx = u * cols;
	float col_i = floor(cx);
	float fxw = fract(cx);
	// share of lit windows and their brightness: each building differs
	float lit_share = mix(0.08, 0.8, pow(r4, 1.4));
	float bright = mix(0.35, 1.25, h1(cell, seed + 29.0));
	float win = 0.0;
	float lit_hash = 0.0;
	if (style < 1.0) {
		// punched windows in a grid
		win = step(0.25, fxw) * step(fxw, 0.75) * step(0.3, fy) * step(fy, 0.75);
		lit_hash = h1(col_i + floor_i * 37.0 + cell * 911.0, seed + 1.3);
	} else if (style < 2.0) {
		// ribbon windows: bands along whole floors, lit in stretches
		win = step(0.35, fy) * step(fy, 0.72);
		lit_hash = h1(floor(cx / 4.0) + floor_i * 53.0 + cell * 577.0, seed + 2.9);
	} else if (style < 3.0) {
		// glass curtain wall: faint blue glow on the mullions, whole floors lit
		col += vec3(0.02, 0.035, 0.06) * step(0.9, fxw) * 0.6;
		win = step(0.12, fy) * step(fy, 0.9) * step(fxw, 0.88);
		lit_hash = h1(floor_i * 71.0 + cell * 313.0 + floor(cx / 6.0), seed + 4.1);
	} else {
		// residential: small windows further apart
		win = step(0.35, fract(cx * 0.5)) * step(fract(cx * 0.5), 0.6) * step(0.4, fy) * step(fy, 0.7);
		lit_hash = h1(floor(cx * 0.5) + floor_i * 41.0 + cell * 997.0, seed + 5.3);
	}
	float lit = step(1.0 - lit_share, lit_hash);
	// now and then a light switches on / off
	lit *= step(0.02, fract(lit_hash * 13.0 + floor(TIME * 0.05 + lit_hash * 4.0) * 0.37));
	float tone = h1(col_i * 3.0 + floor_i + cell, seed + 9.0);
	vec3 wc = tone < 0.5 ? vec3(1.0, 0.72, 0.4) : (tone < 0.82 ? vec3(0.85, 0.9, 1.0) : (tone < 0.93 ? vec3(0.5, 0.95, 0.9) : vec3(1.0, 0.5, 0.25)));
	col += wc * win * lit * bright * (0.55 + 0.45 * lit_hash);
	// dark, unlit windows still reflect a little
	col += vec3(0.02, 0.025, 0.035) * win * (1.0 - lit);
	// neon signs at the foot of some buildings
	if (h1(cell, seed + 31.0) > 0.82 && e < win_h * 1.7 && e > win_h * 0.7) {
		col += (h1(cell, seed + 37.0) > 0.5 ? vec3(0.9, 0.2, 0.7) : vec3(0.2, 0.8, 1.0)) * 0.55;
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
	// the city on the horizon, a few kilometres away: three rows, the further ones hazier
	if (h < 0.12 && h > -0.03) {
		vec3 haze = vec3(0.07, 0.05, 0.045);
		vec4 c3 = city_layer(d, 260.0, 0.004, 0.028, 0.0011, 3.0, flash);
		col = mix(col, mix(c3.rgb, haze, 0.55), c3.a);
		vec4 c2 = city_layer(d, 170.0, 0.006, 0.042, 0.0015, 1.0, flash);
		col = mix(col, mix(c2.rgb, haze, 0.35), c2.a);
		vec4 c1 = city_layer(d, 110.0, 0.008, 0.07, 0.002, 2.0, flash);
		col = mix(col, mix(c1.rgb, haze, 0.1), c1.a);
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
	# the hall's fog must not swallow the sky (the city outside the gate); outside it is the city
	# haze, so the far fields fade into the skyline
	env.fog_sky_affect = 0.0
	env.fog_light_color = Color(0.07, 0.05, 0.045)
	env.fog_density = 0.006
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
	# wet asphalt apron around the hall (just below the hall floor, so it never shows inside)
	var apron := PlaneMesh.new()
	apron.size = hall.grow(14.0).size
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
	mi.mesh = apron
	mi.material_override = mat
	mi.position = Vector3(hall.get_center().x, -0.03, hall.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# wide, wet grass fields out to the city (patchwork of meadows, mown strips, field edges)
	var fields := PlaneMesh.new()
	fields.size = Vector2(3000, 3000)
	var fm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FIELD_SHADER
	fm.shader = sh
	fm.set_shader_parameter("noise_tex", TexKit.noise_texture(71, 0.02))
	var fi := MeshInstance3D.new()
	fi.mesh = fields
	fi.material_override = fm
	fi.position = Vector3(hall.get_center().x, -0.06, hall.get_center().y)
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fi)


const FIELD_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
float fh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz;
	// fields of 40-90 m, each with its own shade of green, some mown in strips
	vec2 fc = floor(p / vec2(70.0, 55.0));
	float f = fh(fc);
	vec3 base = mix(vec3(0.03, 0.055, 0.02), vec3(0.05, 0.075, 0.025), f);
	base = mix(base, vec3(0.06, 0.06, 0.03), step(0.82, f));
	// fine detail only close by (far away it would flicker at the flat viewing angle)
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(25.0, 90.0, dist);
	float n1 = texture(noise_tex, p * 0.05).r;
	float n2 = mix(0.5, texture(noise_tex, p * 0.9).r, near);
	float strips = step(0.6, f) * step(0.5, fract((f > 0.8 ? p.x : p.y) / 6.0)) * 0.15;
	vec3 col = base * (0.75 + 0.5 * n1) * (0.85 + 0.3 * n2) * (1.0 - strips);
	// darker hedges / ditches along the field edges
	vec2 e = abs(fract(p / vec2(70.0, 55.0)) - 0.5);
	float edge = smoothstep(0.485, 0.497, max(e.x, e.y));
	col = mix(col, vec3(0.02, 0.035, 0.015), edge * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.15;
}
"""


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
