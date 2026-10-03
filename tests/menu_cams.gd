extends Node
## Main-menu camera probe: shots of the garage from given positions (rain hidden for speed).
## Run: godot --path . res://tests/menu_cams.tscn -- --out=/tmp/menu

const Main = preload("res://scripts/main.gd")

const CAMS := [
	["a_lo", Vector3(sin(-0.12) * 9.5 - 2.6, 2.5, cos(-0.12) * 9.5), Vector3(-5.0, 1.0, -1.2), 58.0],
	["a_hi", Vector3(sin(0.12) * 9.5 - 2.6, 2.5, cos(0.12) * 9.5), Vector3(-5.0, 1.0, -1.2), 58.0],
]


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/menu"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var main := Main.new()
	add_child(main)
	for f in 20:
		await get_tree().process_frame
	var storm = main.find_child("Storm", true, false)
	if storm:
		storm.process_mode = Node.PROCESS_MODE_DISABLED
		for c in storm.get_children():
			if c is GPUParticles3D or c is MultiMeshInstance3D or c is MeshInstance3D:
				c.visible = false
	var sr = main.showroom
	sr.set_process(false)
	for c in CAMS:
		if c[0] == "a_hi":
			Game.settings["menu_lights"] = {"ceiling": 0.4, "platform": 1.8, "platform_color": "#00e5ff"}
			sr.apply_menu_lights()
		sr.cam.fov = c[3]
		sr.cam.global_position = c[1]
		sr.cam.look_at(c[2], Vector3.UP)
		for f in 3:
			await get_tree().process_frame
		await _shot(out.path_join("cam_%s.png" % c[0]))
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
