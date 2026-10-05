extends Node
## Track layouts: every track reversed, Neo Tokyo's inner-city circuit (both ways) load, the car
## starts on the road facing the way the lap goes, and drives off.
## Run: godot --headless --path . res://tests/layouts_test.tscn   (LAYOUTS="ridge:reverse,…" to pick)

const World = preload("res://scripts/world/world.gd")

var fails := 0


func _ready() -> void:
	Game.persist = false
	var list := ["ridge:reverse", "harbor:reverse", "playground:reverse", "utah:reverse", "tokyo:city", "tokyo:city_reverse", "tokyo:reverse", "gruene_hoelle:reverse"]
	if OS.get_environment("LAYOUTS") != "":
		list = OS.get_environment("LAYOUTS").split(",")
	for e in list:
		var parts: PackedStringArray = str(e).split(":")
		var world := World.new()
		world.setup({"track": parts[0], "layout": parts[1], "mode": "race", "laps": 1, "time_of_day": "day", "weather": "dry",
			"day_cycle": 0, "weather_seed": 3, "online": false})
		add_child(world)
		if not world.is_loaded:
			await world.loaded
		var tr = world.track
		var car = world.local_car
		var i: int = tr.nearest_index(car.global_position)
		var fwd: Vector3 = -car.global_transform.basis.z
		var facing: float = fwd.dot(tr.tangents[i])
		var proj: Array = tr.project(car.global_position, i)
		print("%s: %d m, start %d, facing %.2f, lateral %.1f, lb %s" % [e, int(tr.length), tr.start_index, facing, float(proj[2]), tr.lb_id()])
		if facing < 0.8 or absf(float(proj[2])) > float(tr.half_w):
			fails += 1
			print("FAIL: %s start wrong" % e)
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("LAYOUTS TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
