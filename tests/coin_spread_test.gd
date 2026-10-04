extends Node
## Party coins on Neo Tokyo: on the race route by default; with "party_coins_city" most of them out
## on the city's streets.
## Run: godot --headless --path . res://tests/coin_spread_test.tscn -- [--city]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var city := "--city" in OS.get_cmdline_user_args()
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "race", "laps": 1, "time_of_day": "day", "weather": "dry", "day_cycle": 0,
		"weather_seed": 5, "online": false, "traffic": 0, "party": true, "party_games": 3, "party_coins": 10,
		"party_coins_city": city})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var tr = world.track
	var on_route := 0
	var total := 0
	for c in world.party._coins:
		var p: Vector3 = (c["node"] as Node3D).global_position
		var pr: Array = tr.project(p, -1)
		total += 1
		if absf(float(pr[2])) <= float(tr.half_w) + 0.5:
			on_route += 1
	print("COINS (%s): %d of %d on the race route" % ["city" if city else "route", on_route, total])
	var ok: bool = (on_route == total) if not city else (on_route < total)
	print("COIN SPREAD TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
