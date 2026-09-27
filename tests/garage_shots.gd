extends Node3D
## Renders views of the garage GLB (layout check). Run: godot --path . res://tests/garage_shots.tscn -- --out=/tmp/g

func _ready() -> void:
	var out := "/tmp/g"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var g: Node3D = load("res://assets/env/garage.glb").instantiate()
	add_child(g)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var views := [
		["top", Vector3(-2, 30, 0.6), Vector3(-2, 0, 0.6), true],
		["in1", Vector3(-12, 1.7, 6), Vector3(0, 1.0, -2), false],
		["in2", Vector3(8, 1.7, -6), Vector3(-6, 1.0, 3), false],
		["in3", Vector3(-2, 1.7, 8.5), Vector3(-2, 1.5, -8), false],
		["in4", Vector3(-2, 1.7, -7.5), Vector3(-2, 1.5, 8), false],
	]
	for v in views:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL if v[3] else Camera3D.PROJECTION_PERSPECTIVE
		cam.size = 40.0
		cam.fov = 70.0
		cam.global_position = v[1]
		if v[3]:
			cam.look_at(v[2], Vector3(0, 0, -1))
		else:
			cam.look_at(v[2], Vector3.UP)
		for f in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("garage_%s.png" % v[0]))
	print("GARAGE SHOTS DONE")
	get_tree().quit()
