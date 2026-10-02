extends Node
## A few views of the city: the scramble crossing, on the expressway, from above, the gas station.
## Run: godot --path . res://tests/city_shots.tscn -- --tod=night --out=/tmp/shots [--views=crossing,highway]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var args := {"tod": "night", "out": "/tmp", "views": "crossing,highway,aerial,station"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry",
		"day_cycle": 0, "weather_seed": 7, "online": false})
	add_child(world)
	for f in 30:
		await get_tree().process_frame
	var tr = world.track
	var city = world.scenery.city
	var cam: Camera3D = world.camera
	cam.set_process(false)
	var ci: int = city._crossing_i
	var c: Vector3 = tr.samples[ci]
	var t: Vector3 = tr.tangents[ci]
	var hi: int = tr.index_at(city._highest_progress(-1) + 60.0)
	var views := {
		"crossing": [c - t * 45.0 + Vector3(0, 2.2, 0), c + t * 20.0 + Vector3(0, 6.0, 0)],
		"highway": [tr.samples[hi] + Vector3(0, 2.0, 0) - tr.tangents[hi] * 6.0, tr.samples[(hi + 40) % tr.sample_count()] + Vector3(0, 2.0, 0)],
		"aerial": [Vector3(250, 230, 380), Vector3(380, 0, -200)],
		"station": [tr.samples[tr.nearest_index(Vector3(130, 0, 235))] + Vector3(0, 3.0, 0) - tr.rights[tr.nearest_index(Vector3(130, 0, 235))] * 6.0, Vector3(130, 2.0, 262)],
	}
	for name in str(args["views"]).split(","):
		var v: Array = views[name]
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
		for f in 14:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(args["out"]).path_join("city_%s_%s.png" % [args["tod"], name]))
	get_tree().quit()
