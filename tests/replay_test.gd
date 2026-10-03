extends Node
## Replays: drive for a few seconds, save, play back – the car is where it was at the same time.
## Run: godot --headless --path . res://tests/replay_test.tscn

const World = preload("res://scripts/world/world.gd")
const Replay = preload("res://scripts/replay/replay.gd")


func _ready() -> void:
	Game.persist = false
	var cfg := {"track": "playground", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0}
	var world := World.new()
	world.setup(cfg)
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	Input.action_press("accelerate")
	Input.action_press("steer_left")
	var marks := {}
	for f in 120 * 4:
		await get_tree().physics_frame
		if f == 120 * 3:
			marks[world.recorder.duration()] = world.local_car.global_position
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	var path: String = world.recorder.save()
	print("REPLAY: saved %s, %d frames, %.1f s" % [path, world.recorder.frames, world.recorder.duration()])
	var ok := path != "" and FileAccess.file_exists(path)
	world.queue_free()
	await get_tree().process_frame
	var h: Dictionary = Replay.read_file(path, false)[0]
	var w2 := World.new()
	w2.setup({"track": "playground", "mode": "replay", "replay": path, "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0, "hour": float(h.get("hour", 12.0))})
	add_child(w2)
	if not w2.is_loaded:
		await w2.loaded
	var rp = w2.replay_player
	for tm in marks:
		rp.seek(float(tm))
		rp._set_playing(false)
		for f in 3:
			await get_tree().process_frame
		var d: float = w2.local_car.global_position.distance_to(marks[tm])
		print("REPLAY: at %.2f s recorded %s, replayed %s (%.2f m off)" % [tm, marks[tm], w2.local_car.global_position, d])
		ok = ok and d < 0.6
	# playing on moves the car
	rp._set_playing(true)
	rp.seek(1.0)
	var p0: Vector3 = w2.local_car.global_position
	for f in 60:
		await get_tree().physics_frame
	print("REPLAY: playing, moved %.1f m" % w2.local_car.global_position.distance_to(p0))
	ok = ok and w2.local_car.global_position.distance_to(p0) > 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Engine.time_scale = 1.0
	get_tree().paused = false
	print("REPLAY TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
