extends Node
## A few views of the city: the scramble crossing, on the expressway, from above, the gas station.
## Run: godot --path . res://tests/city_shots.tscn -- --tod=night --out=/tmp/shots [--views=crossing,highway]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	# small and cheap: software rendering of the whole city is slow
	Game.settings["shadow_quality"] = 1
	get_window().size = Vector2i(960, 540)
	var args := {"tod": "night", "out": "/tmp", "views": "crossing,highway,aerial,station"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry",
		"day_cycle": 0, "weather_seed": 7, "online": false, "traffic": int(args.get("traffic", "2"))})
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
	var sk: Vector3 = city._sakura_spots[city._sakura_spots.size() / 2]
	var views := {
		"sakura": [sk + Vector3(9, 3.0, 7), sk + Vector3(0, 3.5, 0)],
		"crossing": [c - t * 45.0 + Vector3(0, 2.2, 0), c + t * 20.0 + Vector3(0, 6.0, 0)],
		"highway": [tr.samples[hi] + Vector3(0, 2.0, 0) - tr.tangents[hi] * 6.0, tr.samples[(hi + 40) % tr.sample_count()] + Vector3(0, 2.0, 0)],
		"aerial": [Vector3(250, 230, 380), Vector3(380, 0, -200)],
		"station": [tr.samples[tr.nearest_index(Vector3(130, 0, 235))] + Vector3(0, 3.0, 0) - tr.rights[tr.nearest_index(Vector3(130, 0, 235))] * 6.0, Vector3(130, 2.0, 262)],
	}
	# a side street meeting the race route (at the foot of the expressway ramp)
	var best_j: Dictionary = {}
	for j in city.net.junctions:
		if best_j.is_empty() or absf(float(j["progress"]) - 720.0) < absf(float(best_j["progress"]) - 720.0):
			best_j = j
	if not best_j.is_empty():
		var jp: Vector2 = best_j["pos"]
		var ji: int = tr.index_at(float(best_j["progress"]) - 28.0)
		views["junction"] = [tr.samples[ji] + Vector3(0, 7.0, 0), Vector3(jp.x, 0.0, jp.y)]
	# the fog at the city's border, from inside
	var fr: Rect2 = city.fog.rect
	views["fog"] = [Vector3(fr.end.x - 75.0, 3.0, fr.get_center().y - 40.0), Vector3(fr.end.x + 4.0, 2.0, fr.get_center().y + 30.0)]
	views["fogin"] = [Vector3(fr.end.x - 25.0, 2.0, fr.get_center().y - 10.0), Vector3(fr.end.x + 10.0, 1.5, fr.get_center().y + 10.0)]
	# a side street, the special places, a park
	var st: Dictionary = city.net.streets[city.net.streets.size() / 3]
	var sp: PackedVector2Array = st["pts"]
	var m0: Vector2 = sp[sp.size() / 2]
	var m1: Vector2 = sp[mini(sp.size() / 2 + 3, sp.size() - 1)]
	var sdir := Vector3(m1.x - m0.x, 0, m1.y - m0.y).normalized()
	views["street"] = [Vector3(m0.x, 1.8, m0.y) - sdir * 12.0, Vector3(m0.x, 3.0, m0.y) + sdir * 30.0]
	# street corners (where streets meet), looked at from above
	for q in 4:
		var cs: Dictionary = city.net.streets[(city.net.streets.size() * (q + 1)) / 6]
		var e: Vector2 = (cs["pts"] as PackedVector2Array)[0]
		views["corner%d" % q] = [Vector3(e.x + 9.0, 14.0, e.y + 9.0), Vector3(e.x, 0.0, e.y)]
	for l in city.lots:
		var lot: Dictionary = l[1]
		var lc: Vector3 = lot["c"]
		var az: Vector3 = lot["az"]
		var ax: Vector3 = lot["ax"]
		if not views.has(l[0]):
			views[l[0]] = [lc - az * (float(lot["d"]) * 0.5 + 6.0) + ax * 6.0 + Vector3(0, 3.0, 0), lc + Vector3(0, 3.5, 0)]
			views[l[0] + "_top"] = [lc - az * (float(lot["d"]) * 0.5 + 25.0) + Vector3(0, 40.0, 0), lc - az * (float(lot["d"]) * 0.25)]
	if city.parks.size() > 0:
		var pc: Vector3 = city.parks[0][0]
		var pr: float = city.parks[0][1]
		views["park"] = [pc + Vector3(pr * 0.7, 6.0, pr * 0.7), pc]
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
		get_viewport().get_texture().get_image().save_png(str(args["out"]).path_join("city_%s_%s.png" % [args["tod"], name]))
		print("shot %s at %d ms" % [name, Time.get_ticks_msec()])
	get_tree().quit()
