extends Node
## Renders screenshots of a track from several viewpoints (for checking the scenery by eye).
## Run: godot --path . res://tests/scene_shots.tscn -- --track=ridge --tod=dusk --weather=dry --out=/tmp/shots [--car=r34]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var args := {"track": "ridge", "tod": "dusk", "weather": "dry", "out": "/tmp/shots", "car": "r34", "cycle": "0", "views": "all"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	DirAccess.make_dir_recursive_absolute(args["out"])
	Game.settings["car"] = args["car"]
	if args.has("shadow"):
		Game.settings["shadow_quality"] = int(args["shadow"])
	if args.has("grass"):
		Game.settings["grass_quality"] = int(args["grass"])
	if args.has("tilt"):
		Game.settings["camera_tilt"] = float(args["tilt"])
	if args.has("vd"):
		Game.settings["view_distance"] = int(args["vd"])
	var world := World.new()
	world.setup({"track": args["track"], "mode": args.get("mode", "free"), "laps": 1, "time_of_day": args["tod"], "weather": args["weather"],
		"day_cycle": int(args["cycle"]), "weather_seed": 7, "online": false})
	add_child(world)
	for f in 30:
		await get_tree().process_frame
	if args.has("elapsed"):
		world.atmosphere.elapsed = float(args["elapsed"])
		for f in 4:
			await get_tree().process_frame
	if world.graffiti:
		# paint the first stretch after the start line (as if the local player had drifted it)
		var tr0 = world.track
		for k in 60:
			world.graffiti.spray(tr0.dists[tr0.start_index] + 20.0 + k * 2.0)
		world.graffiti.apply_claim(2, PackedInt32Array([world.graffiti.cell_at(tr0.dists[tr0.start_index] + 170.0), world.graffiti.cell_at(tr0.dists[tr0.start_index] + 174.0)]))
		for f in 4:
			await get_tree().process_frame
	var tag := "%s_%s_%s" % [args["track"], args["tod"], args["weather"]]
	if args.has("elapsed"):
		tag += "_t%s" % args["elapsed"]
	var prefix: String = str(args["out"]).path_join(tag)
	var wanted: String = args["views"]
	if args.has("burnout"):
		# line-lock burnout (W + S at a standstill) to fill the air with tyre smoke
		world.local_car.controls_locked = false
		Input.action_press("brake")
		for f in 20:
			await get_tree().physics_frame
		Input.action_press("accelerate")
		for f in int(float(args["burnout"]) * 120.0):
			await get_tree().physics_frame
		Input.action_release("accelerate")
		Input.action_release("brake")
		for f in int(float(args.get("linger", "0")) * 120.0):
			await get_tree().physics_frame
	if wanted == "all" or wanted.contains("chase"):
		await _shot(prefix + "_chase.png")
	var cam: Camera3D = world.camera
	cam.set_process(false)
	var tr = world.track
	var n: int = tr.sample_count()
	var views: Array = []
	# along the road, low
	var i0: int = (tr.start_index + 40) % n
	views.append(["road", tr.samples[i0] + Vector3(0, 1.6, 0) - tr.tangents[i0] * 2.0, tr.samples[(i0 + 30) % n] + Vector3(0, 1.2, 0)])
	# elevated overview
	var i1: int = (tr.start_index + 120) % n
	views.append(["aerial", tr.samples[i1] + tr.rights[i1] * 60.0 + Vector3(0, 45, 0), tr.samples[i1]])
	# crowd corner (tightest corner)
	var best := 0
	for i in n:
		if absf(tr.curvature[i]) > absf(tr.curvature[best]):
			best = i
	var side := 1.0 if tr.curvature[best] > 0.0 else -1.0
	views.append(["crowd", tr.samples[best] - tr.rights[best] * side * 4.0 + Vector3(0, 2.0, 0) - tr.tangents[best] * 18.0,
		tr.samples[best] + tr.rights[best] * side * 16.0 + Vector3(0, 1.0, 0)])
	# road edge close-ups: curb at the tightest corner (outside) and a straight
	var ob: Vector3 = tr.samples[best] - tr.rights[best] * side * (float(tr.half_w) + 1.0)
	views.append(["edge_corner", ob + Vector3(0, 2.2, 0) - tr.tangents[best] * 7.0 + tr.rights[best] * side * 3.0, ob + tr.tangents[best] * 5.0])
	var ib: Vector3 = tr.samples[best] + tr.rights[best] * side * (float(tr.half_w) + 1.0)
	views.append(["edge_inside", ib + Vector3(0, 2.2, 0) - tr.tangents[best] * 7.0 - tr.rights[best] * side * 3.0, ib + tr.tangents[best] * 5.0])
	views.append(["edge_top", tr.samples[best] + Vector3(0, 38, 0) - tr.tangents[best] * 12.0, tr.samples[best]])
	var i5: int = (tr.start_index + 60) % n
	var eb: Vector3 = tr.samples[i5] + tr.rights[i5] * (float(tr.half_w) + 1.0)
	views.append(["edge_straight", eb + Vector3(0, 2.0, 0) - tr.tangents[i5] * 6.0 - tr.rights[i5] * 3.0, eb + tr.tangents[i5] * 6.0])
	# high overview of the whole area
	var oc: Vector2 = tr.bounds.get_center()
	views.append(["overview", Vector3(oc.x, 230.0, oc.y + 230.0), Vector3(oc.x, 0.0, oc.y + 10.0)])
	# playground: pit lane and the crossing of the figure eight
	var pgn = world.scenery.get_node_or_null("Playground")
	if pgn:
		var pit: Rect2 = pgn._pit
		views.append(["pit", Vector3(pit.get_center().x - 20.0, 9.0, pit.end.y + 30.0), Vector3(pit.get_center().x, 1.5, pit.get_center().y)])
		views.append(["crossing", Vector3(oc.x + 25.0, 18.0, oc.y + 25.0), Vector3(oc.x, 0.0, oc.y)])
	# distant skyline (harbor: north of the track)
	var cc: Vector2 = tr.bounds.get_center()
	views.append(["skyline", Vector3(cc.x, 12.0, cc.y), Vector3(cc.x, 60.0, cc.y - 800.0)])
	# forest edge, looking into the trees
	var i2: int = (tr.start_index + 260) % n
	views.append(["forest", tr.samples[i2] + Vector3(0, 1.4, 0), tr.samples[i2] + tr.rights[i2] * 40.0 + Vector3(0, 3.0, 0)])
	# towards the sun
	var sd: Vector3 = world.atmosphere.sun_direction()
	var i3: int = (tr.start_index + 80) % n
	var sflat := Vector3(sd.x, 0, sd.z).normalized()
	views.append(["sun", tr.samples[i3] + Vector3(0, 1.5, 0), tr.samples[i3] + Vector3(0, 1.5, 0) + sflat * 50.0 + Vector3(0, maxf(sd.y, 0.05) * 50.0, 0)])
	# grass close-up beside the road
	var i4: int = (tr.start_index + 180) % n
	var gp: Vector3 = tr.samples[i4] + tr.rights[i4] * (float(tr.wall_base) + 7.0)
	gp.y = world.terrain.height_at(gp.x, gp.z)
	views.append(["grass", gp + Vector3(0, 1.3, 0) - tr.tangents[i4] * 4.0, gp + tr.tangents[i4] * 10.0 + Vector3(0, 0.2, 0)])
	# a house (village) and the container yard / a billboard
	var houses: Array = world.scenery.find_children("House_*", "Node3D", false, false)
	if not houses.is_empty():
		var h: Node3D = houses[0]
		var hf: Vector3 = -h.global_transform.basis.z
		views.append(["house", h.global_position + hf * 22.0 + h.global_transform.basis.x * 6.0 + Vector3(0, 3.0, 0), h.global_position + Vector3(0, 3.0, 0)])
	var cont: Array = world.scenery.find_children("Containers", "MultiMeshInstance3D", false, false)
	if not cont.is_empty():
		var mid := Vector3.ZERO
		for cm in cont:
			mid += (cm as Node3D).global_position
		mid /= cont.size()
		views.append(["yard", mid + Vector3(90, 110, 140), mid])
	for v in views:
		if wanted != "all" and not wanted.contains(str(v[0])):
			continue
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		cam.fov = 70.0
		for f in 6:
			await get_tree().process_frame
		await _shot(prefix + "_%s.png" % v[0])
	print("SHOTS DONE")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(path)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	print("SHOT %s  primitives=%d draw_calls=%d objects=%d" % [path.get_file(), prims, draws, objs])
