extends Node
## Party mode with race bots: they play the minigames (on the course, visible, scoring) instead of
## waiting hidden, and race on afterwards.
## Run: godot --headless --path . res://tests/party_bots_test.tscn

const World = preload("res://scripts/world/world.gd")
const MainScript = preload("res://scripts/main.gd")

var fails := 0


func _fail(msg: String) -> void:
	print("FAIL: " + msg)
	fails += 1


func _ready() -> void:
	Game.persist = false
	Game.settings["mode"] = "race"
	Game.settings["bots"] = 3
	Game.settings["bot_level"] = 2
	Game.settings["party"] = true
	Game.settings["party_coins"] = 3
	Game.settings["track"] = "playground"
	var cfg: Dictionary = MainScript.offline_config()
	cfg["weather"] = "dry"
	cfg["time_of_day"] = "day"
	cfg["day_cycle"] = 0
	var world := World.new()
	world.setup(cfg)
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	world.state = "running"
	world.local_car.controls_locked = false
	for f in 120:
		await get_tree().physics_frame
	var party = world.party
	var hz := float(Engine.physics_ticks_per_second)
	var only: String = OS.get_environment("PB_ONLY")
	for gid in ["rlgl", "koth", "parkour", "donut"]:
		if only != "" and gid != only:
			continue
		var g := -1
		for k in party.GAMES.size():
			if party.GAMES[k]["id"] == gid:
				g = k
		if g < 0 or not party.sites.sites.has(gid):
			print("(no %s site here)" % gid)
			continue
		var ids: Array = world.cars.keys()
		ids.sort()
		party.state = "idle"
		party._on_start({"t": "start", "i": -1, "g": g, "s": 1234, "by": 1, "ids": ids})
		# announce + countdown, then 12 s of play
		for f in int(hz * (party.ANNOUNCE_TIME + party.COUNTDOWN_TIME + 12.0)):
			await get_tree().physics_frame
			if f % int(hz * 1.0) == 0 and party._pbots and not party._pbots.bots.is_empty():
				var b0: Dictionary = party._pbots.bots[0]
				var spot: Transform3D = party.sites.start_xf("donut", int(b0["slot"]), party._pbots._count) if gid == "donut" else Transform3D()
				print("  t %.1f %s along %.1f speed %.1f spin %.2f off %.1f gear %d" % [party._t, party.state, float(b0["along"]), float(b0["car"].speed), float(b0["car"].angular_velocity.y), b0["car"].global_position.distance_to(spot.origin), int(b0["car"].gear)])
		var shown := 0
		var moved := 0
		for b in world.race_ai.bots:
			var c = b["car"]
			if c.visible and c.collision_layer != 0:
				shown += 1
			if c.speed > 1.0 or party._pbots and float(party._pbots.results().get(int(b["id"]), 0.0)) > 0.0:
				moved += 1
		var res: Dictionary = party._pbots.results() if party._pbots else {}
		print("%s: state %s, bots shown %d / %d, playing %d, scores %s" % [gid, party.state, shown, world.race_ai.bots.size(), moved, res])
		if shown != world.race_ai.bots.size() or moved == 0:
			_fail("bots do not play %s" % gid)
		# end it: the results include the bots
		party._finish_local()
		party._results[1] = party._value
		party._host_check_final(true)
		for f in 5:
			await get_tree().physics_frame
		var rows: int = party._table.get_child_count()
		print("%s results: %d rows in the table" % [gid, rows])
		if rows < world.race_ai.bots.size() + 2:
			_fail("bots missing in the %s results" % gid)
		for f in int(hz * (party.RESULTS_TIME + party.COUNTDOWN_TIME + 1.0)):
			await get_tree().physics_frame
		print("%s back: state %s, party bots %s" % [gid, party.state, party._pbots])
	print("PARTY BOTS TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
