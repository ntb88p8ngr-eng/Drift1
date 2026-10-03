extends Node
## A car on an imported-model map (Red Mesa) stands on the model's road and can drive off: after
## settling it rests near the road height, then 4 s of throttle move it along the lap.
## Run (needs a real renderer for the mesh collision): godot --path . --rendering-driver vulkan res://tests/glbmap_drive.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var track := "red_mesa"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track = a.substr(8)
	var world := World.new()
	world.setup({"track": track, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var car = world.local_car
	var p0: Vector3 = car.global_position
	if OS.get_cmdline_user_args().has("--probe"):
		var gm = world.scenery.glb_map
		for body in gm.find_children("*", "StaticBody3D", true, false):
			var n := str(body.get_parent().name)
			if n.begins_with("asphalt") or n.begins_with("terrain"):
				var sh = (body.get_child(0) as CollisionShape3D).shape
				print("GLBDRIVE: ", n, " faces ", (sh as ConcavePolygonShape3D).get_faces().size() / 3, " at ", body.global_transform.origin)
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		for q in [p0 + Vector3(0, 20, 0), Vector3(200, 20, 200)]:
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(q, q - Vector3(0, 60, 0)))
			print("GLBDRIVE: ray ", q, " -> ", r.get("position", "none"), " ", r.get("collider", null))
	for f in 180:
		await get_tree().physics_frame
	var p1: Vector3 = car.global_position
	print("GLBDRIVE: spawn %s, after 1.5 s %s, speed %.1f" % [str(p0), str(p1), car.linear_velocity.length()])
	world.state = "running"
	car.controls_locked = false
	Input.action_press("accelerate")
	for f in 480:
		await get_tree().physics_frame
	Input.action_release("accelerate")
	var p2: Vector3 = car.global_position
	var d := Vector2(p2.x - p1.x, p2.z - p1.z).length()
	print("GLBDRIVE: after 4 s throttle %s, moved %.1f m, y %.2f, speed %.1f" % [str(p2), d, p2.y, car.linear_velocity.length()])
	var ok: bool = absf(p1.y - p0.y) < 2.0 and d > 20.0 and p2.y > -2.0 and p2.y < 6.0
	print("GLBDRIVE TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
