extends Node
## Low views along the road edge (litter, grass clumps, leaves, road wear) on the given tracks.
## Run: xvfb-run godot --rendering-driver opengl3 --path . res://tests/roadside_shot.tscn -- --tracks=ridge,utah --out=/tmp
## (--at=0.3: where on the lap, as a fraction)

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	Game.settings["shadow_quality"] = 1
	get_window().size = Vector2i(960, 540)
	var args := {"tracks": "ridge", "out": "/tmp", "at": "0.3", "tod": "day"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	for id in str(args["tracks"]).split(","):
		var w := World.new()
		w.setup({"track": id, "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry", "day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
		add_child(w)
		if not w.is_loaded:
			await w.loaded
		var tr = w.track
		var cam: Camera3D = w.camera
		cam.set_process(false)
		cam.set_physics_process(false)
		w.local_car.visible = false
		for k in 2:
			var i: int = tr.index_at(tr.length * (float(args["at"]) + k * 0.31))
			var hw: float = tr.hws[i]
			var side := 1.0 if k == 0 else -1.0
			var p: Vector3 = tr.edge_point(i, side * (hw - 1.2)) + Vector3(0, 1.1, 0)
			var look: Vector3 = tr.edge_point((i + 9) % tr.sample_count(), side * (hw + 0.6))
			cam.global_position = p
			cam.look_at(look, Vector3.UP)
			for f in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := str(args["out"]).path_join("roadside_%s_%d.png" % [id, k])
			get_viewport().get_texture().get_image().save_png(path)
			print("SHOT %s" % path)
		w.queue_free()
		await get_tree().process_frame
	get_tree().quit()
