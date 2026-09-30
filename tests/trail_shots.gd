extends Node
## Screenshot of the drift trail: the car drifts in circles on the playground pad with the trail on.
## Run: godot --path . res://tests/trail_shots.tscn -- --out=/tmp/shots [--tod=night]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var args := {"out": "/tmp/shots", "tod": "dusk", "paint": "blue"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	DirAccess.make_dir_recursive_absolute(args["out"])
	Game.settings["paint"] = args["paint"]
	var world := World.new()
	world.setup({"track": "playground", "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var car = world.local_car
	var pr: Rect2 = world.terrain.pad_rect()
	car.place(Transform3D(Basis.IDENTITY, Vector3(pr.get_center().x, 0.6, pr.end.y - 30.0)))
	world.state = "running"
	car.controls_locked = false
	car.input_enabled = false
	var inp := [0.0, 0.0, -1.0, false]
	car.ai_fn = func() -> Array: return inp
	var t := 0.0
	while t < 7.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		# a donut / circle drift: throttle and full lock, a handbrake flick at the start
		inp[0] = 1.0 if t > 0.5 else 0.0
		inp[3] = t > 1.0 and t < 1.3
		world.scorer.chain = 60000.0 if t > 1.5 else 0.0
		car.trail_active = t > 1.5
	await RenderingServer.frame_post_draw
	var path: String = str(args["out"]).path_join("trail_%s.png" % args["tod"])
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path, " speed ", car.speed_kmh())
	get_tree().quit()
