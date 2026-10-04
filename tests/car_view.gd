extends Node
## Quick look at one car on its own (no garage): from the side through the windows and from below.
## Run: godot --path . res://tests/car_view.tscn -- --car=r34 --out=/tmp/car   (writes side.png, under.png)

const Car = preload("res://scripts/car/car.gd")


func _ready() -> void:
	Game.persist = false
	var car_id := "r34"
	var out := "/tmp/car"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			car_id = a.substr(6)
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.65)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	add_child(sun)
	var car := Car.new()
	car.is_display = true
	car.car_id = car_id
	car.paint = Game.get_paint("red", "#ff0000", "gloss")
	add_child(car)
	car.freeze = true
	car.position = Vector3(0, 1.2, 0)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	for shot in [["side", Vector3(-4.2, 1.5, 0.3), Vector3(0, 1.3, 0.3)], ["under", Vector3(-1.6, -1.6, 1.2), Vector3(0, 1.1, 0.2)]]:
		cam.look_at_from_position(shot[1], shot[2], Vector3.UP)
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shot[0]])
	get_tree().quit()
