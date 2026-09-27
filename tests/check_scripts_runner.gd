extends Node
## CI helper: compiles every script in res://scripts (with autoloads available) and reports failures.
## Run with: godot --headless --path . res://tests/check_scripts.tscn


func _ready() -> void:
	var failed := 0
	var paths := _collect("res://scripts")
	for path in paths:
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			print("SCRIPT CHECK FAILED: ", path)
			failed += 1
		else:
			print("ok  ", path)
	print("SCRIPT CHECK DONE: %d scripts, %d failed" % [paths.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_collect(dir_path.path_join(d)))
	return out
