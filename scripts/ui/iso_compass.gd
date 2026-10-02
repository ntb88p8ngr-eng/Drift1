extends Control
## The mission compass for the HUD: a flat 3D ring with ticks, seen from above at the same
## isometric angle as the direction arrow, and a glowing needle that always points at the mission
## goal – relative to where you're looking / driving, so it swings as the car turns. `bearing`:
## radians, 0 = straight ahead, + = to the right. `near` (0..1) makes it pulse as you arrive.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")

const RING_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 glow_col : source_color = vec3(0.2, 0.95, 0.9);
uniform float pulse = 0.0;
varying vec3 vcol;
void vertex() { vcol = COLOR.rgb; }
void fragment() {
	// COLOR.r: 1 the glowing inner edge / front tick, 0 the dark metal ring
	ALBEDO = mix(vec3(0.08, 0.09, 0.11), glow_col, vcol.r);
	METALLIC = 0.6 * (1.0 - vcol.r);
	ROUGHNESS = 0.35;
	EMISSION = glow_col * vcol.r * (0.6 + 1.2 * pulse);
}
"""

const NEEDLE_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 col : source_color = vec3(0.2, 0.95, 0.9);
uniform float glow = 0.5;
varying vec3 vcol;
void vertex() { vcol = COLOR.rgb; }
void fragment() {
	ALBEDO = col * mix(0.4, 1.0, vcol.r);
	ROUGHNESS = 0.25;
	SPECULAR = 0.7;
	EMISSION = col * glow * vcol.r;
}
"""

var bearing := 0.0
var near := 0.0
var _now := 0.0
var _t := 0.0
var _vp: SubViewport
var _needle: Node3D
var _ring_mat: ShaderMaterial
var _needle_mat: ShaderMaterial


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
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.7
	var el := deg_to_rad(40.0)
	cam.position = Vector3(0, sin(el), cos(el)) * 10.0
	_vp.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-60.0), deg_to_rad(-35.0), 0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = Shader.new()
	_ring_mat.shader.code = RING_SHADER
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh()
	ring.material_override = _ring_mat
	_vp.add_child(ring)
	_needle_mat = ShaderMaterial.new()
	_needle_mat.shader = Shader.new()
	_needle_mat.shader.code = NEEDLE_SHADER
	_needle = Node3D.new()
	_vp.add_child(_needle)
	var nm := MeshInstance3D.new()
	nm.mesh = _needle_mesh()
	nm.material_override = _needle_mat
	_needle.add_child(nm)
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	if _vp:
		_vp.size = Vector2i(maxi(int(size.x), 8), maxi(int(size.y), 8))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_now += wrapf(bearing - _now, -PI, PI) * minf(delta * 9.0, 1.0)
	_needle.rotation.y = -_now
	_needle.position.y = 0.06 + sin(_t * 3.0) * 0.02
	var pulse := near * (0.5 + 0.5 * sin(_t * 8.0))
	_ring_mat.set_shader_parameter("pulse", pulse)
	_needle_mat.set_shader_parameter("glow", 0.5 + 0.8 * pulse)


## A flat ring (outer rim dark metal, the inner edge glowing) with twelve ticks; the front one bright.
static func _ring_mesh() -> ArrayMesh:
	var st := MeshKit.new_st()
	var seg := 48
	var r0 := 0.86
	var r1 := 1.0
	var h := 0.08
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var d0 := Vector3(sin(a0), 0, -cos(a0))
		var d1 := Vector3(sin(a1), 0, -cos(a1))
		var dark := Color(0, 0, 0)
		var lit := Color(1, 1, 1)
		# top face (dark), outer wall (dark), inner wall (glowing)
		MeshKit.quad(st, d0 * r0 + Vector3(0, h, 0), d0 * r1 + Vector3(0, h, 0), d1 * r1 + Vector3(0, h, 0), d1 * r0 + Vector3(0, h, 0), Vector3.UP,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, dark)
		MeshKit.quad(st, d0 * r1, d1 * r1, d1 * r1 + Vector3(0, h, 0), d0 * r1 + Vector3(0, h, 0), (d0 + d1).normalized(),
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, dark)
		MeshKit.quad(st, d0 * r0, d1 * r0, d1 * r0 + Vector3(0, h, 0), d0 * r0 + Vector3(0, h, 0), -(d0 + d1).normalized(),
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, lit)
	for k in 12:
		var a := TAU * k / 12.0
		var d := Vector3(sin(a), 0, -cos(a))
		var big := k % 3 == 0
		var col := Color(1, 1, 1) if k == 0 else Color(0.35, 0.35, 0.35)
		MeshKit.box(st, Transform3D(Basis.looking_at(d, Vector3.UP), d * (r1 + (0.07 if big else 0.05)) + Vector3(0, h * 0.5, 0)),
			Vector3(0.05 if big else 0.035, h, 0.14 if big else 0.08), col)
	# hub
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(0.14, h * 1.6, 0.14), Color(0, 0, 0))
	return MeshKit.commit(st, null)


## The needle: a slim extruded diamond pointing -Z, its point glowing, the tail dark.
static func _needle_mesh() -> ArrayMesh:
	var st := MeshKit.new_st()
	var tip := Vector3(0, 0, -0.84)
	var tail := Vector3(0, 0, 0.42)
	var l := Vector3(-0.11, 0, 0)
	var r := Vector3(0.11, 0, 0)
	var h := Vector3(0, 0.07, 0)
	var bright := Color(1, 1, 1)
	var dim := Color(0.3, 0.3, 0.3)
	# top faces (front half bright, back half dim), sides
	for side in [[l, -1.0], [r, 1.0]]:
		var sp: Vector3 = side[0]
		MeshKit.tri(st, tip + h, sp + h, h, Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, bright)
		MeshKit.tri(st, tail + h, sp + h, h, Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, dim)
		for e in [[tip, sp, bright], [sp, tail, dim]]:
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			var out := Vector3(-(b - a).z, 0, (b - a).x).normalized()
			if out.dot((a + b) * 0.5) < 0.0:
				out = -out
			MeshKit.quad(st, a, b, b + h, a + h, out, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, e[2])
	return MeshKit.commit(st, null)
