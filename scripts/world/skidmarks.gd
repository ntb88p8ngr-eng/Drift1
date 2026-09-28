extends MultiMeshInstance3D
## Ring buffer of dark quads laid down behind sliding tyres.

const MAX_MARKS := 7000

var _mm: MultiMesh
var _next := 0
var _count := 0
var _last := {}
## height of the marks above the wheel contact: on flat tracks the car rolls on the terrain, 3 cm
## under the road surface; on data tracks it rolls on the road itself
var y_lift := 0.047


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
