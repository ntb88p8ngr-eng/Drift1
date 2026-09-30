extends Node
## Screenshots of the party venues with their props up (for checking them by eye).
## Run: godot --path . res://tests/party_shots.tscn -- --track=harbor --out=/tmp/shots [--games=parkour,arena,bowling]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var args := {"track": "harbor", "out": "/tmp/shots", "games": "parkour,bowling,arena", "tod": "day"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	DirAccess.make_dir_recursive_absolute(args["out"])
	var world := World.new()
	world.setup({"track": args["track"], "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "party": true, "party_games": 6, "party_coins": 1})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var sites = world.party.sites
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 65.0
	world.local_car.visible = false
	for gid in str(args["games"]).split(","):
		if not sites.sites.has(gid):
			continue
		sites.build_course(gid)
		var views: Array = []
		var l: float = sites.sites[gid]["len"]
		match gid:
			"parkour":
				var k: float = l / 210.0
				views = [["mud", 14.0 * k, 4.0, 2.2, 34.0 * k], ["logs", 64.0 * k, 3.5, 2.6, 88.0 * k], ["logs_low", 78.0 * k, -2.5, 1.2, 92.0 * k],
					["ramps", 112.0 * k, 3.0, 2.8, 140.0 * k], ["chicane", 158.0 * k, 0.0, 3.0, 185.0 * k]]
			"bowling":
				sites.make_pins()
				views = [["lane", 2.0, 0.0, 2.5, sites.bowl_pins_along()], ["pins", sites.bowl_pins_along() - 9.0, 2.0, 2.2, sites.bowl_pins_along() + 2.0]]
			"arena":
				views = [["arena", 8.0, 0.0, 5.0, l * 0.5]]
		for f in 10:
			await get_tree().process_frame
		for v in views:
			var eye: Transform3D = sites.course_xf(gid, float(v[1]), float(v[2]), float(v[3]))
			var at: Transform3D = sites.course_xf(gid, float(v[4]), 0.0, 0.5)
			cam.global_position = eye.origin
			cam.look_at(at.origin, Vector3.UP)
			for f in 8:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path: String = str(args["out"]).path_join("party_%s_%s.png" % [gid, v[0]])
			get_viewport().get_texture().get_image().save_png(path)
			print("SHOT ", path)
		sites.clear_course()
	print("SHOTS DONE")
	get_tree().quit()
