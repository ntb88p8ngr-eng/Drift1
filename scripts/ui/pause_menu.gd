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
	var editing: bool = world.mode == "editor"
	if not world.online and not editing:
		_main_box.add_child(UiKit.button("Neustart", func(): _close_then(Callable(world, "request_restart"))))
	_main_box.add_child(UiKit.button("Optionen", func(): _show(_options_box)))
	_main_box.add_child(UiKit.button("♪ Radio ein- / ausblenden", _toggle_radio))
	if world.recorder:
		_main_box.add_child(UiKit.button("Replay speichern", func(): _close_then(Callable(world, "save_replay"))))
	if world.mode == "free":
		_main_box.add_child(UiKit.button("Session beenden (Punkte speichern)", func(): _close_then(Callable(world, "end_free_session"))))
	if editing:
		_main_box.add_child(UiKit.button("Editor verlassen", func():
			_close_then(func():
				var ed = world.get("editor")
				if ed and ed.has_method("_quit"):
					ed._quit()
				else:
					world.request_main_menu())))
	elif world.online:
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
	if world.local_car == null or editing:
		_options_box.visible = false
		stack.add_child(_options_box)
		_back_button(root)
		return
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
	_back_button(root)


func _back_button(root: Control) -> void:
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


## The radio: in a race the HUD's (bottom left); in the world editor (no HUD there) one of its own.
var _ed_radio: CanvasLayer


func _toggle_radio() -> void:
	if world.mode != "editor":
		if world.hud and world.hud.has_method("_show_radio"):
			world.hud._show_radio(not world.hud._radio_box.visible)
		return
	if _ed_radio == null:
		_ed_radio = CanvasLayer.new()
		_ed_radio.layer = 9
		_ed_radio.process_mode = Node.PROCESS_MODE_ALWAYS
		world.add_child(_ed_radio)
		var frame := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.55)
		sb.border_color = Color(0, 0, 0, 1)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(6)
		frame.add_theme_stylebox_override("panel", sb)
		frame.anchor_top = 1.0
		frame.anchor_bottom = 1.0
		frame.offset_left = 14
		frame.offset_right = 424
		frame.offset_top = -146
		frame.offset_bottom = -20
		_ed_radio.add_child(frame)
		var w = load("res://scripts/ui/radio_widget.gd").new()
		w.floating = false
		w.set_anchors_preset(Control.PRESET_FULL_RECT)
		w.offset_left = 5
		w.offset_top = 5
		w.offset_right = -30
		w.offset_bottom = -5
		frame.add_child(w)
		var x := Button.new()
		x.text = "✕"
		x.flat = true
		x.add_theme_color_override("font_color", Color.WHITE)
		x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		x.offset_left = -28
		x.offset_top = 4
		x.offset_right = -4
		x.offset_bottom = 30
		x.pressed.connect(func(): _ed_radio.visible = false)
		frame.add_child(x)
	else:
		_ed_radio.visible = not _ed_radio.visible


func toggle() -> void:
	visible = not visible
	# the world editor switches this menu on only while it is open (Esc is its own key there)
	if world.mode == "editor":
		process_mode = Node.PROCESS_MODE_ALWAYS if visible else Node.PROCESS_MODE_DISABLED
	_show(_main_box)
	if not world.online:
		get_tree().paused = visible
	if visible:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		(_main_box.get_child(1) as Button).grab_focus()
	elif _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if world.local_car and world.mode != "editor":
		world.local_car.input_enabled = not visible and not world.finished


func _close_then(action: Callable) -> void:
	visible = false
	get_tree().paused = false
	action.call()
