extends Control
## North-up minimap of the track with all cars.

var world   # world.gd
var _pts := PackedVector2Array()
var _scale := 1.0
var _offset := Vector2.ZERO
var _center := Vector2.ZERO


func setup(p_world) -> void:
	world = p_world
	_pts = world.track.minimap_points()
	_center = (world.track.bounds as Rect2).get_center()


func _to_map(p: Vector2) -> Vector2:
	return size * 0.5 + (p - _center) * _scale


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or _pts.is_empty():
		return
	var b: Rect2 = world.track.bounds
	var margin := 14.0
	_scale = minf((size.x - margin * 2.0) / maxf(b.size.x, 1.0), (size.y - margin * 2.0) / maxf(b.size.y, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.015, 0.04, 0.6))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.22, 0.8, 0.7), false, 1.5)
	var mapped := PackedVector2Array()
	for p in _pts:
		mapped.append(_to_map(p))
	mapped.append(mapped[0])
	draw_polyline(mapped, Color(0, 0, 0, 0.6), 7.0, true)
	draw_polyline(mapped, Color(0.85, 0.85, 0.9, 0.9), 3.5, true)
	var s: Vector3 = world.track.samples[world.track.start_index]
	var r: Vector3 = world.track.rights[world.track.start_index]
	draw_line(_to_map(Vector2(s.x - r.x * 10.0, s.z - r.z * 10.0)), _to_map(Vector2(s.x + r.x * 10.0, s.z + r.z * 10.0)), Color(1, 1, 1), 3.0)
	for c in world.all_cars():
		if not is_instance_valid(c):
			continue
		var pos: Vector3 = c.global_position
		var mp := _to_map(Vector2(pos.x, pos.z))
		var local: bool = c == world.local_car
		var col := Color(0.75, 0.4, 1.0) if local else Color(1.0, 0.85, 0.3)
		var fwd: Vector3 = -c.global_transform.basis.z
		var f2 := Vector2(fwd.x, fwd.z).normalized()
		var side := Vector2(-f2.y, f2.x)
		var tri := PackedVector2Array([mp + f2 * 8.0, mp - f2 * 5.0 + side * 5.0, mp - f2 * 5.0 - side * 5.0])
		draw_colored_polygon(tri, col)
		if not local:
			draw_string(ThemeDB.fallback_font, mp + Vector2(7, -5), str(c.player_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
