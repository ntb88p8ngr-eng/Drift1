extends Node
const Livery = preload("res://scripts/car/livery.gd")
## The paint booth: the car drives in, a few stickers go on, a picture from the booth camera.
## Run: godot --path . res://tests/booth_shot.tscn -- --out=/tmp/booth.png [--mid=/tmp/mid.png]

func _ready() -> void:
	var out := "/tmp/booth.png"
	var mid := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--mid="):
			mid = a.substr(6)
	Game.persist = false
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	while main.menu == null:
		await get_tree().process_frame
	var sr = main.showroom
	main.menu.show_screen("booth")
	var t0 := Time.get_ticks_msec()
	var shot_mid := false
	while sr.booth != "inside" and Time.get_ticks_msec() - t0 < 900000:
		await get_tree().process_frame
		if mid != "" and not shot_mid and sr.booth == "in" and sr._booth_cam_on:
			for f in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(mid)
			shot_mid = true
	print("BOOTH: ", sr.booth, " car at ", sr.car.global_position)
	for f in 30:
		await get_tree().process_frame
	var ed = main.menu._booth_ui
	if ed:
		while ed._shape_grid.get_child_count() == 0:
			await get_tree().process_frame
		ed.layers = [
			{"shape": "stripes2", "color": "#ffffff", "side": "top", "p": 0.0, "h": 0.0, "size": 4.6, "rot": 90.0, "alpha": 1.0, "mirror": false},
			{"shape": "graffiti_4", "color": "#ffffff", "side": "right", "p": 0.0, "h": 0.55, "size": 1.6, "rot": 0.0, "alpha": 1.0, "mirror": true},
			{"shape": "ch_7", "color": "#ff2a2a", "side": "right", "p": -0.55, "h": 0.5, "size": 0.45, "rot": 0.0, "alpha": 1.0, "mirror": true},
			{"shape": "unicorn", "color": "#000000", "side": "right", "p": 0.6, "h": 0.55, "size": 0.5, "rot": 0.0, "alpha": 1.0, "mirror": false},
		]
		ed.sel = 0
		ed._refresh_list()
		var ta := Time.get_ticks_usec()
		ed._apply()
		print("LIVERY first apply ms: ", (Time.get_ticks_usec() - ta) / 1000.0)
		ta = Time.get_ticks_usec()
		ed._apply()
		print("LIVERY apply ms: ", (Time.get_ticks_usec() - ta) / 1000.0, "  tris: ", (Livery.surface(sr.car.body)["v"] as PackedVector3Array).size() / 3)
	for f in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("CAM ", sr.cam.global_position, " car ", sr.car.global_position)
	if ed:
		ed.visible = false
		main.menu.visible = false
		for f in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "_clean.png"))
		# close to the spray guns on the wall
		sr.set_process(false)
		sr.cam.h_offset = 0.0
		sr.cam.global_position = Vector3(9.9, 1.45, -1.75)
		sr.cam.look_at(Vector3(9.6, 1.2, -0.6), Vector3.UP)
		for f in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "_guns.png"))
	get_tree().quit()
