extends Node
## Takioro Mountain driven by the bot driver (the player's car too): every car must get round – up
## the hairpins, through the tunnels, down again – without falling out of the world, getting stuck or
## needing many resets. Prints lap times and where the cars were put back.
## Run: godot --headless --fixed-fps 60 --path . res://tests/takioro_drive_test.tscn

const World = preload("res://scripts/world/world.gd")
const MainScript = preload("res://scripts/main.gd")


func _ready() -> void:
	Game.persist = false
	Game.settings["mode"] = "race"
	Game.settings["bots"] = 2
	Game.settings["bot_level"] = 2
	# more laps than are driven: the player's car (driven by the bot code) finishing a 1-lap race
	# would end it, and the bots' laps would no longer be counted
	Game.settings["laps"] = 3
	Game.settings["party"] = false
	Game.settings["track"] = "takioro"
	var cfg: Dictionary = MainScript.offline_config()
	cfg["weather"] = "dry"
	cfg["time_of_day"] = "day"
	cfg["day_cycle"] = 0
	cfg["laps"] = 3
	var world := World.new()
	world.setup(cfg)
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	world.race_ai.add_bot(999, world.local_car, "Ausgeglichen")
	var hz := float(Engine.physics_ticks_per_second)
	var tr = world.track
	var resets := {}
	var reset_at := {}
	var low_y := {}
	var max_t := float(OS.get_environment("TK_T")) if OS.get_environment("TK_T") != "" else 720.0
	var last_prog := {}
	var t := 0.0
	var wall_t0 := Time.get_ticks_msec()
	while t < max_t:
		await get_tree().physics_frame
		t += 1.0 / hz
		var all_done := true
		for b in world.race_ai.bots:
			var c = b["car"]
			var id := int(b["id"])
			# a reset shows as a jump in position without the speed for it
			var p: Vector3 = c.global_position
			if last_prog.has(id) and (last_prog[id] as Vector3).distance_to(p) > 12.0:
				resets[id] = int(resets.get(id, 0)) + 1
				var pr: Array = tr.project(p, -1)
				if not reset_at.has(id):
					reset_at[id] = []
				(reset_at[id] as Array).append(int(pr[1]))
			last_prog[id] = p
			if p.y < float(tr.kill_y) + 5.0:
				low_y[id] = true
			if id != 999 and int(b["lap"]) < 1:
				all_done = false
		if all_done:
			break
		if int(t * hz) % int(hz * 60.0) == 0:
			var st: Array = []
			for b in world.race_ai.bots:
				st.append("%d: lap %d at %.0f m" % [int(b["id"]), int(b["lap"]), float(b["progress"]) if b.has("progress") else 0.0])
			print("TK DRIVE t %.0f s (%d s real): %s" % [t, (Time.get_ticks_msec() - wall_t0) / 1000, ", ".join(st)])
	var fails := 0
	for b in world.race_ai.bots:
		var id := int(b["id"])
		print("TK DRIVE car %d (%s): laps %d, best %.1f s, resets %d at %s, fell %s" % [id, b["car"].car_id, int(b["lap"]), float(b["best"]), int(resets.get(id, 0)), str(reset_at.get(id, [])), low_y.has(id)])
		# (the player's car joins the bots after the start: its first lap is not counted – it only must
		# not fall or need resets)
		if (id != 999 and int(b["lap"]) < 1) or low_y.has(id) or int(resets.get(id, 0)) > 3:
			fails += 1
	print("TAKIORO DRIVE TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
