extends Node3D
## Run: godot --path . res://tests/radio_model_shot.tscn -- --out=/tmp/r.png [--dir=z|y|-z|-y]

func _ready() -> void:
	var out := "/tmp/radio.png"
	var dir := Vector3(0, 0, 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a == "--dir=-z": dir = Vector3(0, 0, -1)
		if a == "--dir=y": dir = Vector3(0, 1, 0)
		if a == "--dir=-y": dir = Vector3(0, -1, 0)
	var m := (load("res://assets/props/radio/car_radio.glb") as PackedScene).instantiate() as Node3D
	add_child(m)
	var box := AABB()
	var first := true
	for c in m.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var bb: AABB = mi.global_transform * mi.get_aabb()
		print(mi.name, " ", bb)
		box = bb if first else box.merge(bb)
		first = false
	print("BOX ", box)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = box.size.x
	add_child(cam)
	cam.position = box.get_center() + dir * 3.0
	cam.look_at(box.get_center(), Vector3.UP if absf(dir.y) < 0.5 else Vector3(0, 0, -1))
	var l := DirectionalLight3D.new()
	add_child(l)
	l.look_at_from_position(cam.position, box.get_center())
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.3, 0.3, 0.35)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(1, 1, 1)
	add_child(we)
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
