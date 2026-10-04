extends Node
## One shot of a main menu view (default the rim view, "wheels"), with the menu drawn over it;
## --shutter rolls the shutter down first.
## Run: godot --path . res://tests/wheel_view_shot.tscn -- --out=/tmp/wheel.png [--view=overview] [--shutter] [--car=m3e46] [--open] [--cam=x,y,z,lx,ly,lz]

const Main = preload("res://scripts/main.gd")


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/wheel.png"
	var view := "wheels"
	var shutter := false
	var open_up := false
	var cam_at: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--view="):
			view = a.substr(7)
		if a == "--shutter":
			shutter = true
		if a == "--open":
			open_up = true
		if a.begins_with("--cam="):
			cam_at = Array(a.substr(6).split(",")).map(func(v): return float(v))
		if a.begins_with("--car="):
			Game.settings["car"] = a.substr(6)
	var main := Main.new()
	add_child(main)
	for f in 4:
		await get_tree().process_frame
	var sr = main.showroom
	sr.set_view(view)
	if shutter:
		sr.toggle_shutter()
	if open_up:
		sr.toggle_shutter()
		sr.toggle_shutter()
	# swing the platform round and settle the camera in big steps (few frames to render)
	for f in 25:
		sr._process(0.4)
		await get_tree().process_frame
	if cam_at.size() == 6:
		# a fixed camera (x,y,z, look-at x,y,z), the menu hidden
		sr.set_process(false)
		for c in main.get_children():
			if c is CanvasLayer or c is Control:
				c.visible = false
		sr.cam.global_position = Vector3(cam_at[0], cam_at[1], cam_at[2])
		sr.cam.look_at(Vector3(cam_at[3], cam_at[4], cam_at[5]), Vector3.UP)
		for f in 4:
			await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
