extends Node3D
## Neo Tokyo's edge: a deep bank of mist along the square border of the city. It starts 50 m inside
## the border and thickens outwards – many soft drifting layers, 22 m high, the air itself getting
## murkier the deeper you drive in – with low ground fog in front of it that the cars cut through
## (their tracks stay clear for a few seconds, then the fog drifts back). At the border itself it
## turns you round: you come out of it heading back into the city.

const TexKit = preload("res://scripts/util/tex_kit.gd")

const DEPTH := 50.0                # the mist starts this far inside the border
const LAYERS := 9                  # mist sheets from there out to past the border
const OUTER := 40.0                # … and this far beyond it
const HEIGHT := 22.0
const STEP := 8.0
const TURN_DEPTH := 4.0            # this far past the border it turns you round
const GROUND_IN := 40.0            # ground fog reaches this much further in than the mist
const TRAIL := 32                  # car positions remembered for the wake in the ground fog
const TRAIL_DT := 0.12
const TRAIL_LIFE := 4.0

const MIST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 fog_col : source_color = vec3(0.8, 0.82, 0.86);
uniform float night = 0.0;
uniform float layer = 0.0;        // 0 inner … 1 outer
uniform float height = 22.0;
varying vec3 wp;
varying float base;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; base = UV.x; }
void fragment() {
	float hy = wp.y - base;      // above the ground under the sheet
	// thick low down, thinning out upwards, ragged top; slowly rolling wisps
	float along = wp.x + wp.z + layer * 37.0;
	vec2 uv = vec2(along * 0.018 + TIME * 0.01, hy * 0.04 - TIME * 0.006);
	float n = texture(noise_tex, uv).r * 0.55 + texture(noise_tex, uv * 2.7 + vec2(-TIME * 0.017, 0.31)).r * 0.45;
	float top = height * (0.55 + 0.45 * n);
	float hf = 1.0 - smoothstep(top * 0.25, top, hy);
	ALBEDO = mix(fog_col, fog_col * 0.12 + vec3(0.02, 0.025, 0.04), night);
	float dens = mix(0.18, 0.62, layer);
	ALPHA = clamp(hf * (0.3 + 0.7 * n) * dens, 0.0, 0.92);
}
"""

const GROUND_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 fog_col : source_color = vec3(0.82, 0.84, 0.88);
uniform float night = 0.0;
uniform float sheet = 0.0;        // 0 lowest … 1 top sheet
uniform vec4 trail[32];           // xyz = where a car was, w = how old (s); w < 0 = unused
uniform vec4 rect_in;             // inner edge of the ground fog (x0, z0, x1, z1)
uniform float ramp = 40.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wp.xz * 0.02 + vec2(TIME * 0.012, -TIME * 0.008) + sheet * 0.37;
	float n = texture(noise_tex, uv).r * 0.6 + texture(noise_tex, uv * 3.1 + vec2(TIME * 0.02, 0.0)).r * 0.4;
	// fades in from the inner edge towards the border
	float dx = max(rect_in.x - wp.x, wp.x - rect_in.z);
	float dz = max(rect_in.y - wp.z, wp.z - rect_in.w);
	float inward = max(dx, dz);
	float edge = smoothstep(0.0, ramp, inward);
	// the cars' wake: cleared where they drove, closing again as it gets older
	float clear = 1.0;
	for (int i = 0; i < 32; i++) {
		vec4 t = trail[i];
		if (t.w < 0.0) { continue; }
		float r = mix(3.2, 0.6, clamp(t.w / 4.0, 0.0, 1.0));
		float d = length(wp.xz - t.xz) + n * 1.2;
		clear = min(clear, smoothstep(r, r + 2.2, d));
	}
	ALBEDO = mix(fog_col, fog_col * 0.12 + vec3(0.02, 0.025, 0.04), night);
	ALPHA = clamp(edge * clear * (0.25 + 0.75 * n) * mix(0.55, 0.3, sheet), 0.0, 0.85);
}
"""

var world
var rect: Rect2                 # the border (inside it: the city)
var mist_rect: Rect2            # where the mist begins (DEPTH inside the border)
var _mats: Array = []
var _ground_mats: Array = []
var _cool := 0.0
var _trail: Array = []          # [Vector3, age]
var _trail_t := 0.0
## ground height under a point (x, z) – flat (0) in the city, the dunes in the desert
var ground_fn: Callable
var turn_msg := "Hier draußen ist nichts – zurück in die Stadt"
## false: no mist at all, only the border that turns you round (the desert)
var show := true


func _ground(x: float, z: float) -> float:
	return float(ground_fn.call(x, z)) if ground_fn.is_valid() else 0.0


func setup(p_world, p_rect: Rect2, p_ground := Callable(), p_msg := "", p_show := true) -> void:
	world = p_world
	rect = p_rect
	ground_fn = p_ground
	show = p_show
	if p_msg != "":
		turn_msg = p_msg
	if not show:
		mist_rect = rect.grow(-DEPTH)
		set_process(false)
		return
	mist_rect = rect.grow(-DEPTH)
	var noise: Texture2D = TexKit.noise_texture(733, 0.02)
	# the mist wall: sheets from DEPTH inside out to OUTER beyond the border
	for li in LAYERS:
		var f := float(li) / float(LAYERS - 1)
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = MIST_SHADER
		m.set_shader_parameter("noise_tex", noise)
		m.set_shader_parameter("layer", f)
		m.set_shader_parameter("height", HEIGHT)
		m.render_priority = li
		_mats.append(m)
		_add_ring(rect.grow(-DEPTH + (DEPTH + OUTER) * f), m, "Mist%d" % li)
	# ground fog: flat sheets over the band from GROUND_IN inside the mist out past the border
	var inner := mist_rect.grow(-GROUND_IN)
	for si in 3:
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = GROUND_SHADER
		m.set_shader_parameter("noise_tex", noise)
		m.set_shader_parameter("sheet", si / 2.0)
		m.set_shader_parameter("rect_in", Vector4(inner.position.x, inner.position.y, inner.end.x, inner.end.y))
		m.set_shader_parameter("ramp", GROUND_IN + 10.0)
		m.render_priority = -1 + si
		_ground_mats.append(m)
		_add_band(inner, rect.grow(OUTER), 0.35 + si * 0.55, m, "GroundFog%d" % si)
	_set_trail()


## A vertical ribbon along the four sides of `r`.
func _add_ring(r: Rect2, m: Material, label: String) -> void:
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
			var h0 := _ground(p0.x, p0.y)
			var h1 := _ground(p1.x, p1.y)
			var v := [Vector3(p0.x, h0 - 0.5, p0.y), Vector3(p1.x, h1 - 0.5, p1.y), Vector3(p1.x, h1 + HEIGHT, p1.y), Vector3(p0.x, h0 + HEIGHT, p0.y)]
			var hs := [h0, h1, h1, h0]
			for t in [[0, 1, 2], [0, 2, 3]]:
				for q in t:
					st.set_uv(Vector2(hs[q], 0.0))
					st.add_vertex(v[q])
	_add_mesh(st.commit(), m, label)


## A flat frame between rectangles `a` (inside) and `b` (outside) at height y.
func _add_band(a: Rect2, b: Rect2, y: float, m: Material, label: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[Vector2(b.position.x, b.position.y), Vector2(b.end.x, b.position.y), Vector2(b.end.x, a.position.y), Vector2(b.position.x, a.position.y)],
		[Vector2(b.position.x, a.end.y), Vector2(b.end.x, a.end.y), Vector2(b.end.x, b.end.y), Vector2(b.position.x, b.end.y)],
		[Vector2(b.position.x, a.position.y), Vector2(a.position.x, a.position.y), Vector2(a.position.x, a.end.y), Vector2(b.position.x, a.end.y)],
		[Vector2(a.end.x, a.position.y), Vector2(b.end.x, a.position.y), Vector2(b.end.x, a.end.y), Vector2(a.end.x, a.end.y)],
	]
	for q in quads:
		# split into a grid so the sheets follow the (flat) city ground evenly and sort well
		var cell := 40.0 if not ground_fn.is_valid() else 8.0     # (fine enough to follow dunes)
		var nx := maxi(int((q[1] as Vector2).distance_to(q[0]) / cell), 1)
		var nz := maxi(int((q[3] as Vector2).distance_to(q[0]) / cell), 1)
		for ix in nx:
			for iz in nz:
				var p := []
				for c in [[ix, iz], [ix + 1, iz], [ix + 1, iz + 1], [ix, iz + 1]]:
					var u := float(c[0]) / nx
					var w := float(c[1]) / nz
					var top: Vector2 = (q[0] as Vector2).lerp(q[1], u)
					var bot: Vector2 = (q[3] as Vector2).lerp(q[2], u)
					var xz := top.lerp(bot, w)
					p.append(Vector3(xz.x, y + _ground(xz.x, xz.y), xz.y))
				for t in [[0, 1, 2], [0, 2, 3]]:
					for k in t:
						st.add_vertex(p[k])
	_add_mesh(st.commit(), m, label)


func _add_mesh(mesh: Mesh, m: Material, label: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 50.0
	add_child(mi)


func set_night(n: float) -> void:
	for m in _mats + _ground_mats:
		(m as ShaderMaterial).set_shader_parameter("night", n)


func _set_trail() -> void:
	var arr: Array = []
	for i in TRAIL:
		if i < _trail.size():
			var t: Array = _trail[i]
			arr.append(Vector4((t[0] as Vector3).x, (t[0] as Vector3).y, (t[0] as Vector3).z, float(t[1])))
		else:
			arr.append(Vector4(0, 0, 0, -1))
	for m in _ground_mats:
		(m as ShaderMaterial).set_shader_parameter("trail", arr)


## How far into the mist p is: 0 at its inner edge (or inside the city), 1 at the border.
func depth_at(p: Vector3) -> float:
	var dx := maxf(mist_rect.position.x - p.x, p.x - mist_rect.end.x)
	var dz := maxf(mist_rect.position.y - p.z, p.z - mist_rect.end.y)
	return clampf(maxf(dx, dz) / DEPTH, 0.0, 1.5)


func _process(delta: float) -> void:
	# the wake: every car near the fog leaves a cleared track that closes again
	for t in _trail:
		t[1] = float(t[1]) + delta
	while not _trail.is_empty() and float(_trail[0][1]) > TRAIL_LIFE:
		_trail.pop_front()
	_trail_t -= delta
	if _trail_t <= 0.0 and world != null:
		_trail_t = TRAIL_DT
		for car in world.cars.values():
			if is_instance_valid(car) and car.visible and (car as RigidBody3D).linear_velocity.length() > 2.0:
				var p: Vector3 = car.global_position
				if not mist_rect.grow(-GROUND_IN - 10.0).has_point(Vector2(p.x, p.z)):
					_trail.append([p, 0.0])
		while _trail.size() > TRAIL:
			_trail.pop_front()
	_set_trail()
	# the air itself thickens towards the border (where the camera is)
	var cam := get_viewport().get_camera_3d()
	if cam and world and world.atmosphere:
		var d := depth_at(cam.global_position)
		world.atmosphere.set_fog_boost(1.0 + d * d * 60.0)


func _exit_tree() -> void:
	if world and is_instance_valid(world.atmosphere):
		world.atmosphere.set_fog_boost(1.0)


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
		world.hud.show_message("NEBEL", turn_msg, Color(0.8, 0.85, 0.95), 2.0)
