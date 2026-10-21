extends Node
## Views of Takioro Mountain: the zig-zag from above, a hairpin, a tunnel portal, the valley.
## Run: xvfb-run godot --rendering-driver opengl3 --path . res://tests/takioro_shots.tscn -- --out=/tmp [--views=a,b] [--tod=day]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	Game.settings["shadow_quality"] = 1
	get_window().size = Vector2i(960, 540)
	var args := {"out": "/tmp", "tod": "day", "views": "zigzag,hairpin,tunnel,valley,pass"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var w := World.new()
	w.setup({"track": "takioro", "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry", "day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(w)
	if not w.is_loaded:
		await w.loaded
	var tr = w.track
	var cam: Camera3D = w.camera
	cam.set_process(false)
	cam.set_physics_process(false)
	var meta: Dictionary = tr.meta
	var sec := {}
	for s in meta["sections"]:
		sec[str(s[0])] = float(s[1])
	var at := func(d: float) -> int: return int(d / tr.SPACING) % tr.sample_count()
	var views := {}
	var k4: int = at.call(sec["Kehre 4"])
	var c4: Vector3 = tr.samples[k4]
	views["zigzag"] = [c4 + Vector3(-60, 160, 330), c4 + Vector3(0, -20, -60)]
	var k3: int = at.call(sec["Kehre 3"] - 30.0)
	views["hairpin"] = [tr.samples[k3] + Vector3(0, 2.0, 0) - tr.tangents[k3] * 6.0, tr.samples[at.call(sec["Kehre 3"] + 10.0)] + Vector3(0, 1.0, 0)]
	var t0: float = float(meta["tunnels"][0][0])
	var kt: int = at.call(t0 - 70.0)
	views["tunnel"] = [tr.samples[kt] + Vector3(0, 2.5, 0), tr.samples[at.call(t0)] + Vector3(0, 4.0, 0)]
	var kv: int = at.call(30.0)
	views["valley"] = [tr.samples[kv] + Vector3(0, 2.2, 0), tr.samples[at.call(160.0)] + Vector3(0, 2.0, 0)]
	var kp: int = at.call(sec["Takioro-Pass"])
	views["pass"] = [tr.samples[kp] + Vector3(0, 3.0, 0) + tr.rights[kp] * 4.0, tr.samples[kp] + Vector3(0, -60, 0) + tr.rights[kp] * 200.0 + tr.tangents[kp] * 120.0]
	var t1: Array = meta["tunnels"][0]
	var ki: int = at.call((float(t1[0]) + float(t1[1])) * 0.5)
	views["inside"] = [tr.samples[ki] + Vector3(0, 2.0, 0) - tr.tangents[ki] * 10.0, tr.samples[at.call((float(t1[0]) + float(t1[1])) * 0.5 + 40.0)] + Vector3(0, 2.0, 0)]
	var g0: float = float(meta["gallery"][0])
	var kg: int = at.call(g0 + 40.0)
	views["gallery"] = [tr.samples[kg] + Vector3(0, 2.2, 0), tr.samples[at.call(g0 + 90.0)] + Vector3(0, 2.0, 0)]
	var kgo: int = at.call(g0 - 60.0)
	views["gallery_out"] = [tr.samples[kgo] + Vector3(0, 9.0, 0) - tr.rights[kgo] * 25.0, tr.samples[at.call(g0 + 40.0)] + Vector3(0, 3.0, 0)]
	var kw: int = at.call(float(meta["waterfall"]) - 45.0)
	views["waterfall"] = [tr.samples[kw] + Vector3(0, 2.5, 0), tr.samples[at.call(float(meta["waterfall"]))] + Vector3(0, 6.0, 0)]
	var ks: int = tr.start_index
	views["torii"] = [tr.samples[(ks - 50 + tr.sample_count()) % tr.sample_count()] + Vector3(0, 2.2, 0), tr.samples[(ks - 20 + tr.sample_count()) % tr.sample_count()] + Vector3(0, 5.0, 0)]
	views["portal_out"] = [tr.samples[at.call(float(t1[0]) - 25.0)] + Vector3(0, 30.0, 0) - tr.tangents[at.call(float(t1[0]) - 25.0)] * 40.0, tr.samples[at.call(float(t1[0]) + 20.0)]]
	var mtn = w.scenery.mountain
	for c in mtn.get_children():
		if c.name == "WaterfallRock":
			var rp: Vector3 = (c as Node3D).global_transform * ((c as MeshInstance3D).get_aabb().get_center())
			var ri: int = tr.nearest_index(rp)
			views["fall_top"] = [rp + (tr.samples[ri] - rp) * 2.5 + Vector3(0, 45.0, 0), rp]
			views["fall_close"] = [tr.samples[ri] - (rp - tr.samples[ri]).normalized() * 6.0 + Vector3(0, 3.0, 0) - tr.tangents[ri] * 14.0, rp + Vector3(0, 2.0, 0)]
		if c.name == "Gallery":
			var gp: Vector3 = (c as Node3D).global_transform * ((c as MeshInstance3D).get_aabb().get_center())
			var gi: int = tr.nearest_index(gp)
			views["gallery_side"] = [gp + (tr.samples[gi] - gp).normalized() * 0.0 - tr.rights[gi] * 0.0 + Vector3(0, 0, 0) + (tr.samples[gi] - gp) * 3.0 + Vector3(0, 6.0, 0), gp]
	w.local_car.visible = false
	for hn in str(args.get("hide", "")).split(",", false):
		for c in mtn.get_children():
			if c.name == hn:
				(c as Node3D).visible = false
	for name in str(args["views"]).split(","):
		if not views.has(name):
			continue
		cam.global_position = views[name][0]
		cam.look_at(views[name][1], Vector3.UP)
		for f in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := str(args["out"]).path_join("tk_%s_%s.png" % [args["tod"], name])
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT %s" % path)
	get_tree().quit()
