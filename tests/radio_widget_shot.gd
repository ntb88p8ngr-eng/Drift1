extends Control
## The radio widget on its own: on, a station, the volume at 60 %, a button pressed.
## Run: godot --path . res://tests/radio_widget_shot.tscn -- --out=/tmp/rw.png

func _ready() -> void:
	var out := "/tmp/rw.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	Game.persist = false
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var w = load("res://scripts/ui/radio_widget.gd").new()
	w.floating = false
	w.position = Vector2(20, 20)
	w.size = Vector2(1160, 380)
	add_child(w)
	Radio.on = true
	Radio.volume = 0.6
	Radio.bass = 1.0
	Radio.treble = -1.0
	Radio.status = "PLAY"
	Radio.title = "Led Zeppelin - Kashmir"
	for f in 30:
		await get_tree().process_frame
	w._press("p3")
	for f in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("knob: ", w._knob != null, " buttons: ", w._btn_nodes.keys())
	get_tree().quit()
