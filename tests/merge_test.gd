extends Node
## Neo Tokyo traffic: city cars merge onto the highway at the street mouths and highway cars turn
## off into the city (free mode). Run: godot --headless --path . res://tests/merge_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 3, "traffic_speed": 2})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var ct = world.city_traffic
	var hw = world.traffic
	print("PORTS ", ct.ports.size(), " city cars ", ct.cars.size(), " highway cars ", hw.cars.size())
	Engine.time_scale = 8.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	print("AFTER city ", ct.cars.size(), " highway ", hw.cars.size(), " city stats ", ct.stats.get("merged_out", 0), "/", ct.stats.get("merged_in", 0), " highway merged_in ", hw.stats.get("merged_in", 0))
	var ok: bool = int(ct.stats.get("merged_out", 0)) > 0 and int(ct.stats.get("merged_in", 0)) > 0
	print("MERGE TEST: ", "PASS" if ok else "FAIL")
	get_tree().quit()
