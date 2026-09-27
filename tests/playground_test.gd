extends Node
## Playground sanity: the loose props (single-tyre stacks, barrels, crates …) stay put after loading,
## grass islands report the "grass" surface.
## Run: godot --headless --path . res://tests/playground_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var w := World.new()
	w.setup({"track": "playground", "mode": "free", "laps": 1, "time_of_day": "noon", "weather": "dry", "day_cycle": 0, "weather_seed": 1, "online": false})
	add_child(w)
	await get_tree().process_frame
	var pg = w.scenery.get_node("Playground")
	var start := {}
	for b in pg.get_children():
		if b is RigidBody3D:
			start[b] = b.global_position
	for f in 360:
		await get_tree().physics_frame
	var moved := 0
	for b in start.keys():
		if is_instance_valid(b) and (b as Node3D).global_position.distance_to(start[b]) > 0.15:
			moved += 1
			if moved <= 8:
				var shp: Shape3D = (b.get_child(1) as CollisionShape3D).shape
				print("  moved: %s %s %.2f m" % [shp.get_class(), start[b], (b as Node3D).global_position.distance_to(start[b])])
	var isl: Array = w.terrain.islands[0]
	var surf: Array = w.track.surface_at(Vector3(isl[0].x, 0, isl[0].y), w.track.nearest_index(Vector3(isl[0].x, 0, isl[0].y)))
	print("PLAYGROUND TEST: %d props, %d moved on their own, island surface %s" % [start.size(), moved, surf[1]])
	var ok: bool = moved <= start.size() / 50 and surf[1] == "grass"
	print("PLAYGROUND TEST %s" % ("OK" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)
