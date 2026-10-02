extends Control
## A 3D direction arrow for the HUD: a thick bevelled arrow seen from above at an isometric angle
## (its own little 3D world in a transparent SubViewport). It turns smoothly to `yaw` (0 = straight
## ahead, positive = to the right), bobs over its soft shadow and runs a light along the chevrons on
## its back. `tint` sets the colour (orange: the way to go, red: wrong way).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")

const BODY_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 tint : source_color = vec3(1.0, 0.55, 0.1);
uniform float glow = 0.35;
varying vec3 vcol;
void vertex() { vcol = COLOR.rgb; }
void fragment() {
	// COLOR.r: 1 on the top face, darker on the bevels and sides
	vec3 c = tint * mix(0.45, 1.0, vcol.r);
	ALBEDO = c;
	ROUGHNESS = 0.28;
	METALLIC = 0.1;
	SPECULAR = 0.7;
	EMISSION = tint * glow * vcol.r;
}
"""

const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float alpha = 0.45;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = alpha * (1.0 - smoothstep(0.35, 1.0, d));
}
"""

const CHEVRON_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col : source_color = vec3(1.0);
uniform float energy = 0.0;
void fragment() {
	// darker stripes on the arrow's back that flash white as the light runs over them
	ALBEDO = mix(col * 0.35, vec3(1.0), energy);
}
"""

var yaw := 0.0                  # where it should point (radians, + = right)
var tint := Color(1.0, 0.55, 0.1)
var _yaw_now := 0.0
var _t := 0.0
var _vp: SubViewport
var _pivot: Node3D
var _arrow: Node3D
var _shadow: MeshInstance3D
var _body_mat: ShaderMaterial
var _shadow_mat: ShaderMaterial
var _chev_mats: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := SubViewportContainer.new()
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# isometric-style view: orthographic, from behind and above
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.6
	var el := deg_to_rad(36.0)
	cam.position = Vector3(0, sin(el), cos(el)) * 10.0 + Vector3(0, 0.1, 0)
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.1, 0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-60.0), deg_to_rad(-35.0), 0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = Shader.new()
	_shadow_mat.shader.code = SHADOW_SHADER
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.6, 3.0)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = pm
	_shadow.material_override = _shadow_mat
	_shadow.position = Vector3(0, -0.45, 0)
	_pivot.add_child(_shadow)
	_arrow = Node3D.new()
	_pivot.add_child(_arrow)
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = Shader.new()
	_body_mat.shader.code = BODY_SHADER
	var body := MeshInstance3D.new()
	body.mesh = _arrow_mesh()
	body.material_override = _body_mat
	_arrow.add_child(body)
	# three chevrons on its back that light up in turn, running forward
	var cs := Shader.new()
	cs.code = CHEVRON_SHADER
	for k in 3:
		var m := ShaderMaterial.new()
		m.shader = cs
		var ci := MeshInstance3D.new()
		ci.mesh = _chevron_mesh()
		ci.material_override = m
		ci.position = Vector3(0, 0.225, 0.85 - k * 0.36)
		_arrow.add_child(ci)
		_chev_mats.append(m)
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	if _vp:
		_vp.size = Vector2i(maxi(int(size.x), 8), maxi(int(size.y), 8))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	# turn the short way round, smoothly
	_yaw_now += wrapf(yaw - _yaw_now, -PI, PI) * minf(delta * 7.0, 1.0)
	_pivot.rotation.y = -_yaw_now
	var bob := sin(_t * 3.6) * 0.09
	_arrow.position = Vector3(0, 0.05 + bob, 0)
	_shadow.scale = Vector3.ONE * (1.0 - bob * 0.8)
	_shadow_mat.set_shader_parameter("alpha", 0.42 - bob * 0.6)
	_body_mat.set_shader_parameter("tint", tint)
	_body_mat.set_shader_parameter("glow", 0.25 + 0.15 * sin(_t * 7.0))
	for k in _chev_mats.size():
		var ph := fposmod(_t * 1.8 - k * 0.3, 1.0)
		var e := 1.0 - smoothstep(0.0, 0.4, ph)
		(_chev_mats[k] as ShaderMaterial).set_shader_parameter("energy", e)
		(_chev_mats[k] as ShaderMaterial).set_shader_parameter("col", tint)


## The arrow, pointing -Z (screen up): shaft and head, extruded with a bevel round the top.
static func _arrow_mesh() -> ArrayMesh:
	var outline := PackedVector2Array([Vector2(-0.19, 1.2), Vector2(0.19, 1.2), Vector2(0.19, -0.15), Vector2(0.52, -0.15),
		Vector2(0.0, -1.3), Vector2(-0.52, -0.15), Vector2(-0.19, -0.15)])
	var inner := _inset(outline, 0.06)
	var st := MeshKit.new_st()
	var h := 0.22
	var hb := 0.16                  # where the bevel starts
	var top := Color(1, 1, 1)
	var bevel := Color(0.78, 0.78, 0.78)
	var side := Color(0.5, 0.5, 0.5)
	# top face (fan from the centre of the shaft-head joint; the outline is star-shaped from there)
	var c := Vector3(0, h, -0.15)
	var n := inner.size()
	for i in n:
		var a := inner[i]
		var b := inner[(i + 1) % n]
		MeshKit.tri(st, c, Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3.UP, Vector3.UP, Vector3.UP,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, top)
	# bevel and sides
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var ai := inner[i]
		var bi := inner[(i + 1) % n]
		var e := b - a
		var out := Vector3(e.y, 0, -e.x).normalized()
		if out.dot(Vector3((a.x + b.x) * 0.5, 0, (a.y + b.y) * 0.5 + 0.1)) < 0.0:
			out = -out
		var bn := (out + Vector3.UP).normalized()
		MeshKit.quad(st, Vector3(ai.x, h, ai.y), Vector3(bi.x, h, bi.y), Vector3(b.x, hb, b.y), Vector3(a.x, hb, a.y), bn,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, bevel)
		MeshKit.quad(st, Vector3(a.x, hb, a.y), Vector3(b.x, hb, b.y), Vector3(b.x, 0, b.y), Vector3(a.x, 0, a.y), out,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, side)
	return MeshKit.commit(st, null)


## The outline moved inwards by d (each corner along its bisector).
static func _inset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	# winding sign: inwards is to the left or right of each edge
	var area := 0.0
	for i in n:
		area += pts[i].cross(pts[(i + 1) % n])
	var s := 1.0 if area > 0.0 else -1.0
	for i in n:
		var p0 := pts[(i - 1 + n) % n]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var e0 := (p1 - p0).normalized()
		var e1 := (p2 - p1).normalized()
		var n0 := Vector2(-e0.y, e0.x) * s
		var n1 := Vector2(-e1.y, e1.x) * s
		var bis := (n0 + n1).normalized()
		var k := d / maxf(bis.dot(n0), 0.3)
		out.append(p1 + bis * k)
	return out


## A flat chevron pointing -Z.
static func _chevron_mesh() -> ArrayMesh:
	var st := MeshKit.new_st()
	var w := 0.045
	for sx: float in [-1.0, 1.0]:
		var a := Vector3(sx * 0.15, 0, 0.11)
		var b := Vector3(0, 0, -0.1)
		var d := Vector3(-(b - a).z, 0, (b - a).x).normalized() * w
		MeshKit.quad(st, a - d, a + d, b + d, b - d, Vector3.UP)
	return MeshKit.commit(st, null)
