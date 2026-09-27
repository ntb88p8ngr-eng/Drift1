extends Node3D
## Lens flares for the sun (glare, star rays, anamorphic streak, ghosts along the axis through the
## screen centre, halo) and a small, soft one for the moon. Drawn as a full-screen additive quad;
## the occlusion test samples the depth buffer around the light's screen position, so trees, hills
## and cars hide the flare.

const FLARE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 src_uv = vec2(0.5);
uniform float intensity = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.75);
uniform float ghosts = 1.0;
uniform float glare_size = 0.14;
uniform float aspect = 1.7778;

const float GP[6] = float[](0.28, 0.55, 0.82, 1.18, 1.5, 1.95);
const float GS[6] = float[](0.035, 0.06, 0.02, 0.09, 0.045, 0.14);
const vec3 GC[6] = vec3[](vec3(1.0, 0.7, 0.4), vec3(0.4, 0.9, 0.6), vec3(1.0, 0.5, 0.8), vec3(0.4, 0.6, 1.0), vec3(1.0, 0.9, 0.5), vec3(0.5, 0.7, 1.0));

varying float vis;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
	// occlusion: fraction of sky pixels (depth 0 with reversed Z) around the light position
	float v = 0.0;
	float tot = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			vec2 uv = src_uv + vec2(float(x) / aspect, float(y)) * 0.006;
			if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
				continue;
			}
			float d = textureLod(depth_tex, uv, 0.0).r;
			v += d <= 0.0000001 ? 1.0 : 0.0;
			tot += 1.0;
		}
	}
	vis = tot > 0.0 ? v / tot : 0.0;
}

float hex(vec2 p, float r) {
	p = abs(p);
	return max(p.x * 0.866 + p.y * 0.5, p.y) - r;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 a = vec2(aspect, 1.0);
	vec2 p = (uv - src_uv) * a;
	vec2 axis = (vec2(0.5) - src_uv) * a;
	float r = length(p);
	vec3 col = vec3(0.0);
	col += tint * exp(-r / (glare_size * 0.15)) * 0.8;
	col += tint * exp(-r / glare_size) * 0.12;
	float ang = atan(p.y, p.x);
	float rays = pow(abs(sin(ang * 6.0 + 0.4)), 30.0) + 0.6 * pow(abs(sin(ang * 9.0 + 1.3)), 50.0);
	col += tint * rays * exp(-r / (glare_size * 0.8)) * 0.18 * ghosts;
	col += tint * vec3(0.75, 0.85, 1.0) * exp(-abs(p.y) * 260.0) * exp(-abs(p.x) * 2.5) * 0.22 * ghosts;
	for (int i = 0; i < 6; i++) {
		vec2 c = axis * GP[i];
		float d = hex(p - c, GS[i]);
		float body = (1.0 - smoothstep(-0.006, 0.004, d)) * 0.08;
		float rim = exp(-abs(d) * 180.0) * 0.07;
		col += GC[i] * tint * (body + rim) * ghosts;
	}
	float halo = exp(-abs(r - 0.42) * 70.0) * 0.035 * ghosts;
	col += vec3(0.9, 0.7, 1.0) * halo;
	ALBEDO = col * intensity * vis;
}
"""

var atmosphere
var _sun_quad: MeshInstance3D
var _moon_quad: MeshInstance3D
var _sun_mat: ShaderMaterial
var _moon_mat: ShaderMaterial


func setup(p_atmosphere) -> void:
	atmosphere = p_atmosphere
	var r := _make()
	_sun_quad = r[0]
	_sun_mat = r[1]
	r = _make()
	_moon_quad = r[0]
	_moon_mat = r[1]
	_moon_mat.set_shader_parameter("tint", Color(0.7, 0.8, 1.0))
	_moon_mat.set_shader_parameter("ghosts", 0.25)
	_moon_mat.set_shader_parameter("glare_size", 0.08)


func _make() -> Array:
	var sh := Shader.new()
	sh.code = FLARE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 100
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	mi.visible = false
	add_child(mi)
	return [mi, mat]


func _process(_delta: float) -> void:
	var on := bool(Game.settings.get("lens_flares", true)) and atmosphere != null
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		on = false
	_update(_sun_quad, _sun_mat, cam, atmosphere.sun_direction() if on else Vector3.UP, (atmosphere.sun_visibility() if on else 0.0) * 1.0, true)
	_update(_moon_quad, _moon_mat, cam, atmosphere.moon_direction() if on else Vector3.UP, (atmosphere.moon_visibility() if on else 0.0) * 0.5, false)


func _update(quad: MeshInstance3D, mat: ShaderMaterial, cam: Camera3D, dir: Vector3, strength: float, is_sun: bool) -> void:
	if strength <= 0.01 or cam == null:
		quad.visible = false
		return
	var far_point := cam.global_position + dir * 1000.0
	if cam.is_position_behind(far_point):
		quad.visible = false
		return
	var size := get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(far_point)
	var uv := sp / size
	# fade out when the light leaves the screen
	var outside := maxf(maxf(-uv.x, uv.x - 1.0), maxf(-uv.y, uv.y - 1.0))
	var edge := 1.0 - smoothstep(0.0, 0.2, outside)
	if edge <= 0.0:
		quad.visible = false
		return
	quad.visible = true
	quad.global_position = cam.global_position - cam.global_transform.basis.z * 2.0
	mat.set_shader_parameter("src_uv", uv)
	mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	var k := strength * edge
	if is_sun:
		var col: Color = atmosphere.sun.light_color
		mat.set_shader_parameter("tint", Color(1.0, 0.92, 0.8).lerp(col, 0.5))
		# low sun: bigger, warmer flare
		k *= lerpf(1.2, 0.7, clampf(atmosphere.sun_elevation / 50.0, 0.0, 1.0))
	mat.set_shader_parameter("intensity", k)
