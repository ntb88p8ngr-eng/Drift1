extends Node
## Views of any map: behind the start, from above, and custom cameras.
## Run: godot --path . res://tests/map_shots.tscn -- --track=tokyo --tod=night --out=/tmp/shots
##      [--views=start,aerial,cam1] [--cam1=x,y,z,lx,ly,lz]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	Game.settings["shadow_quality"] = 1
	get_window().size = Vector2i(960, 540)
	var args := {"track": "tokyo", "tod": "night", "out": "/tmp", "views": "start,aerial"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var world := World.new()
	world.setup({"track": args["track"], "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry",
		"day_cycle": 0, "weather_seed": 7, "online": false, "traffic": int(args.get("traffic", "0"))})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	for f in 20:
		await get_tree().process_frame
	var tr = world.track
	var cam: Camera3D = world.camera
	cam.set_process(false)
	var si: int = tr.start_index
	var s: Vector3 = tr.samples[si]
	var t: Vector3 = tr.tangents[si]
	var c := Vector3(tr.bounds.get_center().x, 0, tr.bounds.get_center().y)
	var views := {
		"start": [s - t * 14.0 + Vector3(0, 3.5, 0), s + t * 30.0 + Vector3(0, 1.0, 0)],
		"aerial": [c + Vector3(tr.bounds.size.x * 0.55, maxf(tr.bounds.size.x, tr.bounds.size.y) * 0.6, tr.bounds.size.y * 0.75), c],
	}
	for k in args:
		if str(k).begins_with("cam"):
			var v: PackedFloat64Array = str(args[k]).split_floats(",")
			views[k] = [Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5])]
	for name in str(args["views"]).split(","):
		if not views.has(name):
			print("no view ", name)
			continue
		var v: Array = views[name]
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
		for f in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(args["out"]).path_join("%s_%s_%s.png" % [args["track"], args["tod"], name]))
		print("shot %s at %d ms" % [name, Time.get_ticks_msec()])
	get_tree().quit()
