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
		var play_s := float(OS.get_environment("PB_T")) if OS.get_environment("PB_T") != "" else 12.0
		for f in int(hz * (party.ANNOUNCE_TIME + party.COUNTDOWN_TIME + play_s)):
			await get_tree().physics_frame
			if f % int(hz * 2.0) == 0 and party._pbots and not party._pbots.bots.is_empty():
				var b0: Dictionary = party._pbots.bots[0]
				if gid == "koth" and party.state == "play":
					var ds: Array = []
					for bb in party._pbots.bots:
						ds.append(snappedf((party.sites.course_xf("koth", party._zone.x, party._zone.y).origin - bb["car"].global_position).length(), 0.1))
					print("  koth t %.0f zone %s dist %s" % [party._t, party._zone.round(), ds])
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
			if OS.get_environment("PB_DBG") != "" and party.state == "idle" and party._t < 3.6 + 12.0 / hz and party._t > 3.4:
				var cw = world.race_ai.bots[0]["car"]
				var comps := []
				for w in cw.wheels:
					comps.append(snappedf(float(w["compression"]), 0.01))
				print("    idle-frame y %.2f vy %.2f comp %s frz %s grounded %s" % [cw.global_position.y, cw.linear_velocity.y, comps, cw.freeze, cw.get("grounded_wheels")])
			if OS.get_environment("PB_DBG") != "" and f % int(hz * 0.5) == 0:
				var c0 = world.race_ai.bots[0]["car"]
				var gy0: float = world.track.samples[world.track.nearest_index(c0.global_position)].y
				if party.state == "back" and party._t > 3.0:
					for bx in world.race_ai.bots:
						var cx = bx["car"]
						var pk = cx.get_meta("park_xf", Transform3D()).origin
						var near := []
						for oid in world.cars:
							var oc = world.cars[oid]
							if oc != cx and is_instance_valid(oc):
								var oo: Vector3 = oc.get_meta("park_xf", oc.global_transform).origin if world._bot_ids.has(oid) else oc.global_position
								near.append(snappedf(oo.distance_to(pk), 0.1))
						print("     bot %d park %s now %s dists %s" % [int(bx["id"]), pk.round(), cx.global_position.round(), near])
				print("   back t %.1f %s vis %s frz %s layer %d up %.1f vy %.1f parked %s" % [party._t, party.state, c0.visible, c0.freeze, c0.collision_layer, c0.global_position.y - gy0, c0.linear_velocity.y, world._bots_parked])
		print("%s back: state %s, party bots %s" % [gid, party.state, party._pbots])
		# back in the race: nobody is thrown up
		var max_vy := 0.0
		var max_up := 0.0
		var start_pos := {}
		for b in world.race_ai.bots:
			start_pos[b["id"]] = b["car"].global_position
		for f in int(hz * 3.0):
			await get_tree().physics_frame
			if OS.get_environment("PB_DBG") != "" and f % int(hz * 0.25) == 0:
				var c1 = world.race_ai.bots[0]["car"]
				var gy1: float = world.track.samples[world.track.nearest_index(c1.global_position)].y
				print("   after t %.2f up %.1f vy %.1f frz %s" % [f / hz, c1.global_position.y - gy1, c1.linear_velocity.y, c1.freeze])
			for b in world.race_ai.bots:
				var c = b["car"]
				max_vy = maxf(max_vy, float(c.linear_velocity.y))
				var gy: float = world.track.samples[world.track.nearest_index(c.global_position)].y
				max_up = maxf(max_up, c.global_position.y - gy)
		var drove := 0
		for b in world.race_ai.bots:
			if (b["car"].global_position as Vector3).distance_to(start_pos[b["id"]]) > 5.0:
				drove += 1
		print("%s after: max vertical speed %.1f m/s, max height over the road %.1f m, %d bots race on" % [gid, max_vy, max_up, drove])
		if drove == 0:
			_fail("bots do not race on after %s" % gid)
		if max_vy > 4.0 or max_up > 3.0:
			_fail("bots thrown up after %s" % gid)
	print("PARTY BOTS TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
