extends Node
## Story mode: the camera flies to the office PC, the chapter screen sits over the monitor, and back.
## Run: godot --path . res://tests/story_fly_test.tscn

const Main = preload("res://scripts/main.gd")


func _ready() -> void:
	Game.persist = false
	var main := Main.new()
	add_child(main)
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
	while not (main.menu._story_pc and main.menu._story_pc.visible) and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var pc = main.menu._story_pc
	print("ARRIVED ", pc != null and pc.visible, " cam ", sr.cam.global_position, " ui at ", pc.position if pc else null, " scale ", pc.scale if pc else null)
	ok = ok and pc != null and pc.visible and pc.scale.x > 0.4
	main.menu._leave_story()
	t = 0.0
	while main.menu.current == "story" and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	print("BACK ", main.menu.current, " side ", main.menu._side.visible, " story ", sr.story)
	ok = ok and main.menu.current == "main" and main.menu._side.visible and not sr.story
	print("STORY TEST ", "PASS" if ok else "FAIL")
	get_tree().quit()
