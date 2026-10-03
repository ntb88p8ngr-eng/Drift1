extends Node3D
## Every traffic car model in a row (by eye). Run: godot --path . res://tests/traffic_models_shots.tscn -- --out=/tmp/t

const TrafficCars = preload("res://scripts/world/traffic_cars.gd")

var tc
var _odo := 0.0


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/t"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.5, 0.56)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 50, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	add_child(floor_mi)
	tc = TrafficCars.new()
	add_child(tc)
	tc.setup(null)
	print("MODELS ", tc.models.size())
	process_priority = -10
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for v in [["three", Vector3(9, 4.5, -11)], ["side", Vector3(14, 1.5, 0.01)]]:
		cam.global_position = v[1]
		cam.look_at(Vector3(0, 0.6, 0), Vector3.UP)
		for f in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, v[0]])
	get_tree().quit()


func _process(delta: float) -> void:
	if tc == null:
		return
	_odo += delta * 3.0
	var cols := [Color(0.9, 0.9, 0.88), Color(0.05, 0.15, 0.5), Color(0.7, 0.03, 0.03), Color(0.85, 0.55, 0.22), Color(0.55, 0.35, 0.45), Color(1, 1, 1)]
	for i in tc.models.size():
		var z: float = (i - (tc.models.size() - 1) * 0.5) * 5.5
		tc.add(i, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, z)), cols[i % cols.size()], _odo, false)
