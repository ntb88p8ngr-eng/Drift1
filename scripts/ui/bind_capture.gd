extends Node
## Waits for the next key (keyboard mode) or gamepad button / stick / trigger (pad mode) and hands it
## to `captured`. Esc (keyboard) or Start (gamepad) cancels, so do 6 s without input.

signal captured(key: int, pad: Array)
signal cancelled

var pad := false
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	if _t > 6.0:
		cancelled.emit()
		queue_free()


func _input(event: InputEvent) -> void:
	if _t < 0.25:
		# the press that opened the capture (A / Enter / click) must not be taken as the new binding
		if event is InputEventKey or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	if not pad and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE:
			cancelled.emit()
		else:
			captured.emit(int(event.physical_keycode), [])
		queue_free()
	elif pad and event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		if event.button_index == JOY_BUTTON_START:
			cancelled.emit()
		else:
			captured.emit(-1, [0, int(event.button_index), 1.0])
		queue_free()
	elif pad and event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		get_viewport().set_input_as_handled()
		captured.emit(-1, [1, int(event.axis), signf(event.axis_value)])
		queue_free()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()   # nothing else reacts while waiting
