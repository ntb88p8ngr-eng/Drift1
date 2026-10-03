extends Node
## World editor roads always lie on the ground: laid flat and with a thickness (1.5 m) over hilly
## ground, the surface is never more than its thickness above the ground under it (no gap, nothing
## floating) and never under the ground.
## Run: godot --headless --path . res://tests/road_ground_test.tscn

const World = preload("res://scripts/world/world.gd")
const RoadBuilder = preload("res://scripts/editor/road_builder.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "ridge", "mode": "editor", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var ed = world.editor
	var t = world.terrain
	var car_p: Vector3 = world.local_car.global_position
	var hill := Vector3.ZERO
	for a in 64:
		var p := car_p + Vector3(cos(a * 0.4), 0, sin(a * 0.4)) * (60.0 + a * 3.0)
		if t._dist_raw(p.x, p.z) > 60.0 and t.inside(p.x, p.z):
			hill = Vector3(p.x, t.height_at(p.x, p.z), p.z)
	var ok := true
	for thick in [0.0, 1.5]:
		var r := {"pts": [hill + Vector3(-40, 0, 40), hill + Vector3(0, 0, 60), hill + Vector3(40, 0, 40)],
			"width": 12.0, "surface": "asphalt", "flatten": false, "height": thick, "lift": 0.0}
		var body: StaticBody3D = RoadBuilder.build(ed.holder, world, r)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var line = RoadBuilder.centre_line(world, r["pts"])
		var worst_gap := -1e9
		var worst_under := -1e9
		for i in range(0, line.size(), 3):
			var c: Vector3 = line[i]
			var d: Vector3 = (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)])
			var n := Vector3(-d.z, 0, d.x).normalized()
			for f in [-0.45, -0.2, 0.0, 0.2, 0.45]:
				var p: Vector3 = c + n * 12.0 * f
				var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 500, p.z), Vector3(p.x, -500, p.z), 1)
				q.exclude = []
				var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
				if hit.is_empty() or hit["collider"] != body:
					continue
				var gy: float = t.height_at(p.x, p.z)
				var above: float = float(hit["position"].y) - gy
				worst_gap = maxf(worst_gap, above - thick)
				worst_under = maxf(worst_under, -above)
		print("ROAD thick %.1f: surface above ground+thickness by up to %.2f m, under the ground by up to %.2f m" % [thick, worst_gap, worst_under])
		ok = ok and worst_gap < 0.2 and worst_under < 0.0
		body.queue_free()
	print("ROAD GROUND TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
