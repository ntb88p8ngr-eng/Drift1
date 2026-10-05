extends Node
## The world editor's empty plane: a flat world with no road, barriers or scenery that loads in the
## editor and drives in free mode. Run: godot --headless --path . res://tests/blank_map_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var ok := true
	for mode in ["editor", "free"]:
		var t0 := Time.get_ticks_msec()
		var world := World.new()
		world.setup({"track": "blank", "mode": mode, "laps": 1, "time_of_day": "day", "weather": "dry",
			"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
		add_child(world)
		if not world.is_loaded:
			await world.loaded
		var tr = world.track
		var flat := true
		for p in [Vector2(0, 0), Vector2(150, -200), Vector2(-120, 90), Vector2(300, 40)]:
			if absf(float(world.terrain.height_at(p.x, p.y))) > 0.01:
				flat = false
		var road: bool = tr.get_node_or_null("Road") != null or tr.get_node_or_null("Walls") != null
		var bodies := world.scenery.find_children("*", "CollisionObject3D", true, false).size()
		print("BLANK %s: loaded in %d ms, flat %s, road/walls %s, scenery bodies %d, surface %s" % [mode,
			Time.get_ticks_msec() - t0, flat, road, bodies, tr.surface_at(tr.samples[0], 0)])
		ok = ok and flat and not road and bodies == 0
		if mode == "free":
			# drives: full throttle for 3 s across the plane
			var car = world.local_car
			car.ai_fn = func() -> Array: return [1.0, 0.0, 0.3, false, false]
			for k in 360:
				await get_tree().physics_frame
			print("BLANK drive: %.0f km/h, y %.2f" % [car.speed * 3.6, car.global_position.y])
			ok = ok and car.speed > 8.0 and absf(car.global_position.y) < 2.0
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("BLANK MAP TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
