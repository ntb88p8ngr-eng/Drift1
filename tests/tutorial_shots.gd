extends Node
## Screenshots of the tutorial's cutscene shots and the camp (for checking light and textures by eye).
## Run: godot --path . res://tests/tutorial_shots.tscn -- --out=/tmp/shots [--only=0,3]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.persist = false
	var out := "/tmp/shots"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--only="):
			only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	var world := World.new()
	world.setup({"track": "gruene_hoelle", "mode": "tutorial", "laps": 1, "time_of_day": "night", "hour": 23.98,
		"weather": "rain", "day_cycle": 0, "weather_seed": 77, "online": false, "collisions": true})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var tut = world.tutorial
	tut.set_process(false)
	tut._fade.color.a = 0.0
	# [shot index, time in the shot, name]
	var shots := [[0, 7.9, "clock"], [1, 2.15, "window_flash"], [1, 5.0, "window"], [2, 4.2, "phone"], [3, 2.0, "pov_living"],
		[3, 3.4, "pov_hall"], [3, 5.8, "pov_garage"], [4, 5.0, "garage_car"], [5, 3.0, "outside"]]
	for sh in shots:
		if only != "" and not only.split(",").has(str(sh[0])):
			continue
		var i: int = sh[0]
		var t: float = sh[1]
		tut._shot = i
		tut._st = t
		(tut._shots[i]["enter"] as Callable).call()
		var d: float = tut._shots[i]["d"]
		# run the shot's updates up to the time (events fire in order)
		var tt := 0.0
		while tt < t:
			tt = minf(tt + 0.1, t)
			(tut._shots[i]["update"] as Callable).call(clampf(tt / d, 0.0, 1.0), tt)
		for f in 3:
			tut._update_lightning(1.0 / 60.0)
		tut._fade.color.a = 0.0
		for f in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("tut_%d_%s.png" % [i, sh[2]]))
		print("SHOT ", sh[2])
	# the camp: ending shots
	if only == "" or only.split(",").has("camp"):
		tut._skip_intro()
		tut._close_hint()
		world.local_car.place(Transform3D(Basis.IDENTITY, world.tutorial_site.path_pts[world.tutorial_site.path_pts.size() - 10] + Vector3(0, 0.8, 0)))
		for f in 30:
			await get_tree().physics_frame
		tut._start_ending()
		tut.set_process(false)
		for e in [[0, 3.0, "end_arrive"], [1, 3.0, "end_fire"], [2, 3.0, "end_eyes"]]:
			tut._shot = e[0]
			(tut._shots[e[0]]["enter"] as Callable).call()
			var dd: float = tut._shots[e[0]]["d"]
			var t2 := 0.0
			while t2 < float(e[1]):
				t2 = minf(t2 + 0.1, float(e[1]))
				(tut._shots[e[0]]["update"] as Callable).call(clampf(t2 / dd, 0.0, 1.0), t2)
			for f in 3:
				tut._update_lightning(1.0 / 60.0)
			tut._fade.color.a = 0.0
			for f in 8:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("tut_%s.png" % e[2]))
			print("SHOT ", e[2])
	print("SHOTS DONE")
	get_tree().quit()
