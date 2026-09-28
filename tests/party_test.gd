extends Node
## Party mode: the venues fit on the map, a coin starts a minigame (race clock stops, car goes to the
## venue), every minigame runs to its result and the car comes back to where it took the coin.
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
		print("FAIL: no party mode (venues did not fit)")
		get_tree().quit(1)
		return
	for id in party.sites.sites:
		var s: Dictionary = party.sites.sites[id]
		var o: Vector3 = s["xf"].origin
		print("  venue %-8s at (%.0f, %.1f, %.0f), %.0f m from the road" % [id, o.x, o.y, o.z, world.terrain.distance_to_road(o.x, o.z)])
	var car = world.local_car
	for f in 30:
		await get_tree().physics_frame
	for g in party.GAMES.size():
		# drive "into" a coin: the next game is forced so every game gets played once
		var coin: Dictionary = party._coins[g % party._coins.size()]
		if not bool(coin["active"]):
			coin["active"] = true
			party._place_coin(g % party._coins.size())
		party._game = g - 1
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
		# force the drawn game for coverage
		party._game = g
		var gid: String = party.GAMES[g]["id"]
		while party.state == "announce":
			await get_tree().physics_frame
		var venue: Vector3 = party.sites.xf(gid).origin
		if car.global_position.distance_to(venue) > 140.0:
			print("FAIL: %s: car not at the venue (%.0f m away)" % [gid, car.global_position.distance_to(venue)]); fails += 1
		while party.state == "travel":
			await get_tree().physics_frame
		# play: full throttle straight ahead (a few seconds), then the clock is cut short
		Input.action_press("accelerate", 1.0)
		var on_stage := true
		var v := 0.0
		for f in 120 * 4:
			await get_tree().physics_frame
			v = maxf(v, party._value)
			if car.global_position.y < party.sites.xf(gid).origin.y - 4.0:
				on_stage = false
		Input.action_release("accelerate")
		party._t = float(party.GAMES[g]["time"])
		var guard := 0
		while party.state != "results" and guard < 600:
			await get_tree().physics_frame
			guard += 1
		if party.state != "results":
			print("FAIL: %s: no result" % gid); fails += 1
		print("  %-8s played: best score %.1f in 4 s, stayed on the stage: %s" % [gid, v, str(on_stage)])
		if gid != "donut" and v <= 0.0 and gid != "koth":
			print("FAIL: %s: driving forward gained nothing" % gid); fails += 1
		party._t = 99.0
		while party.state != "idle":
			await get_tree().physics_frame
		if car.global_position.distance_to(before) > 6.0:
			print("FAIL: %s: car not put back (%.1f m off)" % [gid, car.global_position.distance_to(before)]); fails += 1
		if absf(world.race_time - rt) > 0.5 and world.crossed_start:
			print("FAIL: race clock ran during the minigame"); fails += 1
		if car.surface_override.is_valid() or car.respawn_fn.is_valid():
			print("FAIL: venue hooks left on the car"); fails += 1
	print("PARTY TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
