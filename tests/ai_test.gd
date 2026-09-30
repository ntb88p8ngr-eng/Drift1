extends Node
## AI opponents: three bots race one lap offline. Every bot must finish the lap in a sensible time,
## without being put back on the road more than a couple of times.
## Run: godot --headless --path . res://tests/ai_test.tscn -- --track=ridge [--level=2]

const World = preload("res://scripts/world/world.gd")
const RaceAI = preload("res://scripts/world/race_ai.gd")


func _ready() -> void:
	Game.persist = false
	var track_id := "ridge"
	var level := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr(8)
		if a.begins_with("--level="):
			level = int(a.substr(8))
	var world := World.new()
	world.setup({"track": track_id, "mode": "race", "laps": 1, "time_of_day": "day", "weather": "dry", "day_cycle": 0,
		"weather_seed": 5, "online": false, "collisions": true, "bots": RaceAI.make_roster(3, 5), "bot_level": level})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var ai = world.race_ai
	if ai == null or ai.bots.size() != 3:
		print("FAIL: no bots")
		get_tree().quit(1)
		return
	# count the resets
	var resets := {}
	for b in ai.bots:
		resets[b["id"]] = 0
	var sim := 0.0
	var max_v := {}
	while sim < 240.0:
		await get_tree().physics_frame
		sim += 1.0 / 120.0
		var all_done := true
		for b in ai.bots:
			if float(b["stuck_t"]) == 0.0 and float(b["wrong_t"]) == 0.0 and float(b["off_t"]) == 0.0 and b.get("_was_bad", false):
				resets[b["id"]] = int(resets[b["id"]]) + 1
			b["_was_bad"] = float(b["stuck_t"]) > 3.4 or float(b["wrong_t"]) > 2.4 or float(b["off_t"]) > 4.9
			max_v[b["id"]] = maxf(float(max_v.get(b["id"], 0.0)), b["car"].speed_kmh())
			if not bool(b["finished"]):
				all_done = false
		if all_done:
			break
	var fails := 0
	var length: float = world.track.length
	for b in ai.bots:
		var c = b["car"]
		print("  %-10s %-8s finished %s  time %.1f s  top %.0f km/h  resets %d  progress %.0f / %.0f m" % [c.player_name, c.car_id,
			str(b["finished"]), float(b["time"]), float(max_v[b["id"]]), int(resets[b["id"]]), ai.total_progress(b), length])
		if not bool(b["finished"]):
			fails += 1
	print("AI TEST (%s, level %d): %s" % [track_id, level, "PASS" if fails == 0 else "FAIL"])
	get_tree().quit(1 if fails else 0)
