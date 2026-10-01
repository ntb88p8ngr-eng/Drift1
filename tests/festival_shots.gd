extends Node
## Two views of a camp beside the track (from the fence and from above).
## Run: godot --path . res://tests/festival_shots.tscn -- --track=gruene_hoelle --tod=day --out=/tmp/shots

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var args := {"track": "gruene_hoelle", "tod": "day", "out": "/tmp", "camp": "6"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var world := World.new()
	world.setup({"track": args["track"], "mode": "free", "laps": 1, "time_of_day": args["tod"], "weather": "dry",
		"day_cycle": 0, "weather_seed": 7, "online": false})
	add_child(world)
	for f in 30:
		await get_tree().process_frame
	var fest = world.scenery.festival
	var camp: Array = fest._camps[mini(int(args["camp"]), fest._camps.size() - 1)]
	var c: Vector3 = camp[0]
	var tr = world.track
	var i: int = camp[2]
	var road: Vector3 = tr.samples[i]
	var cam: Camera3D = world.camera
	cam.set_process(false)
	var views := [["fence", road.lerp(c, 0.35) + Vector3(0, 2.2, 0) - tr.tangents[i] * 10.0, c + Vector3(0, 1.0, 0)],
		["above", c + (road - c).normalized() * 18.0 + Vector3(0, 16, 0) + tr.tangents[i] * 10.0, c]]
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for f in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(args["out"]).path_join("fest_%s_%s.png" % [args["tod"], v[0]]))
	get_tree().quit()
