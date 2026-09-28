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

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 asphalt : source_color = vec3(0.10, 0.10, 0.11);
uniform vec3 line_color : source_color = vec3(0.92, 0.92, 0.88);
uniform float edge_line = 0.022;
uniform float wetness = 0.0;
uniform float patch_amount = 0.5;
uniform sampler2D puddle_tex : hint_default_black, filter_linear, repeat_disable;
// road-space puddle mask (track.gd): x = metres of road per texture column, y = columns,
// z = half a lateral texel (keeps the filter inside a column)
uniform vec3 puddle_map = vec3(4096.0, 1.0, 0.016);
uniform float puddle_level = 0.0;
uniform float rain = 0.0;
uniform float night = 0.0;       // 0 day … 1 night: dry asphalt reflects much less in the dark
// photo asphalt (assets/textures/asphalt_*): fine grain + relief; a second, rotated and larger
// sample breaks up the tiling
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float asphalt_tile = 0.9;     // metres per repeat
uniform float asphalt_mean = 0.35;    // average brightness of the texture (0 = texture off)
// graffiti mode: owner colour per track cell (x = distance along the track / graffiti_len)
uniform sampler2D graffiti_tex : hint_default_transparent, filter_nearest, repeat_enable;
uniform float graffiti_len = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.23).r;
	float n2 = texture(noise_tex, wpos.xz * 0.019).r;
	float n3 = texture(noise_tex, wpos.xz * 0.004 + vec2(0.3, 0.7)).r;
	vec3 col = asphalt * (0.72 + 0.56 * n) * (0.85 + 0.3 * n2);
	vec2 tp = wpos.xz / asphalt_tile;
	float grain = 1.0;
	if (asphalt_mean > 0.0) {
		vec2 tp2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * wpos.xz / (asphalt_tile * 5.3);
		// at night: blur the fine grain (it flickers like static under the headlights)
		grain = dot(texture(asphalt_tex, tp, night * 2.5).rgb, vec3(0.3333)) / asphalt_mean;
		float grain2 = dot(texture(asphalt_tex, tp2).rgb, vec3(0.3333)) / asphalt_mean;
		col = asphalt * (0.9 + 0.2 * n) * (0.85 + 0.3 * n2) * mix(1.0, grain, 0.9 - 0.5 * night) * mix(1.0, grain2, 0.3);
	}
	col = mix(col, asphalt * 1.45, smoothstep(0.62, 0.66, n3) * patch_amount);
	float line_off = 0.14 * sin(UV.y * 0.011) + 0.06 * sin(UV.y * 0.037);
	float rubber = smoothstep(0.30, 0.0, abs(UV.x - 0.5 + line_off)) * (0.45 + 0.4 * n2);
	col *= 1.0 - rubber * 0.55;
	float edge = step(UV.x, edge_line) + step(1.0 - edge_line, UV.x);
	col = mix(col, line_color * (0.8 + 0.2 * n), clamp(edge, 0.0, 1.0));
	vec3 tag_glow = vec3(0.0);
	if (graffiti_len > 0.0) {
		vec4 g = texture(graffiti_tex, vec2(UV.y / graffiti_len, 0.5));
		// sprayed look: patchy paint, a bit denser towards the middle of the road
		float spray = (0.55 + 0.45 * smoothstep(0.35, 0.7, texture(noise_tex, wpos.xz * 0.9).r)) * (1.0 - 0.35 * abs(UV.x - 0.5) * 2.0);
		col = mix(col, g.rgb * 0.75, g.a * 0.26 * spray);
		tag_glow = g.rgb * g.a * spray * 0.02;
	}
	// wet asphalt gets darker and glossy; puddles become mirror-like with rain ripples
	float p_col = floor(UV.y / puddle_map.x);
	vec2 p_uv = vec2((p_col + clamp(UV.x, puddle_map.z, 1.0 - puddle_map.z)) / puddle_map.y, (UV.y - p_col * puddle_map.x) / puddle_map.x);
	float pm = texture(puddle_tex, p_uv).r;
	float puddle = smoothstep(1.0 - puddle_level, 1.0 - puddle_level + 0.12, pm) * step(0.01, puddle_level);
	col *= 1.0 - wetness * 0.35;
	col = mix(col, col * 0.35, puddle);
	ALBEDO = col;
	EMISSION = tag_glow;
	ROUGHNESS = mix(mix(0.86 - rubber * 0.25 - clamp(grain - 1.0, 0.0, 0.5) * 0.2, 0.16 + n * 0.1, wetness), 0.02, puddle);
	SPECULAR = mix(0.45, 0.7, max(wetness, puddle)) * mix(1.0, 0.35, night * (1.0 - puddle));
	ROUGHNESS = mix(ROUGHNESS, max(ROUGHNESS, 0.93), night * (1.0 - max(wetness, puddle)));
	vec3 nm = texture(noise_nrm, wpos.xz * 0.23).xyz;
	if (asphalt_mean > 0.0) {
		nm = mix(nm, texture(asphalt_nrm, tp, night * 2.5).xyz, 0.75);
	}
	vec3 ripple = texture(noise_nrm, wpos.xz * 1.7 + vec2(TIME * 0.9, -TIME * 0.6)).xyz;
	NORMAL_MAP = mix(nm, mix(vec3(0.5, 0.5, 1.0), ripple, 0.25 * rain), puddle);
	NORMAL_MAP_DEPTH = mix(mix(0.7, 0.18, wetness), 0.4, puddle) * (1.0 - 0.7 * night * (1.0 - puddle));
}
"""

const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
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

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.1, 0.27, 0.045);
uniform vec3 grass_b : source_color = vec3(0.17, 0.4, 0.07);
uniform vec3 grass_dry : source_color = vec3(0.26, 0.33, 0.11);
uniform vec3 forest_floor : source_color = vec3(0.07, 0.11, 0.04);
uniform vec3 dirt : source_color = vec3(0.26, 0.2, 0.13);
uniform vec3 rock : source_color = vec3(0.36, 0.35, 0.33);
uniform vec3 concrete : source_color = vec3(0.40, 0.39, 0.36);
uniform float wetness = 0.0;
// at night the headlights make the fine photo grain of gravel/asphalt flicker like static: blur it (mip bias) and flatten the relief
uniform float night = 0.0;
uniform float joints = 1.0;      // concrete slab joints (0 = seamless asphalt)
// gravel shoulder along the road edge and gravel traps on the outside of tight corners
uniform sampler2D edge_tex : filter_linear, repeat_disable;   // r: distance to the road edge / 8 m, g: trap
uniform vec2 edge_origin = vec2(0.0);
uniform vec2 edge_inv_size = vec2(0.0);
uniform float shoulder = 0.0;    // 0 = off (playground)
uniform float trap_w = 4.6;
uniform vec3 gravel : source_color = vec3(0.47, 0.44, 0.39);
// photo textures: gravel (shoulders, traps, harbor ground) and asphalt (playground pad)
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float photo_tex = 0.0;   // 1 when the photo textures are set
uniform int paved_mode = 0;      // paved ground: 0 concrete slabs, 1 gravel, 2 asphalt

varying vec3 wpos;
varying vec4 splat;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	splat = COLOR;
}

// wavy outer border of the gravel shoulder (identical in grass.gd)
float shoulder_w(vec2 p) {
	return 1.8 + 0.28 * sin(p.x * 0.53 + p.y * 0.21) + 0.2 * sin(p.y * 1.37 - p.x * 0.83) + 0.1 * sin(p.x * 3.1 + p.y * 2.3);
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
	// paved ground: concrete apron / gravel yard (harbor), asphalt pad (playground)
	float pv = clamp(splat.r, 0.0, 1.0);
	vec2 rot_p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	vec3 pnrm = vec3(0.5, 0.5, 1.0);
	if (pv > 0.001) {
		vec3 c = concrete * (0.78 + 0.35 * n2) * (0.88 + 0.24 * n3);
		if (photo_tex > 0.5 && paved_mode == 1) {
			vec3 gt = texture(gravel_tex, p / 1.7, night * 2.5).rgb;
			float g2 = dot(texture(gravel_tex, rot_p / 8.3).rgb, vec3(0.3333)) / 0.49;
			c = gt * 0.82 * mix(1.0, g2, 0.35) * (0.85 + 0.3 * n3);
			pnrm = texture(gravel_nrm, p / 1.7, night * 2.5).xyz;
		} else if (photo_tex > 0.5 && paved_mode == 2) {
			float a1 = dot(texture(asphalt_tex, p / 0.9, night * 2.5).rgb, vec3(0.3333)) / 0.35;
			float a2 = dot(texture(asphalt_tex, rot_p / 4.8).rgb, vec3(0.3333)) / 0.35;
			c = concrete * mix(1.0, a1, 0.9) * mix(1.0, a2, 0.3) * (0.88 + 0.24 * n3);
			pnrm = texture(asphalt_nrm, p / 0.9, night * 2.5).xyz;
		} else {
			vec2 gg = abs(fract(p / 6.0) - 0.5);
			float joint = smoothstep(0.486, 0.496, max(gg.x, gg.y));
			c *= 1.0 - joint * 0.4 * joints;
		}
		c = mix(c, c * 0.55, smoothstep(0.66, 0.8, n5) * 0.6);
		col = mix(col, c, pv);
	}
	// gravel: shoulder band and traps
	float gv = 0.0;
	if (shoulder > 0.5 && edge_inv_size.x > 0.0) {
		vec2 e = texture(edge_tex, (p - edge_origin) * edge_inv_size).rg;
		float ed = e.r * 8.0;
		gv = (1.0 - smoothstep(-0.08, 0.08, ed - shoulder_w(p))) * (1.0 - pv);
		float tb = trap_w + 0.3 * sin(p.x * 0.37 + p.y * 0.51);
		gv = max(gv, smoothstep(0.3, 0.6, e.g) * (1.0 - smoothstep(tb - 0.1, tb + 0.1, ed)));
		if (gv > 0.001) {
			float s1 = texture(noise_tex, p * 2.7).r;
			float s2 = texture(noise_tex, p * 7.9 + vec2(0.3, 0.6)).r;
			vec3 gc = gravel * (0.72 + 0.45 * s1) * (0.85 + 0.3 * n1);
			gc = mix(gc, vec3(0.62, 0.6, 0.56), smoothstep(0.62, 0.75, s2) * 0.6);   // light pebbles
			gc = mix(gc, vec3(0.2, 0.19, 0.17), smoothstep(0.3, 0.2, s2) * 0.5);      // dark pebbles
			if (photo_tex > 0.5) {
				float g2 = dot(texture(gravel_tex, rot_p / 8.3).rgb, vec3(0.3333)) / 0.49;
				gc = texture(gravel_tex, p / 1.7, night * 2.5).rgb * 0.9 * mix(1.0, g2, 0.35) * (0.85 + 0.3 * n1);
			}
			// tyre-worn, darker gravel next to the asphalt
			gc *= mix(0.8, 1.0, smoothstep(0.0, 0.9, ed));
			col = mix(col, gc, gv);
		}
	}
	float wet = wetness * (1.0 - rk * 0.4);
	ALBEDO = col * (1.0 - wet * 0.38);
	ROUGHNESS = mix(mix(mix(0.96, 0.86, pv), 0.92, gv), mix(0.5, 0.18, pv), wet);
	SPECULAR = 0.35 + wet * 0.2;
	NORMAL_MAP = texture(noise_nrm, p * 0.37).xyz;
	if (photo_tex > 0.5) {
		NORMAL_MAP = mix(NORMAL_MAP, pnrm, pv * step(0.5, float(paved_mode)));
		NORMAL_MAP = mix(NORMAL_MAP, texture(gravel_nrm, p / 1.7, night * 2.5).xyz, gv);
	} else {
		NORMAL_MAP = mix(NORMAL_MAP, texture(noise_nrm, p * 2.3).xyz, gv);
	}
	NORMAL_MAP_DEPTH = mix(mix(1.1, 0.6, max(pv, wet * 0.6)), 1.6, gv) * (1.0 - 0.7 * night);
}
"""

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// dithered LOD cross-fade: the camera distance to the chunk picks which pixels this LOD keeps;
// the neighbouring LOD keeps exactly the other ones (no popping, no holes)
global uniform vec3 main_cam_pos;
uniform vec4 lod_fade = vec4(-2.0, -1.0, 1e9, 2e9);   // per LOD level: its own material copy (scenery.gd)
varying float lod_in;
varying float lod_out;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 1.0;
uniform float alpha_cut = 0.45;
uniform vec3 backlight_color : source_color = vec3(0.22, 0.32, 0.08);
uniform float wetness = 0.0;

varying vec3 inst_tint;

void vertex() {
	// per tree (MultiMesh instance) distance: every tree fades on its own, no chunk-wide pop
	float lod_d = distance((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, main_cam_pos);
	lod_in = smoothstep(lod_fade.x, lod_fade.y, lod_d);
	lod_out = smoothstep(lod_fade.z, lod_fade.w, lod_d);
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
	float lod_h = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (lod_h < 1.0 - lod_in || lod_h > 1.0 - lod_out) {
		discard;
	}
	vec4 t = texture(leaf_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * tint * inst_tint * (1.0 - wetness * 0.2);
	// alpha to coverage: smooth leaf edges with MSAA that don't sparkle in motion
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_tex, 0));
	ROUGHNESS = mix(0.72, 0.35, wetness);
	SPECULAR = 0.25 + wetness * 0.25;
	BACKLIGHT = backlight_color * inst_tint;
}
"""

const FAR_TREE_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

// dithered LOD cross-fade: the camera distance to the chunk picks which pixels this LOD keeps;
// the neighbouring LOD keeps exactly the other ones (no popping, no holes)
global uniform vec3 main_cam_pos;
uniform vec4 lod_fade = vec4(-2.0, -1.0, 1e9, 2e9);   // per LOD level: its own material copy (scenery.gd)
varying float lod_in;
varying float lod_out;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 foliage : source_color = vec3(0.15, 0.36, 0.07);
uniform vec3 needles : source_color = vec3(0.06, 0.21, 0.07);
uniform vec3 bark : source_color = vec3(0.2, 0.15, 0.1);
uniform vec3 backlight_color : source_color = vec3(0.12, 0.18, 0.05);

varying vec3 inst_tint;
varying vec3 wpos;
varying float is_leaf;

void vertex() {
	// per tree (MultiMesh instance) distance: every tree fades on its own, no chunk-wide pop
	float lod_d = distance((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, main_cam_pos);
	lod_in = smoothstep(lod_fade.x, lod_fade.y, lod_d);
	lod_out = smoothstep(lod_fade.z, lod_fade.w, lod_d);
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
	float lod_h = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (lod_h < 1.0 - lod_in || lod_h > 1.0 - lod_out) {
		discard;
	}
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

// dithered LOD cross-fade: the camera distance to the chunk picks which pixels this LOD keeps;
// the neighbouring LOD keeps exactly the other ones (no popping, no holes)
global uniform vec3 main_cam_pos;
uniform vec4 lod_fade = vec4(-2.0, -1.0, 1e9, 2e9);   // per LOD level: its own material copy (scenery.gd)
varying float lod_in;
varying float lod_out;

uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 1.0;

void vertex() {
	// per tree (MultiMesh instance) distance: every tree fades on its own, no chunk-wide pop
	float lod_d = distance((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, main_cam_pos);
	lod_in = smoothstep(lod_fade.x, lod_fade.y, lod_d);
	lod_out = smoothstep(lod_fade.z, lod_fade.w, lod_d);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp((VERTEX.y - 2.0) * 0.09, 0.0, 1.4);
	float sway = sin(TIME * 1.5 + wp.x * 0.31 + wp.z * 0.23) * 0.05;
	VERTEX.x += sway * wind * h;
	VERTEX.z += sway * 0.6 * wind * h;
}

void fragment() {
	float lod_h = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (lod_h < 1.0 - lod_in || lod_h > 1.0 - lod_out) {
		discard;
	}
	ALBEDO = texture(bark_tex, UV).rgb * COLOR.rgb * tint;
	NORMAL_MAP = texture(bark_nrm, UV).xyz;
	NORMAL_MAP_DEPTH = 1.4;
	ROUGHNESS = 0.92;
}
"""

const SKY_SHADER := """
shader_type sky;
// the expensive atmosphere + clouds run at half resolution; sun disk, moon and stars stay sharp
render_mode use_half_res_pass;

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
// physically based atmosphere (single scattering: Rayleigh for the blue sky and red dusk,
// Mie for the haze and the bright halo around the sun)
uniform float physical = 1.0;     // 0 = old colour gradient only
uniform float sky_energy = 0.085; // scattered light -> scene brightness
uniform float haze = 1.0;         // Mie (aerosol) density: > 1 in rain and mist

const float R_PLANET = 6371e3;
const float R_ATMOS = 6471e3;
const vec3 K_RLH = vec3(5.5e-6, 13.0e-6, 22.4e-6);
const float K_MIE = 21e-6;
const float SH_RLH = 8e3;
const float SH_MIE = 1.2e3;
const float G_MIE = 0.76;
const float I_SUN = 22.0;

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

// ray / sphere (centre at the origin): far intersection distance, < 0 if none
vec2 rsi(vec3 r0, vec3 rd, float sr) {
	float b = 2.0 * dot(rd, r0);
	float c = dot(r0, r0) - sr * sr;
	float d = b * b - 4.0 * c;
	if (d < 0.0) return vec2(1e5, -1e5);
	float sq = sqrt(d);
	return vec2((-b - sq) * 0.5, (-b + sq) * 0.5);
}

// light scattered towards the eye along `rd` (observer 1 m above the ground)
vec3 atmosphere(vec3 rd, vec3 sd, int steps_i, int steps_j) {
	vec3 r0 = vec3(0.0, R_PLANET + 1.0, 0.0);
	vec2 p = rsi(r0, rd, R_ATMOS);
	if (p.x > p.y) return vec3(0.0);
	p.y = min(p.y, rsi(r0, rd, R_PLANET).x > 0.0 ? rsi(r0, rd, R_PLANET).x : p.y);
	float step_i = (p.y - max(p.x, 0.0)) / float(steps_i);
	float t_i = max(p.x, 0.0);
	vec3 tot_r = vec3(0.0);
	vec3 tot_m = vec3(0.0);
	float od_r_i = 0.0;
	float od_m_i = 0.0;
	float mu = dot(rd, sd);
	float mumu = mu * mu;
	float gg = G_MIE * G_MIE;
	float p_rlh = 3.0 / (16.0 * PI) * (1.0 + mumu);
	float p_mie = 3.0 / (8.0 * PI) * ((1.0 - gg) * (mumu + 1.0)) / (pow(1.0 + gg - 2.0 * mu * G_MIE, 1.5) * (2.0 + gg));
	float k_mie = K_MIE * haze;
	for (int i = 0; i < steps_i; i++) {
		vec3 pos_i = r0 + rd * (t_i + step_i * 0.5);
		float h_i = length(pos_i) - R_PLANET;
		float od_r_step = exp(-h_i / SH_RLH) * step_i;
		float od_m_step = exp(-h_i / SH_MIE) * step_i;
		od_r_i += od_r_step;
		od_m_i += od_m_step;
		float step_j = rsi(pos_i, sd, R_ATMOS).y / float(steps_j);
		float t_j = 0.0;
		float od_r_j = 0.0;
		float od_m_j = 0.0;
		for (int j = 0; j < steps_j; j++) {
			vec3 pos_j = pos_i + sd * (t_j + step_j * 0.5);
			float h_j = length(pos_j) - R_PLANET;
			od_r_j += exp(-h_j / SH_RLH) * step_j;
			od_m_j += exp(-h_j / SH_MIE) * step_j;
			t_j += step_j;
		}
		vec3 attn = exp(-(k_mie * (od_m_i + od_m_j) + K_RLH * (od_r_i + od_r_j)));
		tot_r += od_r_step * attn;
		tot_m += od_m_step * attn;
		t_i += step_i;
	}
	return I_SUN * (p_rlh * K_RLH * tot_r + p_mie * k_mie * tot_m);
}

// colour of direct sunlight after crossing the atmosphere (sunset red, noon white)
vec3 sun_transmittance(vec3 sd) {
	vec3 r0 = vec3(0.0, R_PLANET + 1.0, 0.0);
	float len = rsi(r0, sd, R_ATMOS).y;
	float st = len / 8.0;
	float od_r = 0.0;
	float od_m = 0.0;
	for (int j = 0; j < 8; j++) {
		float h = length(r0 + sd * (st * (float(j) + 0.5))) - R_PLANET;
		od_r += exp(-h / SH_RLH) * st;
		od_m += exp(-h / SH_MIE) * st;
	}
	return exp(-(K_RLH * od_r + K_MIE * haze * od_m));
}

// sky without the sharp sun disk / moon / stars; alpha = cloud cover (hides stars and disk)
vec4 sky_color(vec3 dir, bool cubemap) {
	float h = dir.y;
	vec3 sd = normalize(sun_dir);
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.5));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}
	float d = dot(dir, sd);
	float above = smoothstep(-0.08, 0.02, sd.y);
	vec3 sun_tint = sun_color;
	if (physical > 0.0) {
		// scattering from the sun; the old gradient only carries the night sky
		vec3 ad = vec3(dir.x, max(dir.y, 0.0), dir.z);
		vec3 phys = atmosphere(normalize(ad + vec3(0.0, 0.0005, 0.0)), sd, cubemap ? 8 : 12, cubemap ? 3 : 4) * sky_energy;
		if (h < 0.0) {
			phys = mix(phys, ground_color * dot(phys, vec3(0.33)) * 2.0, clamp(-h * 4.0, 0.0, 1.0));
		}
		float night_w = 1.0 - smoothstep(-0.16, 0.02, sd.y);
		col = mix(col, phys + col * night_w, physical);
		vec3 tr = sun_transmittance(normalize(vec3(sd.x, max(sd.y, 0.01), sd.z)));
		sun_tint = mix(sun_color, tr / max(max(tr.r, tr.g), max(tr.b, 0.05)) * vec3(1.0, 0.97, 0.92), physical);
	} else {
		float glow = pow(max(d, 0.0), 6.0) * sun_glow + pow(max(d, 0.0), 80.0) * 0.8;
		col += sun_color * glow * above;
	}
	if (moon_amount > 0.0) {
		vec3 md = normalize(moon_dir);
		col += vec3(0.25, 0.3, 0.45) * pow(max(dot(dir, md), 0.0), 30.0) * moon_amount * 0.3;
	}
	float cover = 0.0;
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.08);
		int oct = cubemap ? 4 : 6;
		// high, thin veil
		float n2 = fbm(uv * 0.22 + cloud_offset * 0.35 + vec2(7.0, 3.0), 4);
		float veil = smoothstep(0.52, 0.85, n2) * 0.3 * (1.0 - cloud_darkness);
		vec3 lit = mix(cloud_color, cloud_color * sun_tint, 0.55 * physical);
		col = mix(col, lit, veil * smoothstep(0.0, 0.25, h));
		// main cloud layer, lit from the sun side in the colour of the sunlight
		float n = fbm(uv * 0.8 + cloud_offset, oct);
		float cov = 1.0 - cloud_coverage;
		float dens = smoothstep(cov - 0.05, cov + 0.3, n);
		float n_sun = fbm(uv * 0.8 + cloud_offset + sd.xz * 0.12, oct);
		float shade = clamp((n_sun - n) * 5.0 + 0.5, 0.0, 1.0);
		vec3 cc = mix(lit, cloud_shade, shade);
		cc = mix(cc, cloud_shade * 0.55, cloud_darkness * (0.4 + 0.6 * dens));
		// silver lining towards the sun
		cc += sun_tint * pow(max(d, 0.0), 8.0) * 0.6 * (1.0 - dens) * above;
		float a = dens * smoothstep(0.0, 0.1, h) * 0.96;
		col = mix(col, cc, a);
		cover = max(a, veil);
	}
	// overcast: the whole sky turns flat grey
	col = mix(col, mix(cloud_shade, cloud_color, 0.35) * (0.6 + 0.4 * clamp(h * 2.0 + 0.5, 0.0, 1.0)), cloud_darkness * 0.55);
	return vec4(col, cover);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec4 base;
	if (AT_CUBEMAP_PASS) {
		base = sky_color(dir, true);
	} else if (AT_HALF_RES_PASS) {
		base = sky_color(dir, false);
		COLOR = base.rgb;
		ALPHA = base.a;
	} else {
		base = HALF_RES_COLOR;
	}
	if (!AT_HALF_RES_PASS) {
		vec3 col = base.rgb;
		float clear = 1.0 - base.a;
		float h = dir.y;
		vec3 sd = normalize(sun_dir);
		float d = dot(dir, sd);
		float above = smoothstep(-0.08, 0.02, sd.y);
		if (sun_size > 0.0001) {
			vec3 tr = sun_transmittance(normalize(vec3(sd.x, max(sd.y, 0.01), sd.z)));
			vec3 disk_col = mix(sun_color, tr / max(max(tr.r, tr.g), max(tr.b, 0.05)), physical);
			float disk = smoothstep(cos(sun_size), cos(sun_size * 0.85), d);
			col += disk_col * disk * 25.0 * step(-0.02, h) * above * (0.25 + 0.75 * clear);
		}
		if (moon_amount > 0.0) {
			vec3 md = normalize(moon_dir);
			col += vec3(0.8, 0.85, 1.0) * smoothstep(0.9993, 0.9996, dot(dir, md)) * moon_amount * 3.0 * (0.2 + 0.8 * clear);
		}
		if (star_amount > 0.0 && h > 0.0) {
			float s = hash3(floor(dir * 420.0));
			float tw = hash3(floor(dir * 420.0) + vec3(3.0));
			col += vec3(0.9, 0.92, 1.0) * step(0.9975, s) * star_amount * (0.4 + 0.6 * tw) * smoothstep(0.0, 0.25, h) * clear;
		}
		COLOR = col * exposure;
	} else {
		COLOR *= exposure;
	}
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
	var at: Texture2D = photo_texture("asphalt_albedo.jpg")
	if at:
		m.set_shader_parameter("asphalt_tex", at)
		m.set_shader_parameter("asphalt_nrm", photo_texture("asphalt_normal.png"))
		m.set_shader_parameter("asphalt_mean", 0.35)
	else:
		m.set_shader_parameter("asphalt_mean", 0.0)
	return m


## Photo textures from assets/textures (null if missing).
static func photo_texture(file: String) -> Texture2D:
	var path := "res://assets/textures/" + file
	return load(path) if ResourceLoader.exists(path) else null


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
	var gt: Texture2D = photo_texture("gravel_albedo.jpg")
	if gt:
		m.set_shader_parameter("gravel_tex", gt)
		m.set_shader_parameter("gravel_nrm", photo_texture("gravel_normal.png"))
		m.set_shader_parameter("asphalt_tex", photo_texture("asphalt_albedo.jpg"))
		m.set_shader_parameter("asphalt_nrm", photo_texture("asphalt_normal.png"))
		m.set_shader_parameter("photo_tex", 1.0)
		m.set_shader_parameter("paved_mode", {"harbor": 1, "playground": 2}.get(track_id, 0))
	if track_id == "playground":
		m.set_shader_parameter("concrete", Color(0.12, 0.12, 0.13))
		m.set_shader_parameter("joints", 0.0)
	if track_id == "harbor":
		m.set_shader_parameter("grass_a", Color(0.12, 0.26, 0.06))
		m.set_shader_parameter("grass_b", Color(0.2, 0.36, 0.09))
		m.set_shader_parameter("grass_dry", Color(0.3, 0.33, 0.14))
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

// dithered LOD cross-fade: the camera distance to the chunk picks which pixels this LOD keeps;
// the neighbouring LOD keeps exactly the other ones (no popping, no holes)
global uniform vec3 main_cam_pos;
uniform vec4 lod_fade = vec4(-2.0, -1.0, 1e9, 2e9);   // per LOD level: its own material copy (scenery.gd)
varying float lod_in;
varying float lod_out;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 pine_size = vec2(7.2, 16.5);
uniform vec2 leaf_size = vec2(10.0, 12.0);
uniform vec2 mesh_size = vec2(10.0, 17.0);

varying vec3 tint;

void vertex() {
	// per tree (MultiMesh instance) distance: every tree fades on its own, no chunk-wide pop
	float lod_d = distance((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, main_cam_pos);
	lod_in = smoothstep(lod_fade.x, lod_fade.y, lod_d);
	lod_out = smoothstep(lod_fade.z, lod_fade.w, lod_d);
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
	float lod_h = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (lod_h < 1.0 - lod_in || lod_h > 1.0 - lod_out) {
		discard;
	}
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * tint;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(atlas, 0));
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
## Soft puff with noise. fine = wispy variant (finer, more broken-up detail) for tyre smoke.
static func smoke_texture(fine := false) -> ImageTexture:
	var key := "tex_smoke_fine" if fine else "tex_smoke"
	if _cache.has(key):
		return _cache[key]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 17 if not fine else 23
	noise.frequency = 0.045 if not fine else 0.085
	noise.fractal_octaves = 4 if not fine else 5
	for y in size:
		for x in size:
			var p := Vector2(float(x) / size - 0.5, float(y) / size - 0.5) * 2.0
			var r := p.length()
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a := clampf(1.0 - r, 0.0, 1.0)
			if fine:
				# soft falloff, thin wisps: the noise decides where there is smoke at all
				a = pow(a, 1.3) * smoothstep(0.25, 0.8, n) * 1.25
			else:
				a = pow(a, 1.6) * (0.55 + 0.9 * n)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()

	var result = ImageTexture.create_from_image(img)
	_cache[key] = result
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
