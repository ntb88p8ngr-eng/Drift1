extends Node
## Story mode: the camera flies to the office PC, the chapter screen sits over the monitor, and back.
## Run: godot --path . res://tests/story_fly_test.tscn

const Main = preload("res://scripts/main.gd")


func _ready() -> void:
	Game.persist = false
	var main := Main.new()
	add_child(main)
	# (the workshop builds in slices behind a loading screen first)
	while main.menu == null:
		await get_tree().process_frame
	for f in 10:
		await get_tree().process_frame
	var storm = main.find_child("Storm", true, false)
	if storm:
		storm.process_mode = Node.PROCESS_MODE_DISABLED
	var sr = main.showroom
	var ok := true
	print("PC corners ", sr.pc_screen_corners(), " normal ", sr._pc_normal)
	Engine.time_scale = 4.0
	main.menu.show_screen("story")
	var t := 0.0
	while not main.menu._at_pc and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var mid: Vector2 = sr.cam.unproject_position(sr._pc_centre())
	var px = sr.pc_pixel(mid)
	print("ARRIVED ", main.menu._at_pc, " cam ", sr.cam.global_position, " centre px ", px, " screen at ", mid)
	ok = ok and main.menu._at_pc and px != null and (px as Vector2).distance_to(Vector2(480, 270)) < 3.0
	main.menu._leave_story()
	t = 0.0
	while main.menu.current == "story" and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	print("BACK ", main.menu.current, " side ", main.menu._side.visible, " story ", sr.story)
	ok = ok and main.menu.current == "main" and main.menu._side.visible and not sr.story
	print("STORY TEST ", "PASS" if ok else "FAIL")
	get_tree().quit()
