extends RefCounted
## Procedural textures, shaders and materials. Everything is generated at runtime – no asset files.

static var _cache := {}


static func _shader(key: String, code: String) -> Shader:
	if not _cache.has(key):
		var s := Shader.new()
		s.code = code
		_cache[key] = s
	return _cache[key]


# ---------------------------------------------------------------------------
# Shaders
# ---------------------------------------------------------------------------
const PAINT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.17, 0.04, 0.30);
uniform vec3 flip_color : source_color = vec3(0.05, 0.28, 0.20);
uniform vec3 edge_color : source_color = vec3(0.45, 0.22, 0.06);
uniform float flake_amount = 0.45;
uniform float flake_scale = 420.0;
uniform float metallic_amount = 0.8;
uniform float base_roughness = 0.32;
uniform float clearcoat_amount = 1.0;
uniform float dirt = 0.0;

varying vec3 obj_pos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = pow(1.0 - ndv, 1.4);
	vec3 col = mix(base_color, flip_color, smoothstep(0.18, 0.72, f));
	col = mix(col, edge_color, smoothstep(0.72, 1.0, f) * 0.65);
	float h = hash3(floor(obj_pos * flake_scale));
	float flake = step(0.82, h) * flake_amount;
	float sparkle = flake * pow(ndv, 2.0);
	col += sparkle * (0.35 + 0.65 * col);
	col = mix(col, vec3(0.32, 0.28, 0.22), dirt * smoothstep(0.55, 0.1, obj_pos.y));
	ALBEDO = col;
	METALLIC = metallic_amount;
	ROUGHNESS = clamp(base_roughness - flake * 0.18 + dirt * 0.4, 0.05, 1.0);
	SPECULAR = 0.6;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = 0.04;
}
"""

const ROAD_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 asphalt : source_color = vec3(0.10, 0.10, 0.11);
uniform vec3 line_color : source_color = vec3(0.92, 0.92, 0.88);
uniform float edge_line = 0.022;
uniform float wetness = 0.0;
uniform float patch_amount = 0.5;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.23).r;
	float n2 = texture(noise_tex, wpos.xz * 0.019).r;
	float n3 = texture(noise_tex, wpos.xz * 0.004 + vec2(0.3, 0.7)).r;
	vec3 col = asphalt * (0.72 + 0.56 * n) * (0.85 + 0.3 * n2);
	col = mix(col, asphalt * 1.45, smoothstep(0.62, 0.66, n3) * patch_amount);
	float line_off = 0.14 * sin(UV.y * 0.011) + 0.06 * sin(UV.y * 0.037);
	float rubber = smoothstep(0.30, 0.0, abs(UV.x - 0.5 + line_off)) * (0.45 + 0.4 * n2);
	col *= 1.0 - rubber * 0.55;
	float edge = step(UV.x, edge_line) + step(1.0 - edge_line, UV.x);
	col = mix(col, line_color * (0.8 + 0.2 * n), clamp(edge, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.86 - rubber * 0.25, 0.18, wetness);
	SPECULAR = 0.45;
	NORMAL_MAP = texture(noise_nrm, wpos.xz * 0.23).xyz;
	NORMAL_MAP_DEPTH = 0.7;
}
"""

const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 color_a : source_color = vec3(0.13, 0.22, 0.07);
uniform vec3 color_b : source_color = vec3(0.20, 0.30, 0.09);
uniform vec3 color_c : source_color = vec3(0.28, 0.25, 0.14);
uniform float roughness_value = 0.95;
uniform float tile_size = 0.0;
uniform float normal_depth = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.045).r;
	float n2 = texture(noise_tex, wpos.xz * 0.37).r;
	float n3 = texture(noise_tex, wpos.xz * 0.006 + vec2(0.5, 0.1)).r;
	vec3 col = mix(color_a, color_b, smoothstep(0.3, 0.7, n1));
	col = mix(col, color_c, smoothstep(0.55, 0.8, n3) * 0.7);
	col *= 0.78 + 0.44 * n2;
	if (tile_size > 0.0) {
		vec2 g = abs(fract(wpos.xz / tile_size) - 0.5);
		float l = smoothstep(0.485, 0.495, max(g.x, g.y));
		col *= 1.0 - l * 0.45;
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	NORMAL_MAP = texture(noise_nrm, wpos.xz * 0.37).xyz;
	NORMAL_MAP_DEPTH = normal_depth;
}
"""

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 1.0;
uniform float alpha_cut = 0.45;
uniform vec3 backlight_color : source_color = vec3(0.22, 0.32, 0.08);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y * 0.11, 0.0, 1.6);
	float sway = sin(TIME * 1.5 + wp.x * 0.31 + wp.z * 0.23) * 0.07 + sin(TIME * 3.9 + wp.y * 1.7 + wp.x * 0.9) * 0.025;
	VERTEX.x += sway * wind * h;
	VERTEX.z += sway * 0.6 * wind * h;
	VERTEX.y += sin(TIME * 4.3 + wp.x * 2.1 + wp.z * 1.3) * 0.015 * wind * h;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * tint;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.72;
	SPECULAR = 0.25;
	BACKLIGHT = backlight_color;
}
"""

const BARK_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 1.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp((VERTEX.y - 2.0) * 0.09, 0.0, 1.4);
	float sway = sin(TIME * 1.5 + wp.x * 0.31 + wp.z * 0.23) * 0.05;
	VERTEX.x += sway * wind * h;
	VERTEX.z += sway * 0.6 * wind * h;
}

void fragment() {
	ALBEDO = texture(bark_tex, UV).rgb * COLOR.rgb * tint;
	NORMAL_MAP = texture(bark_nrm, UV).xyz;
	NORMAL_MAP_DEPTH = 1.4;
	ROUGHNESS = 0.92;
}
"""

const SKY_SHADER := """
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.12, 0.28, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.72, 0.85);
uniform vec3 ground_color : source_color = vec3(0.18, 0.17, 0.16);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float sun_size = 0.035;
uniform float sun_glow = 0.35;
uniform float cloud_coverage = 0.45;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.58, 0.66);
uniform float star_amount = 0.0;
uniform float moon_amount = 0.0;
uniform vec3 moon_dir = vec3(-0.3, 0.5, -0.8);
uniform float exposure = 1.0;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

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

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.5));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float d = dot(dir, LIGHT0_DIRECTION);
		float disk = 0.0;
		if (sun_size > 0.0001) {
			disk = smoothstep(cos(sun_size), cos(sun_size * 0.85), d);
		}
		float glow = pow(max(d, 0.0), 6.0) * sun_glow + pow(max(d, 0.0), 80.0) * 0.8;
		col += sun_color * glow;
		col += sun_color * disk * 25.0 * step(-0.02, h);
	}
	if (moon_amount > 0.0) {
		float md = dot(dir, normalize(moon_dir));
		col += vec3(0.8, 0.85, 1.0) * smoothstep(0.9993, 0.9996, md) * moon_amount * 3.0;
		col += vec3(0.25, 0.3, 0.45) * pow(max(md, 0.0), 30.0) * moon_amount * 0.3;
	}
	if (star_amount > 0.0 && h > 0.0) {
		float s = hash3(floor(dir * 420.0));
		float tw = hash3(floor(dir * 420.0) + vec3(3.0));
		col += vec3(0.9, 0.92, 1.0) * step(0.9975, s) * star_amount * (0.4 + 0.6 * tw) * smoothstep(0.0, 0.25, h);
	}
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.1);
		float n = fbm(uv * 0.9 + vec2(4.1, 2.3));
		float cov = 1.0 - cloud_coverage;
		float c = smoothstep(cov, cov + 0.3, n);
		float shade = clamp((fbm(uv * 0.9 + vec2(4.13, 2.36)) - n) * 6.0 + 0.5, 0.0, 1.0);
		vec3 cc = mix(cloud_color, cloud_shade, shade);
		if (LIGHT0_ENABLED) {
			cc += sun_color * pow(max(dot(dir, LIGHT0_DIRECTION), 0.0), 8.0) * 0.6 * (1.0 - c);
		}
		col = mix(col, cc, c * smoothstep(0.0, 0.12, h) * 0.92);
	}
	COLOR = col * exposure;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.01, 0.06, 0.09);
uniform vec3 shallow_color : source_color = vec3(0.03, 0.16, 0.18);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n1 = texture(noise_nrm, wpos.xz * 0.03 + vec2(TIME * 0.012, TIME * 0.008)).xyz;
	vec3 n2 = texture(noise_nrm, wpos.xz * 0.07 - vec2(TIME * 0.01, -TIME * 0.015)).xyz;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color, shallow_color, fres);
	METALLIC = 0.0;
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	NORMAL_MAP = n1 * 0.5 + n2 * 0.5;
	NORMAL_MAP_DEPTH = 0.6;
}
"""

const CONTAINER_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 base_color : source_color = vec3(0.6, 0.1, 0.05);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float rib_freq = 9.0;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	float along = abs(onrm.x) > 0.5 ? opos.z : opos.x;
	float rib = sin(along * rib_freq * 6.2831);
	float rust = texture(noise_tex, opos.xy * 0.3 + opos.zx * 0.2).r;
	vec3 col = base_color * (0.85 + 0.15 * rib);
	col = mix(col, vec3(0.35, 0.18, 0.08), smoothstep(0.62, 0.8, rust) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.6;
	METALLIC = 0.35;
	NORMAL_MAP = vec3(0.5 + 0.35 * cos(along * rib_freq * 6.2831), 0.5, 1.0);
}
"""


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
static func paint_material(paint: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.03
	m.metallic_specular = 0.6
	apply_paint(m, paint)
	return m


static func apply_paint(m: StandardMaterial3D, paint: Dictionary) -> void:
	m.albedo_color = paint.get("color", Color(0.62, 0.025, 0.03))
	m.metallic = float(paint.get("metallic", 0.1))
	m.roughness = float(paint.get("roughness", 0.2))


static func std(color: Color, roughness := 0.5, metallic := 0.0, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


static func glass(tint := Color(0.03, 0.03, 0.05, 0.75)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic = 0.2
	m.metallic_specular = 1.0
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.02
	return m


static func chrome() -> StandardMaterial3D:
	if not _cache.has("mat_chrome"):
		_cache["mat_chrome"] = std(Color(0.85, 0.86, 0.9), 0.12, 1.0)
	return _cache["mat_chrome"]


static func rubber() -> StandardMaterial3D:
	if not _cache.has("mat_rubber"):
		_cache["mat_rubber"] = std(Color(0.035, 0.035, 0.04), 0.9, 0.0)
	return _cache["mat_rubber"]


static func black_plastic() -> StandardMaterial3D:
	if not _cache.has("mat_blackplastic"):
		_cache["mat_blackplastic"] = std(Color(0.03, 0.03, 0.035), 0.55, 0.0)
	return _cache["mat_blackplastic"]


static func carbon() -> StandardMaterial3D:
	if not _cache.has("mat_carbon"):
		var m := std(Color(0.05, 0.05, 0.06), 0.25, 0.5)
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		_cache["mat_carbon"] = m
	return _cache["mat_carbon"]


static func emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.3)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	return m


static func noise_texture(seed_value: int, freq: float, normal_map := false, size := 512, bump := 6.0) -> NoiseTexture2D:
	var key := "noise_%d_%f_%s_%d" % [seed_value, freq, str(normal_map), size]
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal_map:
		t.as_normal_map = true
		t.bump_strength = bump

	var result = t
	_cache[key] = result
	return result


static func road_material(asphalt: Color, wet := 0.0) -> ShaderMaterial:
	var s := Shader.new()
	s.code = ROAD_SHADER
	var m := ShaderMaterial.new()
	m.shader = s
	m.set_shader_parameter("noise_tex", noise_texture(11, 0.02))
	m.set_shader_parameter("noise_nrm", noise_texture(12, 0.03, true, 512, 4.0))
	m.set_shader_parameter("asphalt", asphalt)
	m.set_shader_parameter("wetness", wet)
	return m


static func ground_material(a: Color, b: Color, c: Color, roughness := 0.95, tile := 0.0) -> ShaderMaterial:
	var s := Shader.new()
	s.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = s
	m.set_shader_parameter("noise_tex", noise_texture(21, 0.015))
	m.set_shader_parameter("noise_nrm", noise_texture(22, 0.05, true, 512, 3.0))
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("color_c", c)
	m.set_shader_parameter("roughness_value", roughness)
	m.set_shader_parameter("tile_size", tile)
	return m


static func water_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = s
	m.set_shader_parameter("noise_nrm", noise_texture(31, 0.04, true, 512, 5.0))
	return m


static func container_material(color: Color) -> ShaderMaterial:
	var sh: Shader = _shader("shader_container", CONTAINER_SHADER)
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("noise_tex", noise_texture(41, 0.03, false, 256))
	return m


static func sky_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = SKY_SHADER
	var m := ShaderMaterial.new()
	m.shader = s
	return m


static func leaf_material(kind: String, tint := Color.WHITE) -> ShaderMaterial:
	var sh: Shader = _shader("shader_leaf", LEAF_SHADER)
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("leaf_tex", needle_texture() if kind == "needle" else leaf_texture())
	m.set_shader_parameter("tint", tint)
	if kind == "needle":
		m.set_shader_parameter("backlight_color", Color(0.08, 0.14, 0.05))
		m.set_shader_parameter("wind", 0.5)
	return m


static func bark_material(tint := Color.WHITE) -> ShaderMaterial:
	var sh: Shader = _shader("shader_bark", BARK_SHADER)
	var m := ShaderMaterial.new()
	m.shader = sh
	var tex: Array = bark_textures()
	m.set_shader_parameter("bark_tex", tex[0])
	m.set_shader_parameter("bark_nrm", tex[1])
	m.set_shader_parameter("tint", tint)
	return m


# ---------------------------------------------------------------------------
# Generated images
# ---------------------------------------------------------------------------
## A sprig with several leaves on a twig – used on leaf cards (RGBA, alpha-tested).
static func leaf_texture() -> ImageTexture:
	if _cache.has("tex_leaf"):
		return _cache["tex_leaf"]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.18, 0.28, 0.08, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.08
	# twig from bottom centre towards the top
	var leaves: Array = []
	for i in 9:
		var t := 0.18 + float(i) * 0.09
		var side := -1.0 if i % 2 == 0 else 1.0
		var base := Vector2(0.5 + sin(t * 3.0) * 0.03, 1.0 - t)
		var ang := -PI * 0.5 + side * rng.randf_range(0.55, 0.95)
		if i == 8:
			ang = -PI * 0.5
		var length := rng.randf_range(0.17, 0.23) * (1.1 - t * 0.35)
		var dir := Vector2(cos(ang), sin(ang))
		leaves.append([base + dir * length, dir, length, length * rng.randf_range(0.36, 0.46), rng.randf_range(-0.08, 0.08)])
	for y in size:
		for x in size:
			var p := Vector2((float(x) + 0.5) / size, (float(y) + 0.5) / size)
			var col := Color(0, 0, 0, 0)
			# twig
			var tx := 0.5 + sin((1.0 - p.y) * 3.0) * 0.03
			if absf(p.x - tx) < 0.009 and p.y > 0.12:
				col = Color(0.25, 0.17, 0.09, 1.0)
			for l in leaves:
				var c: Vector2 = l[0]
				var d: Vector2 = l[1]
				var half_len: float = l[2]
				var width: float = l[3]
				var rel := p - c
				var u := rel.dot(d) / half_len
				var v := rel.dot(Vector2(-d.y, d.x))
				if absf(u) >= 1.0:
					continue
				var tt := (u + 1.0) * 0.5
				var w := width * pow(sin(PI * tt), 0.75) * (1.0 - 0.25 * tt)
				if absf(v) < w:
					var edge := absf(v) / w
					var vein := 1.0 - smoothstep(0.0, 0.06, absf(v) / width)
					var side_vein := 0.5 + 0.5 * sin((u * 9.0 + absf(v) / width * 4.0) * PI)
					var nv := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
					var hue: float = l[4]
					var base_col := Color(0.20 + hue, 0.40 + hue * 0.5, 0.09).lerp(Color(0.34, 0.52, 0.12), tt * 0.5)
					base_col = base_col.darkened(edge * 0.25 + side_vein * 0.06)
					base_col = base_col.lerp(Color(0.52, 0.62, 0.25), vein * 0.6)
					base_col = base_col * (0.85 + nv * 0.3)
					base_col.a = 1.0
					col = base_col
			img.set_pixel(x, y, col)
	img.generate_mipmaps()

	var result = ImageTexture.create_from_image(img)
	_cache["tex_leaf"] = result
	return result


## Pine needle spray: a thin stem with many needles pointing outward.
static func needle_texture() -> ImageTexture:
	if _cache.has("tex_needle"):
		return _cache["tex_needle"]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.16, 0.06, 0.0))
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.2
	for y in size:
		for x in size:
			var along := (float(x) + 0.5) / size
			var off := (float(y) + 0.5) / size - 0.5
			var col := Color(0, 0, 0, 0)
			var taper := 0.46 * (1.0 - along * 0.55)
			if absf(off) < 0.012 and along < 0.97:
				col = Color(0.22, 0.15, 0.08, 1.0)
			elif absf(off) < taper and along > 0.02:
				var k := along - absf(off) * 0.7
				var f := fposmod(k / 0.028, 1.0)
				var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				if f < 0.34 + n * 0.1:
					var shade := 0.75 + 0.4 * (1.0 - absf(off) / taper)
					col = Color(0.07 * shade, 0.20 * shade + n * 0.05, 0.08 * shade, 1.0)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()

	var result = ImageTexture.create_from_image(img)
	_cache["tex_needle"] = result
	return result


## Stretched bark texture + matching normal map.
static func bark_textures() -> Array:
	if _cache.has("tex_bark"):
		return _cache["tex_bark"]
	var size := 256
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.02
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var fine := FastNoiseLite.new()
	fine.seed = 6
	fine.frequency = 0.15
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			# stretch vertically, keep it tileable by sampling a torus-like mapping
			var ax := float(x) / size * TAU
			var nx := cos(ax) * 40.0
			var nz := sin(ax) * 40.0
			var h := noise.get_noise_3d(nx, float(y) * 0.25, nz) * 0.7 + fine.get_noise_3d(nx * 2.0, float(y) * 1.2, nz * 2.0) * 0.3
			heights[y * size + x] = h * 0.5 + 0.5
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var nrm := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var h := heights[y * size + x]
			var c := Color(0.20, 0.14, 0.09).lerp(Color(0.42, 0.34, 0.25), h)
			c = c.darkened(clampf(0.35 - h, 0.0, 0.35))
			alb.set_pixel(x, y, c)
			var hl := heights[y * size + ((x - 1 + size) % size)]
			var hr := heights[y * size + ((x + 1) % size)]
			var hu := heights[((y - 1 + size) % size) * size + x]
			var hd := heights[((y + 1) % size) * size + x]
			var n := Vector3((hl - hr) * 4.0, (hu - hd) * 4.0, 1.0).normalized()
			nrm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	alb.generate_mipmaps()
	nrm.generate_mipmaps()

	var result = [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(nrm)]
	_cache["tex_bark"] = result
	return result


## Soft puffy smoke sprite.
static func smoke_texture() -> ImageTexture:
	if _cache.has("tex_smoke"):
		return _cache["tex_smoke"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 17
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	for y in size:
		for x in size:
			var p := Vector2(float(x) / size - 0.5, float(y) / size - 0.5) * 2.0
			var r := p.length()
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = pow(a, 1.6) * (0.55 + 0.9 * n)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()

	var result = ImageTexture.create_from_image(img)
	_cache["tex_smoke"] = result
	return result


## Honeycomb-ish mesh for grilles and intakes (dark, alpha-free).
static func grille_texture() -> ImageTexture:
	if _cache.has("tex_grille"):
		return _cache["tex_grille"]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var row := int(y / 8.0)
			var ox := 4 if row % 2 == 1 else 0
			var cx := fposmod(float(x + ox), 8.0) - 4.0
			var cy := fposmod(float(y), 8.0) - 4.0
			var d := maxf(absf(cx) * 0.9 + absf(cy) * 0.5, absf(cy))
			var v := 0.02 if d < 2.6 else 0.16
			img.set_pixel(x, y, Color(v, v, v * 1.05))
	img.generate_mipmaps()
	var result := ImageTexture.create_from_image(img)
	_cache["tex_grille"] = result
	return result


## Checkered start/finish texture.
static func checker_texture() -> ImageTexture:
	if _cache.has("tex_checker"):
		return _cache["tex_checker"]
	var img := Image.create(64, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 64:
			var on := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.95, 0.95) if on else Color(0.05, 0.05, 0.05))

	var result = ImageTexture.create_from_image(img)
	_cache["tex_checker"] = result
	return result
