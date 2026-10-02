extends Node
## The HUD's 3D direction arrow at a few angles (straight, right, sharp left, wrong way).
## Run: godot --path . res://tests/arrow_shots.tscn -- --out=/tmp/shots

const IsoArrow = preload("res://scripts/ui/iso_arrow.gd")
const IsoCompass = preload("res://scripts/ui/iso_compass.gd")


func _ready() -> void:
	var out := "/tmp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.3, 0.36)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var specs := [[0.0, Color(1.0, 0.55, 0.1)], [1.2, Color(1.0, 0.55, 0.1)], [-0.7, Color(1.0, 0.55, 0.1)], [PI, Color(1.0, 0.12, 0.08)]]
	for k in specs.size():
		var a := IsoArrow.new()
		a.position = Vector2(k * 250, 40)
		a.size = Vector2(160, 112)
		bg.add_child(a)
		a.yaw = specs[k][0]
		a.tint = specs[k][1]
		a._yaw_now = specs[k][0]
	var cp := IsoCompass.new()
	cp.position = Vector2(4 * 250, 40)
	cp.size = Vector2(132, 96)
	bg.add_child(cp)
	cp.bearing = 0.9
	cp._now = 0.9
	for f in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("arrows.png"))
	get_tree().quit()
