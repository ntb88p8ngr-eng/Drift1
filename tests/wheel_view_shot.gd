extends Node
## One shot of a main menu view (default the rim view, "wheels"), with the menu drawn over it;
## --shutter rolls the shutter down first.
## Run: godot --path . res://tests/wheel_view_shot.tscn -- --out=/tmp/wheel.png [--view=overview] [--shutter]

const Main = preload("res://scripts/main.gd")


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/wheel.png"
	var view := "wheels"
	var shutter := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--view="):
			view = a.substr(7)
		if a == "--shutter":
			shutter = true
	var main := Main.new()
	add_child(main)
	for f in 4:
		await get_tree().process_frame
	var sr = main.showroom
	sr.set_view(view)
	if shutter:
		sr.toggle_shutter()
	# swing the platform round and settle the camera in big steps (few frames to render)
	for f in 25:
		sr._process(0.4)
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
