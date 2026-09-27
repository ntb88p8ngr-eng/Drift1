extends CanvasLayer
## Pause menu (Esc / Start). Pauses the game offline; online the race keeps running.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

var world   # world.gd
var _main_box: VBoxContainer
var _controls_box: VBoxContainer
var _options_box: VBoxContainer
var _panel: PanelContainer
var _was_captured := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var stack := VBoxContainer.new()
	_panel = UiKit.panel(stack)
	center.add_child(_panel)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 10)
	_main_box.add_child(UiKit.title("PAUSE", 48))
	_main_box.add_child(UiKit.button("Weiter", toggle))
	if not world.online:
		_main_box.add_child(UiKit.button("Neustart", func(): _close_then(Callable(world, "request_restart"))))
	_main_box.add_child(UiKit.button("Steuerung", func(): _show(_controls_box)))
	_main_box.add_child(UiKit.button("Optionen", func(): _show(_options_box)))
	if world.mode == "free":
		_main_box.add_child(UiKit.button("Session beenden (Punkte speichern)", func(): _close_then(Callable(world, "end_free_session"))))
	if world.online:
		_main_box.add_child(UiKit.button("Lobby verlassen", func(): _close_then(Callable(world, "request_leave_online"))))
	else:
		_main_box.add_child(UiKit.button("Zum Hauptmenü", func(): _close_then(Callable(world, "request_main_menu"))))
	stack.add_child(_main_box)

	_controls_box = VBoxContainer.new()
	_controls_box.add_child(UiKit.title("STEUERUNG", 36))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for pair in Game.CONTROLS_HELP:
		grid.add_child(UiKit.label(pair[0], 18, UiKit.GOLD))
		grid.add_child(UiKit.label(pair[1], 18))
	_controls_box.add_child(grid)
	_controls_box.add_child(UiKit.spacer())
	_controls_box.add_child(UiKit.button("Zurück", func(): _show(_main_box)))
	_controls_box.visible = false
	stack.add_child(_controls_box)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 10)
	_options_box.add_child(UiKit.title("OPTIONEN", 36))
	_options_box.add_child(UiKit.labeled("Lautstärke", UiKit.slider(0, 1, 0.05, float(Game.settings["master_volume"]),
		func(v): Game.set_setting("master_volume", v))))
	_options_box.add_child(UiKit.labeled("Motorsound", UiKit.slider(0, 1.5, 0.05, float(Game.settings["engine_volume"]),
		func(v):
			Game.settings["engine_volume"] = v
			Game.save_settings()
			if world.local_car and world.local_car.audio:
				world.local_car.audio.set_volume(v))))
	_options_box.add_child(UiKit.labeled("Konter-Lenkhilfe", UiKit.slider(0, 1, 0.05, float(Game.settings["steer_assist"]),
		func(v): Game.set_setting("steer_assist", v))))
	_options_box.add_child(UiKit.labeled("Sichtfeld (FOV)", UiKit.slider(60, 100, 1, float(Game.settings["fov"]),
		func(v):
			Game.set_setting("fov", v)
			world.camera._base_fov = v)))
	_options_box.add_child(UiKit.labeled("Maus-Empfindlichkeit", UiKit.slider(0.05, 1.0, 0.05, float(Game.settings["mouse_sensitivity"]),
		func(v): Game.set_setting("mouse_sensitivity", v))))
	var trans := UiKit.option(["Automatik", "Manuell"], 0 if world.local_car.transmission == "auto" else 1, func(i):
		world.local_car.transmission = "auto" if i == 0 else "manual"
		Game.set_setting("transmission", world.local_car.transmission))
	_options_box.add_child(UiKit.labeled("Getriebe", trans))
	_options_box.add_child(UiKit.spacer())
	_options_box.add_child(UiKit.button("Zurück", func(): _show(_main_box)))
	_options_box.visible = false
	stack.add_child(_options_box)


func _show(box: Control) -> void:
	for b in [_main_box, _controls_box, _options_box]:
		(b as Control).visible = b == box


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if world and world.hud and world.hud.results_visible():
			return
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	_show(_main_box)
	if not world.online:
		get_tree().paused = visible
	if visible:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		(_main_box.get_child(1) as Button).grab_focus()
	elif _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if world.local_car:
		world.local_car.input_enabled = not visible and not world.finished


func _close_then(action: Callable) -> void:
	visible = false
	get_tree().paused = false
	action.call()
