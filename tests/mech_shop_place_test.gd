extends Node
## Every map (but the city) gets its workshop: a free level lot beside the track.
## Run: godot --headless --path . res://tests/mech_shop_place_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var ok := true
	for tid in ["ridge", "harbor", "playground", "utah", "gruene_hoelle"]:
		var world := World.new()
		world.setup({"track": tid, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
			"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
		add_child(world)
		if not world.is_loaded:
			await world.loaded
		var at: Vector3 = world.scenery.mech_shop_at
		var d: float = world.terrain.distance_to_road(at.x, at.z) if at != Vector3.INF else -1.0
		print("%s: workshop at %s, %.0f m from the road" % [tid, at, d])
		if at == Vector3.INF:
			ok = false
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("MECH SHOP PLACE TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
