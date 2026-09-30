extends MultiMeshInstance3D
## Ring buffer of dark quads laid down behind sliding tyres – plus a second one for the glowing drift
## trail in the car's colour (a big drift chain, see Car.DRIFT_TRAIL_POINTS).

const MAX_MARKS := 7000
const MAX_GLOW := 4000

var _mm: MultiMesh
var _next := 0
var _count := 0
var _last := {}
## height of the marks above the wheel contact: on flat tracks the car rolls on the terrain, 3 cm
## under the road surface; on data tracks it rolls on the road itself
var y_lift := 0.047
var _glow: MultiMesh
var _g_next := 0
var _g_count := 0
var _g_last := {}


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	_mm.mesh = plane
	_mm.instance_count = MAX_MARKS
	_mm.visible_instance_count = 0
	multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.02)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.render_priority = -1
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-5000, -50, -5000), Vector3(10000, 100, 10000))
	# the coloured trail: unshaded, so it glows at night and stays vivid by day
	_glow = MultiMesh.new()
	_glow.transform_format = MultiMesh.TRANSFORM_3D
	_glow.use_colors = true
	_glow.mesh = plane
	_glow.instance_count = MAX_GLOW
	_glow.visible_instance_count = 0
	var gi := MultiMeshInstance3D.new()
	gi.multimesh = _glow
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.vertex_color_use_as_albedo = true
	gm.render_priority = 0
	gi.material_override = gm
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi.custom_aabb = custom_aabb
	add_child(gi)


func add_mark(key: int, pos: Vector3, width: float, alpha: float) -> void:
	if not _last.has(key):
		_last[key] = pos
		return
	var prev: Vector3 = _last[key]
	var d := pos.distance_to(prev)
	if d < 0.35:
		return
	if d > 3.0:
		_last[key] = pos
		return
	var z := (pos - prev) / d
	var x := Vector3.UP.cross(z).normalized()
	if x.length_squared() < 0.5:
		_last[key] = pos
		return
	var mid := (prev + pos) * 0.5
	mid.y += y_lift
	var b := Basis(x * width, Vector3.UP, z * (d + 0.06))
	_mm.set_instance_transform(_next, Transform3D(b, mid))
	_mm.set_instance_color(_next, Color(0.02, 0.02, 0.02, alpha))
	_next = (_next + 1) % MAX_MARKS
	_count = mini(_count + 1, MAX_MARKS)
	_mm.visible_instance_count = _count
	_last[key] = pos


func break_mark(key: int) -> void:
	_last.erase(key)


## A piece of the glowing drift trail (just above the black marks).
func add_glow_mark(key: int, pos: Vector3, width: float, color: Color) -> void:
	if not _g_last.has(key):
		_g_last[key] = pos
		return
	var prev: Vector3 = _g_last[key]
	var d := pos.distance_to(prev)
	if d < 0.3:
		return
	if d > 3.0:
		_g_last[key] = pos
		return
	var z := (pos - prev) / d
	var x := Vector3.UP.cross(z).normalized()
	if x.length_squared() < 0.5:
		_g_last[key] = pos
		return
	var mid := (prev + pos) * 0.5
	mid.y += y_lift + 0.006
	_glow.set_instance_transform(_g_next, Transform3D(Basis(x * width, Vector3.UP, z * (d + 0.05)), mid))
	_glow.set_instance_color(_g_next, color)
	_g_next = (_g_next + 1) % MAX_GLOW
	_g_count = mini(_g_count + 1, MAX_GLOW)
	_glow.visible_instance_count = _g_count
	_g_last[key] = pos


func break_glow_mark(key: int) -> void:
	_g_last.erase(key)
