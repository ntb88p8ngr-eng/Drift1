extends Node
## Screenshots of the ambient life: a flock brought close in front of the camera, the ground view
## (leaves, fireflies, sand) and, in Tokyo, a steaming manhole.
## Run: xvfb-run godot --rendering-driver opengl3 --path . res://tests/ambient_shot.tscn -- --track=ridge --tod=day --out=/tmp

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	Game.settings["shadow_quality"] = 1
	get_window().size = Vector2i(960, 540)
	var args := {"track": "ridge", "out": "/tmp", "tod": "day"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var w := World.new()
	w.setup({"track": args["track"], "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry", "day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(w)
	if not w.is_loaded:
		await w.loaded
	print("AMBIENT: %s" % w.ambient.stats_text())
	var tr = w.track
	var cam: Camera3D = w.camera
	cam.set_process(false)
	cam.set_physics_process(false)
	var i: int = tr.index_at(tr.length * 0.4)
	var p: Vector3 = tr.edge_point(i, 0.0) + Vector3(0, 1.6, 0)
	var t: Vector3 = tr.tangents[i]
	var shots := {}
	# the ground view along the road
	shots["ground"] = [p, p + t * 20.0 + Vector3(0, 0.5, 0)]
	# a flock right in front, looking up at it
	for f in w.ambient._flocks:
		if (f.at_night and args["tod"] == "night") or (not f.at_night and args["tod"] != "night"):
			f.centre = p + t * 30.0 - Vector3(0, w.terrain.height_at(p.x, p.z), 0) * 0.0
			f.centre.y = 0.0
			f.radius = 12.0
			f.height = Vector2(10, 12) if not f.at_night else Vector2(3, 5)
			f.placed = true
			f.vis = 1.0
			shots["flock"] = [p, p + t * 30.0 + Vector3(0, 9.0 if not f.at_night else 3.0, 0)]
			break
	for name in shots:
		cam.global_position = shots[name][0]
		cam.look_at(shots[name][1], Vector3.UP)
		for f in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if name == "flock":
			var c3 := get_viewport().get_camera_3d()
			for f in w.ambient._flocks:
				if not f.mmi.visible:
					continue
				var on := 0
				var first := Vector3.ZERO
				for k in f.n:
					var bp: Vector3 = f.mmi.multimesh.get_instance_transform(k).origin
					first = bp
					if not c3.is_position_behind(bp) and get_viewport().get_visible_rect().has_point(c3.unproject_position(bp)):
						on += 1
				print("FLOCK: %d of %d birds on screen (size %.2f, vis %.2f, a bird at %s, camera %s)" % [on, f.n, f.size, f.vis, first, c3.global_position])
		var path := str(args["out"]).path_join("ambient_%s_%s_%s.png" % [args["track"], args["tod"], name])
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT %s" % path)
	# Tokyo: the nearest manhole
	for c in w.ambient.get_children():
		if c is MeshInstance3D:
			var mp: Vector3 = (c as Node3D).global_position
			cam.global_position = mp + Vector3(6, 2.2, 6)
			cam.look_at(mp + Vector3(0, 1.2, 0), Vector3.UP)
			for f in 40:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path2 := str(args["out"]).path_join("ambient_%s_%s_steam.png" % [args["track"], args["tod"]])
			get_viewport().get_texture().get_image().save_png(path2)
			print("SHOT %s" % path2)
			break
	get_tree().quit()
