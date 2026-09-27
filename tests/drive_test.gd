extends Node
## Drives each car in a straight line for 9 s (rain by default, W=dry for dry) and logs speed, gear,
## rpm and ride height – checks the terrain collision, gearing and the automatic gearbox.
## Run: godot --headless --path . res://tests/drive_test.tscn

const World = preload("res://scripts/world/world.gd")
func _ready() -> void:
	Game.persist = false
	for cid in ["r34", "mustang", "m3gt3"]:
		Game.settings["car"] = cid
		var world := World.new()
		world.setup({"track": "ridge", "mode": "free", "laps": 1, "time_of_day": "day", "weather": str(OS.get_environment("W") if OS.get_environment("W") != "" else "rain"), "weather_seed": 3, "online": false})
		add_child(world)
		for f in 5:
			await get_tree().physics_frame
		var car = world.local_car
		Input.action_press("accelerate")
		var t := 0.0
		var log_next := 0.0
		var miny := 99.0
		var maxy := -99.0
		while t < 9.0:
			await get_tree().physics_frame
			t += 1.0 / 120.0
			miny = minf(miny, car.global_position.y)
			maxy = maxf(maxy, car.global_position.y)
			if t >= log_next:
				log_next += 1.5
				print("DRIVE %s t=%.1f v=%.0f km/h gear=%d rpm=%d y=%.2f wet=%.2f grip_surface=%s" % [cid, t, car.speed_kmh(), car.gear, int(car.rpm), car.global_position.y, world.track.wetness, car.surface_name])
		Input.action_release("accelerate")
		print("DRIVE %s y range %.2f..%.2f, gears %s final %.3f" % [cid, miny, maxy, str(car.gears), car.final_drive])
		remove_child(world)
		world.queue_free()
		await get_tree().process_frame
	print("DRIVE TEST DONE")
	get_tree().quit()
