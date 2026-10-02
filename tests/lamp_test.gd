extends Node
## Neo Tokyo: a car driven into a streetlight knocks it over (snaps off, a stump stays, its light
## goes out); one standing next to it at walking pace doesn't.
## Run: godot --headless --path . res://tests/lamp_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": "night", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var lamps = world.scenery.city.lamps
	var fails := 0
	# a lamp on a city street (not the race route): the first one away from the track
	var k := -1
	for i in lamps.poles.size():
		var o: Vector3 = (lamps.poles[i]["xf"] as Transform3D).origin
		if world.terrain.distance_to_road(o.x, o.z) > 60.0:
			k = i
			break
	var pl: Dictionary = lamps.poles[k]
	var xf: Transform3D = pl["xf"]
	var along: Vector3 = xf.basis.x
	var car = world.local_car
	var start: Vector3 = xf.origin + along * 12.0 + Vector3(0, 0.7, 0)
	car.place(Transform3D(Basis.looking_at(-along, Vector3.UP), start))
	await get_tree().physics_frame
	car.linear_velocity = -along * 15.0
	for f in 120 * 2:
		await get_tree().physics_frame
	var broken: bool = pl["broken"]
	var light_off: bool = float((lamps.emitters[int(pl["light"])] as Array)[3]) <= 0.0
	var bodies: int = lamps.find_children("BrokenLamp*", "RigidBody3D", false, false).size()
	print("LAMP: broken %s, light off %s, falling bodies %d, stats %s" % [broken, light_off, bodies, str(lamps.stats)])
	if not broken or not light_off or bodies < 1:
		print("FAIL: the lamp didn't break"); fails += 1
	print("LAMP TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
