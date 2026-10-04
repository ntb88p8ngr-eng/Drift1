extends Node3D
## The mechanic workshop on its own (no map): pictures from outside and inside.
## Run: godot --path . res://tests/mech_shop_shot.tscn -- --out=/tmp/shop

func _ready() -> void:
	var out := "/tmp/shop"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var shop = load("res://scripts/world/mech_shop.gd").new()
	shop.build(self, Transform3D.IDENTITY)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	ground.position.y = -0.15
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = 70
	add_child(cam)
	for v in [["outside", Vector3(-2, 4.5, -22), Vector3(0, 2, 0)], ["hall", Vector3(-2.8, 2.4, -5.3), Vector3(-6, 0.8, 1.5)],
			["engine", Vector3(-3.2, 1.7, -2.6), Vector3(-5.0, 1.0, -0.6)], ["shop", Vector3(3.9, 1.8, -5.2), Vector3(9, 1.2, 2)]]:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, v[0]])
	get_tree().quit()
