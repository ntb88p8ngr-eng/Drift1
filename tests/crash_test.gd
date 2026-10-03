extends Node
## Bots and traffic together: a race with 7 bots and traffic on the lap. Counts the crashes – a bot
## losing more than 7 m/s within a quarter second (a hit, not braking) – and the traffic cars knocked.
## Run: godot --headless --path . res://tests/crash_test.tscn -- [--track=ridge] [--secs=90]

const World = preload("res://scripts/world/world.gd")
const RaceAI = preload("res://scripts/world/race_ai.gd")


func _ready() -> void:
	Game.persist = false
	var track_id := "ridge"
	var secs := 90.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr(8)
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
	var world := World.new()
	world.setup({"track": track_id, "mode": "race", "laps": 5, "time_of_day": "day", "weather": "dry", "day_cycle": 0,
		"weather_seed": 5, "online": false, "collisions": true, "bots": RaceAI.make_roster(7, 9), "bot_level": 2,
		"traffic": 2, "traffic_speed": 2})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var ai = world.race_ai
	var hist := {}
	var crashes := 0
	var sim := 0.0
	var dist := 0.0
	var tick := 0
	while sim < secs:
		await get_tree().physics_frame
		sim += 1.0 / 120.0
		tick += 1
		if tick % 30 != 0:
			continue
		for b in ai.bots:
			var c = b["car"]
			var v: float = c.linear_velocity.length()
			var last: float = hist.get(b["id"], -1.0)
			if last >= 0.0 and last - v > 7.0:
				crashes += 1
			hist[b["id"]] = v
			dist += v * 0.25
	var knocked := 0
	if world.traffic:
		knocked = int(world.traffic_cars.stats.get("hits", 0)) if world.traffic_cars and "stats" in world.traffic_cars else 0
	print("CRASH: %d bot crashes in %.0f s (%.1f km driven by the bots), traffic stats %s, render stats %s" % [crashes, secs, dist / 1000.0,
		str(world.traffic.stats) if world.traffic else "-", str(world.traffic_cars.stats) if world.traffic_cars and "stats" in world.traffic_cars else "-"])
	get_tree().quit(0)
