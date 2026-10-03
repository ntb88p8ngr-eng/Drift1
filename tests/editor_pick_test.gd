extends Node
## World editor picking in Neo Tokyo: a street tree under the mouse is picked (not the building
## behind it), a click on a city building says it can't be edited instead of selecting a collider.
## Run (real renderer – the scenery index needs the instance buffers):
##   godot --path . --rendering-driver vulkan res://tests/editor_pick_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "editor", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	for f in 10:
		await get_tree().process_frame
	var ed = world.editor
	var cam: Camera3D = ed.cam
	ed.set_process(false)          # (the editor's orbit camera would put the camera back)
	var ok := true
	# a street tree: look at its trunk from 14 m
	var tree_id := -1
	for id in ed._spots:
		if str(ed._spots[id].get("label", "")).contains("tree") or str(ed._spots[id].get("label", "")).contains("sakura"):
			tree_id = id
			break
	if tree_id >= 0:
		var foot: Vector3 = ed._spots[tree_id]["pos"]
		cam.global_position = foot + Vector3(3, 16, 3)
		cam.look_at(foot + Vector3(0, 1.8, 0), Vector3.UP)
		await get_tree().process_frame
		var it: Dictionary = ed._pick_at(cam.unproject_position(foot + Vector3(0, 1.8, 0)))
		print("PICK: tree %s -> %s" % [str(ed._spots[tree_id]["label"]), str(it)])
		ok = ok and str(it.get("kind", "")) == "spot" and int(it.get("id", -1)) == tree_id
	else:
		print("PICK: no tree found")
		ok = false
	# a building: aim at the middle of a tall one
	var b: Dictionary = world.scenery.city.builds[world.scenery.city.builds.size() / 2]
	var bc: Vector3 = (b["c"] as Vector3) + Vector3(0, float(b["h"]) * 0.5, 0)
	cam.global_position = bc - (b["az"] as Vector3) * (float(b["d"]) * 0.5 + 25.0) + Vector3(0, 5, 0)
	cam.look_at(bc, Vector3.UP)
	await get_tree().physics_frame
	await get_tree().process_frame
	var it2: Dictionary = ed._pick_at(cam.unproject_position(bc))
	print("PICK: building -> %s" % str(it2))
	ok = ok and str(it2.get("kind", "")) == "none"
	print("EDITOR PICK TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
