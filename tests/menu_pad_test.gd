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
		# a long screen: going down entry by entry, the list must scroll along so the selected
	# entry stays inside the visible part
	for screen in ["single", "options"]:
		menu.show_screen(screen)
		for f in 4:
			await get_tree().process_frame
		var hidden := 0
		var scrolled := 0
		var must_scroll := false
		for k in 25:
			await _pad(JOY_BUTTON_DPAD_DOWN)
			var fo = vp.gui_get_focus_owner()
			if fo == null:
				continue
			var sc = fo.get_parent()
			while sc != null and not (sc is ScrollContainer):
				sc = sc.get_parent()
			if sc == null:
				continue
			scrolled = maxi(scrolled, int(sc.scroll_vertical))
			must_scroll = must_scroll or r_end_below(fo, sc)
			var r: Rect2 = fo.get_global_rect()
			var view: Rect2 = sc.get_global_rect()
			if r.position.y < view.position.y - 1.0 or r.end.y > view.end.y + 1.0:
				hidden += 1
		print("  %s: 25x down, scrolled to %d px, selected entry outside the view %d times" % [screen, scrolled, hidden])
		if hidden > 0 or (must_scroll and scrolled == 0):
			print("FAIL: %s: the list does not follow the selection" % screen); fails += 1
		await _pad(JOY_BUTTON_B)
	# RB / LB switch the option categories
	menu.show_screen("options")
	for f in 4:
		await get_tree().process_frame
	var tc: TabContainer = null
	for c in menu._content.get_children():
		if c is TabContainer:
			tc = c
	var t0: int = tc.current_tab
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	var t1: int = tc.current_tab
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	var t2: int = tc.current_tab
	print("  options RB/LB: tab %d -> RB %d -> LB LB %d (of %d)" % [t0, t1, t2, tc.get_tab_count()])
	if t1 != (t0 + 1) % tc.get_tab_count() or t2 != posmod(t0 - 1, tc.get_tab_count()):
		print("FAIL: RB / LB do not switch the categories"); fails += 1
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


## The entry lies below the list's unscrolled view (so the list has to scroll to show it).
func r_end_below(fo: Control, sc: ScrollContainer) -> bool:
	return fo.get_global_rect().end.y + float(sc.scroll_vertical) > sc.get_global_rect().end.y + 1.0
