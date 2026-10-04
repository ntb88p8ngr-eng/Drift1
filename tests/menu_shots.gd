extends Node
## Main-menu background shots (garage, storm outside): calm, during a lightning strike.
## Run: godot --path . res://tests/menu_shots.tscn -- --out=/tmp/menu

const Main = preload("res://scripts/main.gd")


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/menu"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	if OS.get_cmdline_user_args().has("--underglow"):
		Game.settings["underglow"] = {Game.settings["car"]: {"on": true, "mode": 0, "speed": 1.0, "sides": {
			"front": {"on": true, "color": "#00e5ff", "flash": false}, "rear": {"on": true, "color": "#ff2060", "flash": true},
			"left": {"on": true, "color": "#8a3dff", "flash": false}, "right": {"on": true, "color": "#8a3dff", "flash": false}}}}
	var main := Main.new()
	add_child(main)
	# (the workshop builds in slices behind a loading screen first)
	while main.menu == null:
		await get_tree().process_frame
	for f in 60:
		await get_tree().process_frame
	var storm = main.find_child("Storm", true, false)
	await _shot(out.path_join("menu_calm.png"))
	# the shutter and the street behind it
	var sr = main.showroom
	if sr and sr.cam:
		sr.set_process(false)
		sr.cam.global_position = Vector3(0, 1.8, 4.0)
		sr.cam.look_at(Vector3(0, 1.6, -14.0), Vector3.UP)
		for f in 3:
			await get_tree().process_frame
		await _shot(out.path_join("menu_shutter.png"))
		sr.set_process(true)
		# the garage with the rims view
		main.menu.show_screen("garage")
		sr.set_view("wheels")
		for f in 150:
			await get_tree().process_frame
		await _shot(out.path_join("menu_wheels.png"))
	if storm:
		storm._next = 0.0
		for f in 2:
			await get_tree().process_frame
		await _shot(out.path_join("menu_flash.png"))
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
