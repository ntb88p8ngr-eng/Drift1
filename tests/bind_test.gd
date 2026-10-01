extends Node
## Rebinding: the controls page captures a key / a gamepad input, the action reacts to it, the old
## one no longer does, and "Standardbelegung" restores the defaults.
## Run: godot --headless --path . res://tests/bind_test.tscn

const SettingsUi = preload("res://scripts/ui/settings_ui.gd")


func _key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _ready() -> void:
	Game.persist = false
	var fails := 0
	var page := SettingsUi.controls_page()
	add_child(page)
	await get_tree().process_frame
	# the handbrake's keyboard field
	var btn: Button = null
	for b in page.find_children("*", "Button", true, false):
		if b.get_parent() is HBoxContainer and b.get_parent().get_child(0) is Label and (b.get_parent().get_child(0) as Label).text == "Handbremse":
			btn = b
			break
	if btn == null:
		print("FAIL: no handbrake field"); get_tree().quit(1); return
	print("handbrake keyboard before: %s" % btn.text)
	btn.pressed.emit()
	for f in 30:
		await get_tree().process_frame
	_key(KEY_H, true)
	await get_tree().process_frame
	_key(KEY_H, false)
	await get_tree().process_frame
	print("handbrake keyboard after: %s" % btn.text)
	_key(KEY_H, true)
	await get_tree().physics_frame
	if not Input.is_action_pressed("handbrake"):
		print("FAIL: H does not pull the handbrake"); fails += 1
	_key(KEY_H, false)
	_key(KEY_SPACE, true)
	await get_tree().physics_frame
	if Input.is_action_pressed("handbrake"):
		print("FAIL: space still pulls the handbrake"); fails += 1
	_key(KEY_SPACE, false)
	# gamepad: nitro on the right stick pushed up
	Game.rebind("nitro", -1, [1, JOY_AXIS_RIGHT_Y, -1.0])
	print("nitro pad: %s" % Game.binding_text("nitro", true))
	if Game.binding_text("nitro", true) != "Rechter Stick ↑" or Game.binding_text("nitro", false) == "–":
		print("FAIL: nitro pad binding"); fails += 1
	Game.reset_bindings()
	if Game.binding_text("handbrake", false) != "Space" or not Game.settings["bindings"].is_empty() \
			or Game.binding_text("nitro", true) != "(B)":
		print("FAIL: reset"); fails += 1
	print("after reset: handbrake %s, nitro %s" % [Game.binding_text("handbrake", false), Game.binding_text("nitro", true)])
	print("BIND TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
