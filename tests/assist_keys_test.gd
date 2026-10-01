extends Node
## ABS / ESP keys: K and the right stick click switch the ABS, J and the left stick click the ESP;
## (Y) short switches the camera view, held it unlocks the free camera.
## Run: godot --headless --path . res://tests/assist_keys_test.tscn

const World = preload("res://scripts/world/world.gd")

var fails := 0


func _send(ev: InputEvent, hold_frames := 2) -> void:
	ev.set("pressed", true)
	Input.parse_input_event(ev)
	for f in hold_frames:
		await get_tree().process_frame
		await get_tree().physics_frame
	var up: InputEvent = ev.duplicate()
	up.set("pressed", false)
	Input.parse_input_event(up)
	for f in 3:
		await get_tree().process_frame
		await get_tree().physics_frame


func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


func _pad(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _ready() -> void:
	Game.persist = false
	Game.settings["abs"] = true
	Game.settings["esp"] = false
	var world := World.new()
	world.setup({"track": "playground", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry", "weather_seed": 3, "online": false})
	add_child(world)
	for f in 20:
		await get_tree().physics_frame
	var car = world.local_car
	await _send(_key(KEY_K))
	var a1: bool = car.abs_on
	await _send(_pad(JOY_BUTTON_RIGHT_STICK))
	var a2: bool = car.abs_on
	await _send(_key(KEY_J))
	var e1: bool = car.esp_on
	await _send(_pad(JOY_BUTTON_LEFT_STICK))
	var e2: bool = car.esp_on
	print("ABS: K -> %s, R3 -> %s | ESP: J -> %s, L3 -> %s" % [a1, a2, e1, e2])
	if a1 or not a2 or not e1 or e2:
		print("FAIL: the ABS / ESP keys do not switch"); fails += 1
	var cam = world.camera
	var m0: int = cam.mode
	await _send(_pad(JOY_BUTTON_Y), 6)        # short press
	var m1: int = cam.mode
	await _send(_pad(JOY_BUTTON_Y), 90)       # held 0.75 s
	print("CAMERA (Y) short: mode %d -> %d, held: free look %s (mode %d)" % [m0, m1, cam.free_look, cam.mode])
	if m1 == m0 or not cam.free_look or cam.mode != m1:
		print("FAIL: (Y) short / held"); fails += 1
	print("ASSIST KEYS TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
