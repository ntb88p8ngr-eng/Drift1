extends Node3D
## Looks at a GLB from the side, front and top (by eye). Run: godot --path . res://tests/glb_view.tscn -- --glb=/abs/file.glb --out=/tmp/v

func _ready() -> void:
	var path := ""
	var out := "/tmp/v"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="):
			path = a.substr(6)
		if a.begins_with("--out="):
			out = a.substr(6)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(path, st)
	var scene := doc.generate_scene(st) as Node3D
	add_child(scene)
	var bb := AABB()
	var first := true
	for c in scene.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (c as MeshInstance3D).global_transform * (c as MeshInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	print("BOUNDS ", bb)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.5, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = bb.size.length() * 0.75
	cam.far = bb.size.length() * 10.0
	add_child(cam)
	cam.current = true
	var c := bb.get_center()
	var d := bb.size.length() * 2.0
	for v in [["side", Vector3(1, 0, 0)], ["front", Vector3(0, 0, -1)], ["top", Vector3(0, 1, 0.001)], ["three", Vector3(1, 0.6, -1).normalized()]]:
		cam.global_position = c + v[1] * d
		cam.look_at(c, Vector3.UP)
		for f in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, v[0]])
	get_tree().quit()
