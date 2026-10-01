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
		"day_cycle": 0, "weather_seed": 3, "online": false, "party": true, "party_games": 7, "party_coins": 3})
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
		# at speed and sliding, like in a real run through the coin
		var proj0: Array = tr.project(before, -1)
		var xf0: Transform3D = tr.transform_at(int(proj0[0]) - 4, float(proj0[2]), 0.6)
		car.place(xf0)
		car.linear_velocity = -xf0.basis.z * 30.0 + xf0.basis.x * 2.0
		car.angular_velocity = Vector3(0, 1.5, 0)
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
		# released at the start: the car must stay put (not be flung away)
		var fling := 0.0
		for f in 90:
			await get_tree().physics_frame
			fling = maxf(fling, Vector2(car.linear_velocity.x, car.linear_velocity.z).length())
		if fling > 2.5:
			print("FAIL: %s: car flung at the start (%.1f m/s)" % [gid, fling]); fails += 1
		if gid == "parkour" and car.lift < 0.2:
			print("FAIL: parkour: the car is not lifted"); fails += 1
		if gid == "bowling" and party._pins.size() != 10:
			print("FAIL: bowling: %d pins" % party._pins.size()); fails += 1
		if gid == "arena" or gid == "balloon":
			if party._arena == null or party._arena.bot_ids().size() != 3:
				print("FAIL: arena: no bots"); fails += 1
			Input.action_press("fire")
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
		if gid == "rlgl" and not party._done:
			# crossing the finish line while the light is red: the finish counts, no teleport back
			var red_t := -1.0
			for ph in party._rl_phases:
				if not bool(ph[1]) and float(ph[0]) > party._t + 3.0:
					red_t = float(ph[0]) - 1.0
					break
			party._t = red_t
			party._red_since = red_t - 2.0     # long red already: movement would be caught
			party._pin = false                  # (the 4 s full-throttle run above may have been caught)
			party._penalty = 0.0
			var fx: Transform3D = party.sites.course_xf("rlgl", party.sites.rlgl_finish() - 6.0, 0.0, 0.6)
			car.place(fx)
			car.linear_velocity = -fx.basis.z * 12.0
			for f in 120:
				await get_tree().physics_frame
				if party._done:
					break
			print("  rlgl: light %d at the line, finished %s, value %.0f" % [party._rl_light(party._t), party._done, party._value])
			if not party._done or party._value < 9000.0:
				print("FAIL: rlgl: crossing the line on red did not count"); fails += 1
			if party.sites.rlgl_lamps.size() < 6:
				print("FAIL: rlgl: no traffic lights"); fails += 1
		if gid == "arena" or gid == "balloon":
			Input.action_release("fire")
			var a = party._arena
			var hits := 0
			for id in a.fighters:
				hits += int(a.fighters[id]["hits"])
			var moved := 0.0
			for bid in a.bot_ids():
				var bc = a.fighters[bid]["car"]
				moved = maxf(moved, bc.global_position.distance_to(party.sites.arena_spawn(0).origin))
			print("  %s: %d hits, %d shots in the air, bots alive: %d" % [gid, hits, a.shots.size(), a.bot_ids().size()])
		if gid == "bowling":
			print("  bowling: %d pins down after 4 s" % party.sites.pins_down(party._pins))
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
		var race_clock_ok := absf(world.race_time - rt) < 0.5 or not world.crossed_start
		var fling2 := 0.0
		for f in 90:
			await get_tree().physics_frame
			fling2 = maxf(fling2, Vector2(car.linear_velocity.x, car.linear_velocity.z).length())
		if fling2 > 2.5:
			print("FAIL: %s: car flung when put back (%.1f m/s)" % [gid, fling2]); fails += 1
		if car.global_position.distance_to(before) > 10.0:
			print("FAIL: %s: car not put back (%.1f m off)" % [gid, car.global_position.distance_to(before)]); fails += 1
		if party.sites._course != null:
			print("FAIL: %s: props left on the track" % gid); fails += 1
		if car.lift != 0.0 or not car.input_enabled:
			print("FAIL: %s: lift / input not restored" % gid); fails += 1
		if world.get_children().filter(func(c): return c.name.begins_with("Bot_") and not c.is_queued_for_deletion()).size() > 0:
			print("FAIL: %s: bots left behind" % gid); fails += 1
		if not race_clock_ok:
			print("FAIL: race clock ran during the minigame"); fails += 1
		if car.surface_override.is_valid() or car.respawn_fn.is_valid():
			print("FAIL: minigame hooks left on the car"); fails += 1
	print("PARTY TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
