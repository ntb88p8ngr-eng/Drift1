extends Node
## Frame times in the main menu: hitches over 25 ms with what happened round them.
## Run: godot --path . res://tests/menu_perf.tscn [-- --secs=20]

var _t := 0.0
var _secs := 20.0
var _frames: Array = []
var _last := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.substr(7))
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_last = Time.get_ticks_usec()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	_t += delta
	if _t < 3.0:
		return
	_frames.append(ms)
	if ms > 12.0:
		print("HITCH %.1f ms at %.2f s  nodes %d  res %d" % [ms, _t, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)]) if true else print(0, [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	if _t > _secs:
		_frames.sort()
		var avg := 0.0
		for f in _frames:
			avg += f
		avg /= _frames.size()
		print("FRAMES %d avg %.1f ms  p50 %.1f  p95 %.1f  max %.1f  process %.2f ms  draws %d" % [_frames.size(), avg,
			_frames[_frames.size() / 2], _frames[int(_frames.size() * 0.95)], _frames[-1],
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		get_tree().quit()
