extends Node3D
## Neo Tokyo's edge: a bank of low fog drifting along the square border of the city (a little in
## from its very edge). Drive into it and you come out of it again turned round, heading back in.

const TexKit = preload("res://scripts/util/tex_kit.gd")

const LAYERS := [0.0, 5.0, 10.0]   # sheets of fog, metres outwards from the border
const HEIGHT := 11.0
const STEP := 8.0
const TURN_DEPTH := 4.0            # this far into the fog it turns you round

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 fog_col : source_color = vec3(0.8, 0.82, 0.86);
uniform float night = 0.0;
uniform float layer = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// thick at the ground, thinning out upwards; slowly drifting wisps
	float hf = 1.0 - smoothstep(0.5, 9.0, wp.y);
	float along = wp.x + wp.z + layer * 17.0;
	vec2 uv = vec2(along * 0.025 + TIME * 0.012, wp.y * 0.05);
	float n = texture(noise_tex, uv).r * 0.6 + texture(noise_tex, uv * 2.3 + vec2(-TIME * 0.02, 0.3)).r * 0.4;
	ALBEDO = mix(fog_col, fog_col * 0.1 + vec3(0.02, 0.025, 0.04), night);
	ALPHA = clamp(hf * (0.35 + 0.65 * n) * (0.55 + 0.25 * layer), 0.0, 0.95);
}
"""

var world
var rect: Rect2                 # the border (inside it: the city)
var _mats: Array = []
var _cool := 0.0


func setup(p_world, p_rect: Rect2) -> void:
	world = p_world
	rect = p_rect
	var noise: Texture2D = TexKit.noise_texture(733, 0.02)
	for li in LAYERS.size():
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = FOG_SHADER
		m.set_shader_parameter("noise_tex", noise)
		m.set_shader_parameter("layer", float(li))
		m.render_priority = li
		_mats.append(m)
		var r := rect.grow(float(LAYERS[li]))
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 4:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 4]
			var n := maxi(int(a.distance_to(b) / STEP), 1)
			for j in n:
				var p0 := a.lerp(b, float(j) / n)
				var p1 := a.lerp(b, float(j + 1) / n)
				var v := [Vector3(p0.x, -0.5, p0.y), Vector3(p1.x, -0.5, p1.y), Vector3(p1.x, HEIGHT, p1.y), Vector3(p0.x, HEIGHT, p0.y)]
				for t in [[0, 1, 2], [0, 2, 3]]:
					for q in t:
						st.add_vertex(v[q])
		var mi := MeshInstance3D.new()
		mi.name = "Fog%d" % li
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func set_night(n: float) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("night", n)


func _physics_process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	if world == null or world.local_car == null or _cool > 0.0:
		return
	var car = world.local_car
	if not is_instance_valid(car) or not (car is RigidBody3D):
		return
	var p: Vector3 = car.global_position
	# how far out past the border, and which way is back in
	var out := Vector2.ZERO
	if p.x < rect.position.x:
		out.x = p.x - rect.position.x
	elif p.x > rect.end.x:
		out.x = p.x - rect.end.x
	if p.z < rect.position.y:
		out.y = p.z - rect.position.y
	elif p.z > rect.end.y:
		out.y = p.z - rect.end.y
	if out.length() < TURN_DEPTH:
		return
	# turned round: mirrored at the border, back on the near side of the fog, heading in
	var rb := car as RigidBody3D
	var v := rb.linear_velocity
	var n3 := Vector3(out.x, 0, out.y).normalized()        # outwards
	var vin := v - n3 * 2.0 * minf(v.dot(n3), 0.0) if v.dot(n3) < 0.0 else v - n3 * 2.0 * v.dot(n3)
	var spd := v.length() * 0.6
	var dir := Vector3(vin.x, 0, vin.z).normalized() if Vector2(vin.x, vin.z).length() > 1.0 else -n3
	var back := Vector3(clampf(p.x, rect.position.x + 2.0, rect.end.x - 2.0), p.y + 0.3, clampf(p.z, rect.position.y + 2.0, rect.end.y - 2.0))
	car.place(Transform3D(Basis.looking_at(dir, Vector3.UP), back))
	rb.linear_velocity = dir * spd
	_cool = 1.0
	if world.hud:
		world.hud.show_message("NEBEL", "Hier draußen ist nichts – zurück in die Stadt", Color(0.8, 0.85, 0.95), 2.0)
