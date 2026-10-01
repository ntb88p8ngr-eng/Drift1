extends Node
## Gamepad in the menus: every screen has a focused control, (A) presses it, (B) goes back.
## Run: godot --headless --path . res://tests/menu_pad_test.tscn

var fails := 0


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await get_tree().process_frame


func _ready() -> void:
	Game.persist = false
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for f in 30:
		await get_tree().process_frame
	var menu = main.menu
	var vp := get_viewport()
	if vp.gui_get_focus_owner() == null:
		print("FAIL: nothing focused on the main screen"); fails += 1
	for screen in ["single", "garage", "leaderboard", "controls", "options"]:
		menu.show_screen(screen)
		for f in 4:
			await get_tree().process_frame
		var foc = vp.gui_get_focus_owner()
		print("  %s: focus on %s" % [screen, foc.get_class() + " '" + str(foc.get("text")) + "'" if foc else "nothing"])
		if foc == null:
			print("FAIL: %s: nothing focused" % screen); fails += 1
		await _pad(JOY_BUTTON_B)
		if menu.current != "main":
			print("FAIL: (B) on %s did not go back (now %s)" % [screen, menu.current]); fails += 1
	# options: up from the first option reaches the tab row, right switches the tab
	menu.show_screen("options")
	for f in 4:
		await get_tree().process_frame
	await _pad(JOY_BUTTON_DPAD_UP)
	var tb = vp.gui_get_focus_owner()
	var tab0 := -1
	if tb is TabBar:
		tab0 = tb.current_tab
		await _pad(JOY_BUTTON_DPAD_RIGHT)
	print("  options: up -> %s, tab %d -> %d" % [tb.get_class() if tb else "nothing", tab0, tb.current_tab if tb is TabBar else -1])
	if not (tb is TabBar) or tb.current_tab == tab0:
		print("FAIL: the options tabs cannot be switched with the gamepad"); fails += 1
	await _pad(JOY_BUTTON_B)
		# (A) on the focused main-screen entry: "Einzelspieler" is the second button
	for f in 4:
		await get_tree().process_frame
	var foc2 = vp.gui_get_focus_owner()
	if foc2:
		await _pad(JOY_BUTTON_DPAD_DOWN)
		await _pad(JOY_BUTTON_A)
		print("  (A) on the 2nd main entry -> screen %s" % menu.current)
		if menu.current != "single":
			print("FAIL: (A) did not open the single player screen"); fails += 1
	print("MENU PAD TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
