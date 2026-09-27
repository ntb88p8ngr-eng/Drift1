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
uniform sampler2D puddle_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 puddle_rect = vec4(0.0, 0.0, 0.001, 0.001);   // origin xz, 1/size xz
uniform float puddle_level = 0.0;
uniform float rain = 0.0;

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
	// wet asphalt gets darker and glossy; puddles become mirror-like with rain ripples
	float pm = texture(puddle_tex, (wpos.xz - puddle_rect.xy) * puddle_rect.zw).r;
	float puddle = smoothstep(1.0 - puddle_level, 1.0 - puddle_level + 0.12, pm) * step(0.01, puddle_level);
	col *= 1.0 - wetness * 0.35;
	col = mix(col, col * 0.35, puddle);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.86 - rubber * 0.25, 0.16 + n * 0.1, wetness), 0.02, puddle);
	SPECULAR = mix(0.45, 0.7, max(wetness, puddle));
	vec3 nm = texture(noise_nrm, wpos.xz * 0.23).xyz;
	vec3 ripple = texture(noise_nrm, wpos.xz * 1.7 + vec2(TIME * 0.9, -TIME * 0.6)).xyz;
	NORMAL_MAP = mix(nm, mix(vec3(0.5, 0.5, 1.0), ripple, 0.25 * rain), puddle);
	NORMAL_MAP_DEPTH = mix(mix(0.7, 0.18, wetness), 0.4, puddle);
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

const TERRAIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.09, 0.19, 0.045);
uniform vec3 grass_b : source_color = vec3(0.16, 0.28, 0.07);
uniform vec3 grass_dry : source_color = vec3(0.3, 0.28, 0.13);
uniform vec3 forest_floor : source_color = vec3(0.085, 0.075, 0.045);
uniform vec3 dirt : source_color = vec3(0.26, 0.2, 0.13);
uniform vec3 rock : source_color = vec3(0.36, 0.35, 0.33);
uniform vec3 concrete : source_color = vec3(0.40, 0.39, 0.36);
uniform float wetness = 0.0;

varying vec3 wpos;
varying vec4 splat;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	splat = COLOR;
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p * 0.045).r;
	float n2 = texture(noise_tex, p * 0.31).r;
	float n3 = texture(noise_tex, p * 0.0071 + vec2(0.37, 0.11)).r;
	float n4 = texture(noise_tex, p * 0.93 + vec2(0.5, 0.2)).r;
	float n5 = texture(noise_tex, p * 0.017 + vec2(0.71, 0.43)).r;
	vec3 g = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1));
	g = mix(g, grass_dry, clamp(smoothstep(0.6, 0.85, n3) * 0.5 + splat.a * smoothstep(0.5, 0.75, n5) * 0.35, 0.0, 1.0));
	g *= 0.78 + 0.42 * n2;
	vec3 col = g;
	float forest = clamp(splat.b, 0.0, 1.0);
	vec3 ff = forest_floor * (0.75 + 0.6 * n2) + vec3(0.03, 0.02, 0.0) * n4;
	col = mix(col, ff, forest * (0.75 + 0.25 * n1));
	float d = clamp(splat.g + smoothstep(0.66, 0.8, n2 * n1 * 1.6) * 0.2 * (1.0 - forest), 0.0, 1.0);
	col = mix(col, dirt * (0.72 + 0.55 * n4), d);
	// rock on steep slopes (noise sampled along the slope to avoid stretching)
	float slope = 1.0 - wnrm.y;
	float rk = smoothstep(0.26, 0.42, slope + (n2 - 0.5) * 0.14);
	vec2 rp = vec2(p.x + p.y * 0.3, wpos.y * 1.5 + p.y * 0.2);
	vec3 rcol = rock * (0.62 + 0.7 * texture(noise_tex, rp * 0.21).r) * (0.85 + 0.3 * n4);
	col = mix(col, rcol, rk);
	// concrete apron (harbor)
	float pv = clamp(splat.r, 0.0, 1.0);
	if (pv > 0.001) {
		vec3 c = concrete * (0.78 + 0.35 * n2) * (0.88 + 0.24 * n3);
		vec2 gg = abs(fract(p / 6.0) - 0.5);
		float joint = smoothstep(0.486, 0.496, max(gg.x, gg.y));
		c *= 1.0 - joint * 0.4;
		c = mix(c, c * 0.55, smoothstep(0.66, 0.8, n5) * 0.6);
		col = mix(col, c, pv);
	}
	float wet = wetness * (1.0 - rk * 0.4);
	ALBEDO = col * (1.0 - wet * 0.38);
	ROUGHNESS = mix(mix(0.96, 0.86, pv), mix(0.5, 0.18, pv), wet);
	SPECULAR = 0.35 + wet * 0.2;
	NORMAL_MAP = texture(noise_nrm, p * 0.37).xyz;
	NORMAL_MAP_DEPTH = mix(1.1, 0.6, max(pv, wet * 0.6));
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
uniform float wetness = 0.0;

varying vec3 inst_tint;

void vertex() {
	// per-instance colour variation (MultiMesh custom data, alpha = 1 marks it as set)
	inst_tint = INSTANCE_CUSTOM.a > 0.5 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y * 0.11, 0.0, 1.6);
	float sway = sin(TIME * 1.5 + wp.x * 0.31 + wp.z * 0.23) * 0.07 + sin(TIME * 3.9 + wp.y * 1.7 + wp.x * 0.9) * 0.025;
	VERTEX.x += sway * wind * h;
	VERTEX.z += sway * 0.6 * wind * h;
	VERTEX.y += sin(TIME * 4.3 + wp.x * 2.1 + wp.z * 1.3) * 0.015 * wind * h;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * tint * inst_tint * (1.0 - wetness * 0.2);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = mix(0.72, 0.35, wetness);
	SPECULAR = 0.25 + wetness * 0.25;
	BACKLIGHT = backlight_color * inst_tint;
}
"""

const FAR_TREE_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 foliage : source_color = vec3(0.17, 0.3, 0.07);
uniform vec3 needles : source_color = vec3(0.07, 0.17, 0.07);
uniform vec3 bark : source_color = vec3(0.2, 0.15, 0.1);
uniform vec3 backlight_color : source_color = vec3(0.12, 0.18, 0.05);

varying vec3 inst_tint;
varying vec3 wpos;
varying float is_leaf;

void vertex() {
	inst_tint = INSTANCE_CUSTOM.a > 0.5 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	// the mesh holds a conifer (UV.x = 0) and a broadleaf tree (UV.x = 1); custom alpha picks one
	float want_leaf = INSTANCE_CUSTOM.a > 0.9 ? 1.0 : 0.0;
	is_leaf = UV.x;
	if (abs(UV.x - want_leaf) > 0.5) {
		VERTEX = vec3(0.0);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.35 + wpos.y * 0.21).r;
	float n2 = texture(noise_tex, wpos.xz * 1.3 - wpos.y * 0.5).r;
	vec3 base = mix(needles, foliage, is_leaf);
	vec3 c = base * COLOR.rgb * inst_tint * (0.62 + 0.55 * n) * (0.8 + 0.35 * n2);
	c = mix(bark * (0.7 + 0.5 * n2), c, COLOR.a);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = backlight_color * inst_tint * COLOR.a;
}
"""

const ROCK_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 stone : source_color = vec3(0.38, 0.37, 0.35);
uniform vec3 moss : source_color = vec3(0.13, 0.2, 0.06);
uniform float wetness = 0.0;

varying vec3 lpos;
varying vec3 wnrm;
varying vec3 inst_tint;

void vertex() {
	lpos = VERTEX;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	inst_tint = INSTANCE_CUSTOM.a > 0.5 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
}

void fragment() {
	vec3 b = abs(normalize(lpos));
	b /= (b.x + b.y + b.z);
	float n = texture(noise_tex, lpos.yz * 0.9).r * b.x + texture(noise_tex, lpos.xz * 0.9).r * b.y + texture(noise_tex, lpos.xy * 0.9).r * b.z;
	float fine = texture(noise_tex, lpos.xz * 4.0 + lpos.y).r;
	vec3 c = stone * inst_tint * (0.55 + 0.7 * n) * (0.85 + 0.3 * fine);
	float m = smoothstep(0.45, 0.8, wnrm.y + (n - 0.5) * 0.5);
	c = mix(c, moss * (0.7 + 0.6 * fine), m * 0.85);
	ALBEDO = c * (1.0 - wetness * 0.3);
	ROUGHNESS = mix(0.88, 0.35, wetness * (1.0 - m * 0.5));
	NORMAL_MAP = texture(noise_nrm, lpos.xz * 1.7 + lpos.y * 0.7).xyz;
	NORMAL_MAP_DEPTH = 1.6;
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
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform float sun_size = 0.035;
uniform float sun_glow = 0.35;
uniform float cloud_coverage = 0.45;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.58, 0.66);
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_darkness = 0.0;
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

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 sd = normalize(sun_dir);
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.5));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}
	// sun glow and disk (sun_dir points towards the sun; hidden below the horizon)
	float d = dot(dir, sd);
	float above = smoothstep(-0.08, 0.02, sd.y);
	float glow = pow(max(d, 0.0), 6.0) * sun_glow + pow(max(d, 0.0), 80.0) * 0.8;
	col += sun_color * glow * above;
	if (sun_size > 0.0001) {
		float disk = smoothstep(cos(sun_size), cos(sun_size * 0.85), d);
		col += sun_color * disk * 25.0 * step(-0.02, h) * above;
	}
	if (moon_amount > 0.0) {
		vec3 md = normalize(moon_dir);
		float mdd = dot(dir, md);
		col += vec3(0.8, 0.85, 1.0) * smoothstep(0.9993, 0.9996, mdd) * moon_amount * 3.0;
		col += vec3(0.25, 0.3, 0.45) * pow(max(mdd, 0.0), 30.0) * moon_amount * 0.3;
	}
	if (star_amount > 0.0 && h > 0.0) {
		float s = hash3(floor(dir * 420.0));
		float tw = hash3(floor(dir * 420.0) + vec3(3.0));
		col += vec3(0.9, 0.92, 1.0) * step(0.9975, s) * star_amount * (0.4 + 0.6 * tw) * smoothstep(0.0, 0.25, h) * (1.0 - cloud_coverage);
	}
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.08);
		int oct = AT_CUBEMAP_PASS ? 4 : 6;
		// high, thin veil
		float n2 = fbm(uv * 0.22 + cloud_offset * 0.35 + vec2(7.0, 3.0), 4);
		float veil = smoothstep(0.52, 0.85, n2) * 0.3 * (1.0 - cloud_darkness);
		col = mix(col, cloud_color, veil * smoothstep(0.0, 0.25, h));
		// main cloud layer, lit from the sun side
		float n = fbm(uv * 0.8 + cloud_offset, oct);
		float cov = 1.0 - cloud_coverage;
		float dens = smoothstep(cov - 0.05, cov + 0.3, n);
		float n_sun = fbm(uv * 0.8 + cloud_offset + sd.xz * 0.12, oct);
		float shade = clamp((n_sun - n) * 5.0 + 0.5, 0.0, 1.0);
		vec3 cc = mix(cloud_color, cloud_shade, shade);
		cc = mix(cc, cloud_shade * 0.55, cloud_darkness * (0.4 + 0.6 * dens));
		cc += sun_color * pow(max(d, 0.0), 8.0) * 0.6 * (1.0 - dens) * above;
		col = mix(col, cc, dens * smoothstep(0.0, 0.1, h) * 0.96);
	}
	// overcast: the whole sky turns flat grey
	col = mix(col, mix(cloud_shade, cloud_color, 0.35) * (0.6 + 0.4 * clamp(h * 2.0 + 0.5, 0.0, 1.0)), cloud_darkness * 0.55);
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
uniform bool instanced = false;   // MultiMesh: colour per container from INSTANCE_CUSTOM

varying vec3 opos;
varying vec3 onrm;
varying vec3 inst_col;
varying float seed;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	inst_col = INSTANCE_CUSTOM.rgb;
	seed = INSTANCE_CUSTOM.a;
}

void fragment() {
	float along = abs(onrm.x) > 0.5 ? opos.z : opos.x;
	// fade the ribs out where they get finer than a pixel (no moire in the distance)
	float rib_aa = clamp(1.5 - fwidth(along * rib_freq) * 3.0, 0.0, 1.0);
	float rib = sin(along * rib_freq * 6.2831) * rib_aa;
	float rust = texture(noise_tex, opos.xy * 0.3 + opos.zx * 0.2 + vec2(seed * 7.0, seed * 3.0)).r;
	vec3 base = instanced ? inst_col : base_color;
	// door end: darker frame, locking bars
	float door = abs(onrm.z) > 0.5 && instanced ? 1.0 : 0.0;
	float bars = door * step(0.92, fract(opos.x * 1.6 + 0.25));
	vec3 col = base * (0.85 + 0.15 * rib * (1.0 - door)) * (1.0 - bars * 0.45);
	col = mix(col, vec3(0.35, 0.18, 0.08), smoothstep(0.62, 0.8, rust) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.6;
	METALLIC = 0.35;
	NORMAL_MAP = vec3(0.5 + 0.35 * cos(along * rib_freq * 6.2831) * rib_aa, 0.5, 1.0);
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


static func terrain_material(track_id: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("shader_terrain", TERRAIN_SHADER)
	m.set_shader_parameter("noise_tex", noise_texture(21, 0.015))
	m.set_shader_parameter("noise_nrm", noise_texture(22, 0.05, true, 512, 3.0))
	if track_id == "harbor":
		m.set_shader_parameter("grass_a", Color(0.14, 0.2, 0.07))
		m.set_shader_parameter("grass_b", Color(0.22, 0.28, 0.11))
		m.set_shader_parameter("grass_dry", Color(0.36, 0.32, 0.18))
	return m


static func water_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = s
	m.set_shader_parameter("noise_nrm", noise_texture(31, 0.04, true, 512, 5.0))
	return m


static func container_material(color: Color, instanced := false) -> ShaderMaterial:
	var sh: Shader = _shader("shader_container", CONTAINER_SHADER)
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("noise_tex", noise_texture(41, 0.03, false, 256))
	m.set_shader_parameter("instanced", instanced)
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
	var tex: Texture2D = leaf_texture()
	if kind == "oak":
		tex = oak_leaf_texture()
	elif kind == "needle":
		tex = needle_texture()
	elif kind == "fern":
		tex = fern_texture()
	m.set_shader_parameter("leaf_tex", tex)
	m.set_shader_parameter("tint", tint)
	if kind == "needle":
		m.set_shader_parameter("backlight_color", Color(0.08, 0.14, 0.05))
		m.set_shader_parameter("wind", 0.5)
		m.set_shader_parameter("alpha_cut", 0.4)
	elif kind == "fern":
		m.set_shader_parameter("backlight_color", Color(0.12, 0.2, 0.04))
		m.set_shader_parameter("wind", 2.2)
	return m


## Billboard impostor for trees beyond the 3D view distance: a camera-facing (upright) card from a
## two-cell atlas (conifer | broadleaf, picked like the far LOD via custom alpha), tinted per tree.
const IMPOSTOR_SHADER := """
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_burley, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 pine_size = vec2(7.2, 16.5);
uniform vec2 leaf_size = vec2(10.0, 12.0);
uniform vec2 mesh_size = vec2(10.0, 17.0);

varying vec3 tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	float leaf = INSTANCE_CUSTOM.a > 0.9 ? 1.0 : 0.0;
	tint = INSTANCE_CUSTOM.rgb;
	vec2 size = mix(pine_size, leaf_size, leaf) * s;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec2 q = vec2(VERTEX.x / mesh_size.x, VERTEX.y / mesh_size.y);   // x -0.5..0.5, y 0..1
	vec3 w = origin + right * q.x * size.x + vec3(0.0, q.y * size.y - 0.3 * s, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(to_cam + vec3(0.0, 0.9, 0.0)), 0.0)).xyz);
	UV = vec2(UV.x * 0.5 + leaf * 0.5, UV.y);
}

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * tint;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = vec3(0.08, 0.12, 0.04) * tint;
}
"""


static func impostor_material() -> ShaderMaterial:
	if _cache.has("mat_impostor"):
		return _cache["mat_impostor"]
	var m := ShaderMaterial.new()
	m.shader = _shader("shader_impostor", IMPOSTOR_SHADER)
	m.set_shader_parameter("atlas", impostor_texture())
	_cache["mat_impostor"] = m
	return m


## 512 x 256 atlas: a layered conifer (left) and a round broadleaf crown (right), lit from above.
static func impostor_texture() -> ImageTexture:
	if _cache.has("tex_impostor"):
		return _cache["tex_impostor"]
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.18, 0.07, 0.0))
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var blobs: Array = []
	for k in 7:
		var a := TAU * k / 7.0
		blobs.append([Vector2(0.5 + cos(a) * rng.randf_range(0.16, 0.24), 0.36 + sin(a) * rng.randf_range(0.1, 0.18)), rng.randf_range(0.17, 0.24)])
	blobs.append([Vector2(0.5, 0.3), 0.26])
	for y in h:
		for x in w:
			var cell := 0 if x < 256 else 1
			var u := float(x % 256) / 256.0
			var v := float(y) / 256.0          # 0 = top
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var col := Color(0, 0, 0, 0)
			if cell == 0:
				# trunk
				if v > 0.86 and absf(u - 0.5) < 0.025:
					col = Color(0.2, 0.15, 0.1, 1.0)
				# five tiers, each a flared skirt; narrower towards the top
				var tier := clampf((v - 0.02) / 0.84, 0.0, 1.0) * 5.0
				var f := fposmod(tier, 1.0)
				var taper := 0.12 + 0.88 * (tier / 5.0)
				var half := (0.18 + 0.82 * f) * taper * 0.48 + (n - 0.5) * 0.05
				if v > 0.02 and v < 0.88 and absf(u - 0.5) < half:
					var shade := 0.7 + 0.45 * (1.0 - f) - absf(u - 0.5) / maxf(half, 0.01) * 0.25
					col = Color(0.07, 0.17, 0.07) * shade * (0.75 + 0.5 * n)
					col.a = 1.0
			else:
				if v > 0.62 and absf(u - 0.5) < 0.035 - (v - 0.62) * -0.02:
					col = Color(0.22, 0.16, 0.1, 1.0)
				var inside := 0.0
				var light := 0.0
				for b in blobs:
					var c: Vector2 = b[0]
					var r: float = b[1]
					var d := Vector2(u, v).distance_to(c) / (r * (0.92 + 0.16 * n))
					if d < 1.0:
						inside = 1.0
						light = maxf(light, (1.0 - d) * 0.5 + (c.y - v + r) / (2.0 * r) * 0.5)
				if inside > 0.0:
					col = Color(0.17, 0.3, 0.07) * (0.6 + 0.6 * light) * (0.75 + 0.5 * n)
					col.a = 1.0
			img.set_pixel(x, y, col)
	var t := ImageTexture.create_from_image(coverage_mipmaps(img, 0.45))
	_cache["tex_impostor"] = t
	return t


static func far_tree_material(foliage: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("shader_far_tree", FAR_TREE_SHADER)
	m.set_shader_parameter("noise_tex", noise_texture(61, 0.05, false, 256))
	m.set_shader_parameter("foliage", foliage)
	return m


static func rock_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("shader_rock", ROCK_SHADER)
	m.set_shader_parameter("noise_tex", noise_texture(71, 0.03, false, 256))
	m.set_shader_parameter("noise_nrm", noise_texture(72, 0.06, true, 256, 5.0))
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
## Mipmaps for alpha-tested foliage that keep the same coverage at every level (otherwise leaf and
## needle cards thin out and trees look bare in the distance).
static func coverage_mipmaps(src: Image, cutoff: float) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var base: Image = src.duplicate()
	if base.has_mipmaps():
		base.clear_mipmaps()
	var target := _coverage(base.get_data(), 1.0, cutoff)
	var data := base.get_data()
	var lw := w
	var lh := h
	while lw > 1 or lh > 1:
		lw = maxi(lw / 2, 1)
		lh = maxi(lh / 2, 1)
		var lvl: Image = base.duplicate()
		lvl.resize(lw, lh, Image.INTERPOLATE_LANCZOS if lw >= 4 else Image.INTERPOLATE_BILINEAR)
		var bytes := lvl.get_data()
		var lo := 0.5
		var hi := 6.0
		for _it in 12:
			var mid := (lo + hi) * 0.5
			if _coverage(bytes, mid, cutoff) < target:
				lo = mid
			else:
				hi = mid
		var sc := (lo + hi) * 0.5
		for i in range(3, bytes.size(), 4):
			bytes[i] = mini(int(float(bytes[i]) * sc), 255)
		data.append_array(bytes)
	return Image.create_from_data(w, h, true, Image.FORMAT_RGBA8, data)


static func _coverage(bytes: PackedByteArray, scale: float, cutoff: float) -> float:
	var thr := cutoff * 255.0 / scale
	var count := 0
	var total := bytes.size() / 4
	for i in range(3, bytes.size(), 4):
		if float(bytes[i]) >= thr:
			count += 1
	return float(count) / float(maxi(total, 1))


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
	var result = ImageTexture.create_from_image(coverage_mipmaps(img, 0.45))
	_cache["tex_leaf"] = result
	return result


## Oak twig: dark, leathery leaves with rounded lobes.
static func oak_leaf_texture() -> ImageTexture:
	if _cache.has("tex_oak"):
		return _cache["tex_oak"]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.22, 0.06, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var noise := FastNoiseLite.new()
	noise.seed = 8
	noise.frequency = 0.09
	var leaves: Array = []
	for i in 8:
		var t := 0.2 + float(i) * 0.1
		var side := -1.0 if i % 2 == 0 else 1.0
		var base := Vector2(0.5 + sin(t * 2.5) * 0.03, 1.0 - t)
		var ang := -PI * 0.5 + side * rng.randf_range(0.5, 1.0)
		if i == 7:
			ang = -PI * 0.5
		var length := rng.randf_range(0.19, 0.25) * (1.1 - t * 0.3)
		var dir := Vector2(cos(ang), sin(ang))
		leaves.append([base + dir * length, dir, length, length * rng.randf_range(0.42, 0.5), rng.randf_range(-0.05, 0.05), rng.randf() * TAU])
	for y in size:
		for x in size:
			var p := Vector2((float(x) + 0.5) / size, (float(y) + 0.5) / size)
			var col := Color(0, 0, 0, 0)
			var tx := 0.5 + sin((1.0 - p.y) * 2.5) * 0.03
			if absf(p.x - tx) < 0.011 and p.y > 0.14:
				col = Color(0.3, 0.2, 0.1, 1.0)
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
				# obovate outline with 4-5 rounded lobes per side
				var lobes := 0.62 + 0.38 * absf(sin(tt * PI * 4.5 + float(l[5]) * 0.1))
				var w := width * pow(sin(PI * tt), 0.6) * (0.75 + 0.35 * tt) * lobes
				if absf(v) < w:
					var edge := absf(v) / w
					var vein := 1.0 - smoothstep(0.0, 0.05, absf(v) / width)
					var nv := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
					var hue: float = l[4]
					var base_col := Color(0.13 + hue, 0.27 + hue * 0.5, 0.07).lerp(Color(0.22, 0.36, 0.1), tt * 0.4)
					base_col = base_col.darkened(edge * 0.2)
					base_col = base_col.lerp(Color(0.4, 0.46, 0.2), vein * 0.5)
					base_col = base_col * (0.85 + nv * 0.3)
					base_col.a = 1.0
					col = base_col
			img.set_pixel(x, y, col)
	var result = ImageTexture.create_from_image(coverage_mipmaps(img, 0.45))
	_cache["tex_oak"] = result
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
			var taper := 0.47 * (1.0 - along * 0.5)
			if absf(off) < 0.014 and along < 0.97:
				col = Color(0.22, 0.15, 0.08, 1.0)
			elif absf(off) < taper and along > 0.02:
				var k := along - absf(off) * 0.7
				var f := fposmod(k / 0.022, 1.0)
				var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				if f < 0.5 + n * 0.12:
					var shade := 0.75 + 0.4 * (1.0 - absf(off) / taper)
					col = Color(0.07 * shade, 0.20 * shade + n * 0.05, 0.08 * shade, 1.0)
			img.set_pixel(x, y, col)
	var result = ImageTexture.create_from_image(coverage_mipmaps(img, 0.4))
	_cache["tex_needle"] = result
	return result


## Fern frond: a midrib with alternating leaflets (u across, v along the frond).
static func fern_texture() -> ImageTexture:
	if _cache.has("tex_fern"):
		return _cache["tex_fern"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.2, 0.05, 0.0))
	var noise := FastNoiseLite.new()
	noise.seed = 13
	noise.frequency = 0.15
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / size - 0.5
			var v := (float(y) + 0.5) / size
			var col := Color(0, 0, 0, 0)
			var half := 0.46 * (1.0 - v * 0.75)
			if absf(u) < 0.025:
				col = Color(0.2, 0.28, 0.08, 1.0)
			elif absf(u) < half:
				# leaflets: slanted stripes along the frond
				var k := v * 14.0 + absf(u) * 3.2
				var f := fposmod(k, 1.0)
				if f < 0.62 - absf(u) / half * 0.3:
					var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
					var shade := 0.8 + 0.35 * (1.0 - absf(u) / half)
					col = Color(0.13 * shade, 0.3 * shade + n * 0.05, 0.07 * shade, 1.0)
			img.set_pixel(x, y, col)
	var result := ImageTexture.create_from_image(coverage_mipmaps(img, 0.45))
	_cache["tex_fern"] = result
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
