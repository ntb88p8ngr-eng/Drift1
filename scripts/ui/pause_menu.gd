extends CanvasLayer
## Pause menu (Esc / Start). Pauses the game offline; online the race keeps running.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const SettingsUi = preload("res://scripts/ui/settings_ui.gd")

var world   # world.gd
var _main_box: VBoxContainer
var _controls_box: VBoxContainer
var _options_box: VBoxContainer
var _options_back: Button
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
	_main_box.add_child(UiKit.button("Optionen", func(): _show(_options_box)))
	if world.mode == "free":
		_main_box.add_child(UiKit.button("Session beenden (Punkte speichern)", func(): _close_then(Callable(world, "end_free_session"))))
	if world.online:
		_main_box.add_child(UiKit.button("Lobby verlassen", func(): _close_then(Callable(world, "request_leave_online"))))
	else:
		_main_box.add_child(UiKit.button("Zum Hauptmenü", func(): _close_then(Callable(world, "request_main_menu"))))
	stack.add_child(_main_box)

	_controls_box = VBoxContainer.new()
	_controls_box.visible = false
	stack.add_child(_controls_box)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 10)
	_options_box.add_child(UiKit.title("OPTIONEN", 36))
	_options_box.add_child(UiKit.label("Kategorie wechseln: RB / LB  ·  E / Q", 15, UiKit.TEXT_DIM))
	_options_box.add_child(SettingsUi.tabs(Callable(), true))
	var trans := UiKit.option(["Automatik", "Manuell"], 0 if world.local_car.transmission == "auto" else 1, func(i):
		world.local_car.transmission = "auto" if i == 0 else "manual"
		Game.set_setting("transmission", world.local_car.transmission))
	_options_box.add_child(UiKit.labeled("Getriebe", trans))
	var car_id: String = world.local_car.car_id
	var burble := UiKit.option(Game.BURBLE_LEVELS, Game.get_burble(car_id), func(i):
		Game.set_burble(car_id, i)
		if world.online:
			Net.update_local_info())
	burble.tooltip_text = "Fehlzündungen im Schiebebetrieb: Blubbern, Knallen und Flammen."
	_options_box.add_child(UiKit.labeled("Burble-Tune", burble))
	_options_box.visible = false
	stack.add_child(_options_box)
	# "Zurück" pinned to the bottom right corner while the options are open
	_options_back = UiKit.button("◀  Zurück", func(): _show(_main_box), 240)
	_options_back.custom_minimum_size.y = 58
	_options_back.add_theme_font_size_override("font_size", 24)
	_options_back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_options_back.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_options_back.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_options_back.offset_right = -40
	_options_back.offset_bottom = -36
	_options_back.visible = false
	root.add_child(_options_back)


func _show(box: Control) -> void:
	for b in [_main_box, _controls_box, _options_box]:
		(b as Control).visible = b == box
	_options_back.visible = box == _options_box
	if visible:
		(func() -> void: UiKit.focus_first(box)).call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if world and world.hud and world.hud.results_visible():
			return
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		# (B) / Esc: out of the options back to the pause list, from there back into the game
		get_viewport().set_input_as_handled()
		if _main_box.visible:
			toggle()
		else:
			_show(_main_box)


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
