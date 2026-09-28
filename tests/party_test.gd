extends Node
## Party mode: every minigame gets its own stretch of the track; a coin starts a minigame (race clock
## stops, the car goes to the stretch, the props go up), every minigame runs to its result, the props
## come down again and the car is put back where it took the coin.
## Run: godot --headless --path . res://tests/party_test.tscn -- --track=ridge

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var track_id := "ridge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr(8)
	var t0 := Time.get_ticks_msec()
	var world := World.new()
	world.setup({"track": track_id, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "party": true, "party_games": 4, "party_coins": 3})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	print("PARTY: %s loaded in %d ms" % [track_id, Time.get_ticks_msec() - t0])
	var fails := 0
	var party = world.party
	if party == null:
		print("FAIL: no party mode")
		get_tree().quit(1)
		return
	var tr = world.track
	for id in party.sites.sites:
		var s: Dictionary = party.sites.sites[id]
		print("  stretch %-8s from %.0f m (%.0f m long)" % [id, float(s["p0"]), float(s["len"])])
	if party.sites.sites.size() != party.GAMES.size():
		print("FAIL: only %d of %d minigames got a stretch" % [party.sites.sites.size(), party.GAMES.size()]); fails += 1
	var car = world.local_car
	for f in 30:
		await get_tree().physics_frame
	for g in party.GAMES.size():
		var gid: String = party.GAMES[g]["id"]
		if not party.sites.sites.has(gid):
			continue
		# drive "into" a coin; the drawn game is overridden so every game gets played once
		var ci: int = g % party._coins.size()
		var coin: Dictionary = party._coins[ci]
		if not bool(coin["active"]):
			coin["active"] = true
			party._place_coin(ci)
		var before: Vector3 = (coin["node"] as Node3D).global_position
		car.place(Transform3D(car.global_transform.basis, before + Vector3(0, -0.8, 0)))
		var rt: float = world.race_time
		var waited := 0
		while party.state == "idle" and waited < 60:
			await get_tree().physics_frame
			waited += 1
		if party.state == "idle":
			print("FAIL: coin %d did not start a minigame" % g); fails += 1
			continue
		party._game = g
		while party.state == "announce":
			await get_tree().physics_frame
		var start: Vector3 = party.sites.start_xf(gid, 0, 1).origin
		if car.global_position.distance_to(start) > 3.0:
			print("FAIL: %s: car not at the start (%.0f m away)" % [gid, car.global_position.distance_to(start)]); fails += 1
		if party.sites._course == null:
			print("FAIL: %s: no props put up" % gid); fails += 1
		while party.state == "travel":
			await get_tree().physics_frame
		# play: full throttle straight ahead (a few seconds), then the clock is cut short
		Input.action_press("accelerate", 1.0)
		var v := 0.0
		var on_road := true
		for f in 120 * 4:
			await get_tree().physics_frame
			v = maxf(v, party._value)
			var proj: Array = tr.project(car.global_position, -1)
			if absf(float(proj[2])) > float(tr.half_w) + 3.0:
				on_road = false
		Input.action_release("accelerate")
		party._t = float(party.GAMES[g]["time"])
		var guard := 0
		while party.state != "results" and guard < 600:
			await get_tree().physics_frame
			guard += 1
		if party.state != "results":
			print("FAIL: %s: no result" % gid); fails += 1
		print("  %-8s played: best score %.1f in 4 s, stayed on the road: %s" % [gid, v, str(on_road)])
		if (gid == "rlgl" or gid == "parkour") and v <= 0.0:
			print("FAIL: %s: driving forward gained nothing" % gid); fails += 1
		party._t = 99.0
		while party.state != "idle":
			await get_tree().physics_frame
		if car.global_position.distance_to(before) > 6.0:
			print("FAIL: %s: car not put back (%.1f m off)" % [gid, car.global_position.distance_to(before)]); fails += 1
		if party.sites._course != null:
			print("FAIL: %s: props left on the track" % gid); fails += 1
		if absf(world.race_time - rt) > 0.5 and world.crossed_start:
			print("FAIL: race clock ran during the minigame"); fails += 1
		if car.surface_override.is_valid() or car.respawn_fn.is_valid():
			print("FAIL: minigame hooks left on the car"); fails += 1
	print("PARTY TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
