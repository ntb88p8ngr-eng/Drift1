extends Node
## Lists scenery instances (vegetation, rocks, props) whose origin lies on the road or curbs.
## Run (needs a real renderer for MultiMesh read-back): xvfb-run godot --path . res://tests/veg_check.tscn -- --track=ridge

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var track_id := "ridge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr(8)
	var world := World.new()
	world.setup({"track": track_id, "mode": "free", "laps": 1, "time_of_day": "noon", "weather": "dry",
		"day_cycle": 0, "weather_seed": 7, "online": false})
	add_child(world)
	for f in 5:
		await get_tree().process_frame
	var tr = world.track
	var bad := {}
	var total := 0
	for mmi in world.scenery.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		if mm == null:
			continue
		for k in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
			var p: Vector3 = (mmi as Node3D).global_transform * mm.get_instance_transform(k).origin
			total += 1
			var lat: float = tr.distance_to_center(p) - float(tr.half_w)
			if lat < 4.0 and p.y < 3.0:
				var key := "%s/%s lat<%d" % [mmi.get_parent().name, mmi.name, int(ceil(lat))]
				bad[key] = int(bad.get(key, 0)) + 1
				if int(bad[key]) <= 1:
					print("ON ROAD %s at %s lat %.2f" % [key, p, lat])
	print("VEG CHECK %s: %d instances, on road: %s" % [track_id, total, bad])
	get_tree().quit()
