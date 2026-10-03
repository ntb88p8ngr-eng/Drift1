extends Node
## The world editor by eye: a raised hill, a road with live preview, water, placed objects, the UI.
## Run: godot --path . res://tests/editor_shots.tscn -- --out=/tmp/e

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/e"
	var track := "ridge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--track="):
			track = a.substr(8)
	var world := World.new()
	world.setup({"track": track, "mode": "editor", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var ed = world.editor
	var t = world.terrain
	var car_p: Vector3 = world.local_car.global_position
	var hill := Vector3.ZERO
	for a in 64:
		var p := car_p + Vector3(cos(a * 0.4), 0, sin(a * 0.4)) * (60.0 + a * 3.0)
		if t._dist_raw(p.x, p.z) > 60.0 and t.inside(p.x, p.z):
			hill = Vector3(p.x, t.height_at(p.x, p.z), p.z)
			break
	ed._focus = hill
	ed._dist = 110.0
	ed._pitch = -0.6
	ed.tool = "raise"
	ed.brush_r = 22.0
	ed._stroke = true
	ed._stroke_old = {}
	for i in 90:
		ed._brush(hill, 1.0 / 60.0)
	ed._release()
	for k in 5:
		var p := hill + Vector3(20 + k * 6, 0, -10)
		p.y = t.height_at(p.x, p.z)
		ed.place_asset = ["block:container", "tree_sakura", "glb:res://assets/props/camp/02_sundrift_overcab.glb", "prop:bus_shelter", "block:ramp"][k]
		ed._place(p)
	ed._road_pts = [hill + Vector3(-40, 0, 40), hill + Vector3(0, 0, 60), hill + Vector3(40, 0, 40)]
	ed._finish_road()
	ed._add_water(hill + Vector3(-45, 0, -30))
	ed._set_tool("road")
	ed._road_pts = [hill + Vector3(-30, 0, -50), hill + Vector3(10, 0, -45)]
	ed._update_road_preview(hill + Vector3(40, 0, -20))
	ed._mouse = Vector2(640, 360)
	for f in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "_editor.png")
	print("SHOT ", out + "_editor.png")
	get_tree().quit(0)
