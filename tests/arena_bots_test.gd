extends Node
## Arena shoot-out offline with the race's bots (Utah, 4 bots: five cars, fought on the long
## stretch): the bots must come to the player (not fight among themselves at the far end), and the
## physics step must stay cheap. Also the balloon battle.
## Run: godot --headless --fixed-fps 60 --path . res://tests/arena_bots_test.tscn

const World = preload("res://scripts/world/world.gd")
const MainScript = preload("res://scripts/main.gd")

var fails := 0


func _fail(msg: String) -> void:
	print("FAIL: " + msg)
	fails += 1


func _ready() -> void:
	Game.persist = false
	Game.settings["mode"] = "race"
	Game.settings["bots"] = int(OS.get_environment("AB_BOTS")) if OS.get_environment("AB_BOTS") != "" else 4
	Game.settings["bot_level"] = 2
	Game.settings["party"] = true
	Game.settings["party_coins"] = 3
	Game.settings["track"] = OS.get_environment("AB_TRACK") if OS.get_environment("AB_TRACK") != "" else "utah"
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
	for f in 60:
		await get_tree().physics_frame
	var party = world.party
	var hz := float(Engine.physics_ticks_per_second)
	var base := 0.0
	for f in int(hz * 2.0):
		await get_tree().physics_frame
		base += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("ARENA baseline (racing): physics frame %.2f ms" % (base / (hz * 2.0)))
	for gid in ["arena", "balloon"]:
		var g := -1
		for k in party.GAMES.size():
			if party.GAMES[k]["id"] == gid:
				g = k
		var ids: Array = world.cars.keys()
		ids.sort()
		party.state = "idle"
		party._on_start({"t": "start", "i": -1, "g": g, "s": 1234, "by": 1, "ids": ids})
		var me = world.local_car
		var near_sum := 0.0
		var near_n := 0
		var worst_ms := 0.0
		var sum_ms := 0.0
		var n_ms := 0
		var t_last := Time.get_ticks_usec()
		for f in int(hz * (party.ANNOUNCE_TIME + party.COUNTDOWN_TIME + 20.0)):
			await get_tree().physics_frame
			var now := Time.get_ticks_usec()
			var ms := (now - t_last) / 1000.0
			t_last = now
			if party.state == "travel" and party._t > 3.3 and party._t < 3.3 + 1.5 / hz:
				var aw := 0
				var tot := 0
				for c in party.sites.find_children("*", "RigidBody3D", true, false):
					tot += 1
					if not (c as RigidBody3D).sleeping and not (c as RigidBody3D).freeze:
						aw += 1
				print("  end of the countdown (nobody moved yet): %d of %d loose bodies awake" % [aw, tot])
			if party.state == "play" and party._arena:
				ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				sum_ms += ms
				n_ms += 1
				worst_ms = maxf(worst_ms, ms)
				# distance of the nearest bot to the player
				var dmin := 1e9
				for id in party._arena.bot_ids():
					var c = party._arena.fighters[id]["car"]
					if is_instance_valid(c):
						dmin = minf(dmin, (c as Node3D).global_position.distance_to(me.global_position))
				near_sum += dmin
				near_n += 1
				if near_n == int(hz * 6.0):
					# what one physics step of the arena costs, piece by piece
					var arena0 = party._arena
					var t0 := Time.get_ticks_usec()
					for r in 20:
						for id in arena0.bot_ids():
							arena0._bot_ai(id)
					var t1 := Time.get_ticks_usec()
					for r in 20:
						arena0._step_shots(0.0)
					var t2 := Time.get_ticks_usec()
					for r in 20:
						for id in arena0.bot_ids():
							arena0._bot_think(id, arena0.fighters[id], 0.0)
					var t3 := Time.get_ticks_usec()
					for r in 20:
						party._play(0.0, party.GAMES[party._game])
					var t4 := Time.get_ticks_usec()
					var bodies := 0
					var awake := 0
					for c in party.sites.find_children("*", "RigidBody3D", true, false):
						bodies += 1
						if not (c as RigidBody3D).sleeping and not (c as RigidBody3D).freeze:
							awake += 1
					print("  %d of the loose bodies awake, %d active rigid bodies in the physics server" % [awake, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))])
					print("  per step: bot ai %.2f ms, shots %.2f ms (%d), think %.2f ms, party play %.2f ms; %d loose bodies on the course" % [
						(t1 - t0) / 20000.0, (t2 - t1) / 20000.0, arena0.shots.size(), (t3 - t2) / 20000.0, (t4 - t3) / 20000.0, bodies])
		var arena = party._arena
		var bots: int = arena.bot_ids().size() if arena else 0
		var avg_near := near_sum / maxf(near_n, 1)
		var player_hits := 0
		if arena:
			for id in arena.fighters:
				if int(id) != arena.me:
					player_hits += 0
		print("ARENA %s: site len %.0f m, %d bots, nearest bot to the player %.0f m on average, physics frame %.2f ms avg, %.2f ms worst" % [
			gid, party.sites.arena_len(), bots, avg_near, sum_ms / maxf(n_ms, 1), worst_ms])
		if gid == "arena" and avg_near > 60.0:
			_fail("the bots stay away from the player (%.0f m)" % avg_near)
		party._t = 1e6
		for f in int(hz * (party.RESULTS_TIME + 4.0)):
			await get_tree().physics_frame
	print("ARENA BOTS TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
