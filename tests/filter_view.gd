extends Node3D
## Quick look at the art-style filters: the R34 on a studio floor, rendered without filter, retro and comic.
## Run: godot --path . res://tests/filter_view.tscn -- --out=/tmp/shots

const TexKit = preload("res://scripts/util/tex_kit.gd")
const Car = preload("res://scripts/car/car.gd")
const ArtFilter = preload("res://scripts/ui/art_filter.gd")


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.5, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.8, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fl.mesh = pm
	fl.material_override = TexKit.std(Color(0.3, 0.3, 0.32), 0.8)
	add_child(fl)
	for k in 5:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1 + k * 0.4, 1)
		b.mesh = bm
		b.material_override = TexKit.std(Color.from_hsv(k * 0.2, 0.7, 0.9), 0.5)
		b.position = Vector3(-4.0 + k * 2.0, bm.size.y * 0.5, -4.0)
		add_child(b)
	var car := Car.new()
	car.car_id = "r34"
	car.paint = Game.get_paint("blue")
	car.is_display = true
	add_child(car)
	car.rotation = Vector3(0, 0.6, 0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(3.5, 1.6, 5.5)
	cam.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	cam.current = true
	var art := ArtFilter.new()
	add_child(art)
	for s in 3:
		Game.settings["art_style"] = s
		art._apply()
		for f in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("filter_%d.png" % s))
		print("SHOT filter_%d" % s)
	get_tree().quit()
