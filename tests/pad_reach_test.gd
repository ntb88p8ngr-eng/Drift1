extends Node
## Gamepad: from the focused control of every menu screen, every visible button, slider, list and
## field can be reached with the d-pad (the focus moving round by the four directions).
## Lists what cannot. Run: godot --headless --path . res://tests/pad_reach_test.tscn

const SCREENS := ["main", "main+light", "single", "garage", "online", "servers", "leaderboard", "options", "controls",
	"editor", "replays", "credits", "profile", "admin"]

var fails := 0


static func _interactive(c: Control) -> bool:
	return (c is BaseButton or (c is Range and not (c is ProgressBar)) and not (c is SpinBox) or c is LineEdit or c is TabBar or c is ItemList or c is TextEdit) and not (c is ScrollBar)


func _press(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _ready() -> void:
	Game.persist = false
	Game.first_boot = false      # (the first start's music question is a modal dialog: it has the pad)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	while main.menu == null:
		await get_tree().process_frame
	for f in 30:
		await get_tree().process_frame
	var menu = main.menu
	var vp := get_viewport()
	# a small window: the long screens (credits, profile, options …) run past its bottom
	get_window().size = Vector2i(1280, int(OS.get_environment("PAD_H")) if OS.get_environment("PAD_H") != "" else 560)
	await get_tree().process_frame
	var only := OS.get_environment("PAD_ONLY")
	for screen in SCREENS:
		if only != "" and not (only.split(",") as Array).has(screen):
			continue
		menu.show_screen(screen.trim_suffix("+light"))
		for f in 6:
			await get_tree().process_frame
		if screen.ends_with("+light"):
			menu._light_panel.visible = true     # the garage lights panel opened
			await get_tree().process_frame
		var start = vp.gui_get_focus_owner()
		if start == null:
			menu._focus_first()
			start = vp.gui_get_focus_owner()
		var all: Array = []
		for c in menu.find_children("*", "Control", true, false):
			var cc := c as Control
			# (buttons in their own window – a dialog – have its focus; page arrows / dots have LB / RB)
			if _interactive(cc) and cc.is_visible_in_tree() and not (cc as Control).get_global_rect().size.x < 2.0 \
					and cc.get_viewport() == vp and not cc.has_meta("pad_redundant"):
				all.append(cc)
		# flood fill over the four d-pad directions
		var seen := {}
		var queue: Array = []
		if start:
			queue.append(start)
			seen[start] = true
		while not queue.is_empty():
			var c: Control = queue.pop_front()
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				var nb = c.find_valid_focus_neighbor(side)
				if nb != null and not seen.has(nb):
					seen[nb] = true
					queue.append(nb)
		var missing: Array = []
		for c in all:
			if not seen.has(c):
				var why := "focus off" if (c as Control).focus_mode == Control.FOCUS_NONE else "not reached"
				missing.append("%s '%s' (%s) %s" % [c.get_class(), str(c.get("text")).substr(0, 24) if c.get("text") != null else c.name, why,
					str(menu.get_path_to(c)) if str(c.get("text")) == "" else ""])
		print("PAD %s: %d controls, %d reachable from %s%s" % [screen, all.size(), all.size() - missing.size(),
			start.get_class() if start else "nothing", "" if missing.is_empty() else ", missing:"])
		for m in missing:
			print("    ", m)
		if not missing.is_empty() or start == null:
			fails += 1
		# a long screen scrolls to its end with the d-pad (also past its last control: text below)
		var sc: ScrollContainer = menu._scroll
		var room := int(sc.get_v_scroll_bar().max_value - sc.size.y)
		if room > 20:
			var f0 = vp.gui_get_focus_owner()
			if f0 == null:
				menu._focus_first()
			for k in 60:
				await _press(JOY_BUTTON_DPAD_DOWN)
			var at_end := sc.scroll_vertical >= room - 4
			if not at_end:
				var fo = vp.gui_get_focus_owner()
				print("    (focus on %s '%s' %s)" % [fo.get_class() if fo else "-", str(fo.get("text")) if fo else "", menu.get_path_to(fo) if fo else ""])
			print("    scrolls %d / %d px with the d-pad%s" % [sc.scroll_vertical, room, "" if at_end else "  <-- NOT TO THE END"])
			if not at_end:
				fails += 1
		menu._light_panel.visible = false
		menu.show_screen("main")
		for f in 3:
			await get_tree().process_frame
	print("PAD REACH TEST: %s (%d screens with gaps)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()
