extends Node3D
## The car with custom rims and a paint finish (by eye). Run: godot --path . res://tests/rim_shots.tscn -- --out=/tmp/r

const Car = preload("res://scripts/car/car.gd")


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/r"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.32, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var shots := [["r34", 3, 3, "pearl", "blue"], ["mustang", 2, 1, "matte", "red"], ["m3", 6, 6, "chrome", "silver"]]
	for sh in shots:
		Game.settings["rims"] = {str(sh[0]): {"style": sh[1], "color": sh[2]}}
		var car := Car.new()
		car.car_id = sh[0]
		car.is_display = true
		car.paint = Game.get_paint(str(sh[4]), "", str(sh[3]))
		add_child(car)
		car.freeze = true
		cam.global_position = Vector3(3.2, 1.0, -2.8)
		cam.look_at(Vector3(0, 0.45, -0.6), Vector3.UP)
		for f in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("rims_%s.png" % sh[0]))
		print("SHOT ", sh[0])
		car.queue_free()
		await get_tree().process_frame
	get_tree().quit()
