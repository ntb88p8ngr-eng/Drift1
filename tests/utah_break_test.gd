extends Node
## Utah's telephone poles and fences break off when a car drives into them (and fly with physics);
## a slow car is stopped by them instead. Run: godot --headless --path . res://tests/utah_break_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "utah", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var d = world.scenery.get_node("Desert")
	print("UTAH props: poles %d, fence pieces %d" % [int(d.stats.get("poles_breakable", 0)), int(d.stats.get("fence_pieces", 0))])
	var car = world.local_car
	car.ai_fn = func() -> Array: return [0.6, 0.0, 0.0, false, false]
	var ok := true
	for kind in ["Pole", "FencePiece"]:
		var target = null
		for p in d._props:
			if (p["node"] as Node).name.begins_with(kind) and not p["down"]:
				target = p
				break
		if target == null:
			print("UTAH no ", kind)
			ok = false
			continue
		var o: Vector3 = (target["xf"] as Transform3D).origin
		# from 12 m away, across the piece
		var side: Vector3 = (target["xf"] as Transform3D).basis.z
		var start := o - side * 12.0
		start.y = world.terrain.height_at(start.x, start.z) + 0.7
		car.place(Transform3D(Basis.looking_at(side, Vector3.UP), start))
		car.linear_velocity = side * 16.0
		var broken_before := int(d.stats.get("broken", 0))
		for k in 150:
			await get_tree().physics_frame
		var broke: bool = target["down"]
		var flew: bool = broke and (target["node"] as Node3D).global_position.distance_to(o) > 1.0
		print("UTAH %s at %s: broken %s, flew %s, car now %.0f km/h" % [kind, o.snapped(Vector3.ONE * 0.1), broke, flew, car.speed * 3.6])
		ok = ok and broke and flew and int(d.stats.get("broken", 0)) > broken_before
	print("UTAH BREAK TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
