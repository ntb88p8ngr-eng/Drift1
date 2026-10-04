extends CanvasLayer
## Main menu: single player setup, garage, online (host / join / LAN browser), lobby, leaderboard, options.
## The 3D showroom behind the menu shows the selected car.

const Rendezvous = preload("res://scripts/autoload/rendezvous.gd")
const RaceAI = preload("res://scripts/world/race_ai.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const MainTiles = preload("res://scripts/ui/main_tiles.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const CarBody = preload("res://scripts/car/car_body.gd")
const CarBodyScript = preload("res://scripts/car/car_body.gd")
const SettingsUi = preload("res://scripts/ui/settings_ui.gd")
const MapData = preload("res://scripts/editor/map_data.gd")
const Replay = preload("res://scripts/replay/replay.gd")
const StoryPc = preload("res://scripts/ui/story_pc.gd")

var main   # main.gd
var current := ""
var _root: Control
var _panel: PanelContainer
var _content: VBoxContainer
var _status: Label
var _chat_lines: Array = []
var _return_to := "main"
var _opts_return := "main"      # where the settings go back to (main menu or the online lobby)
var _back_fn := Callable()   # what (B) / Esc does on this screen (the Zurück / Fertig / Verlassen button)

# lobby widgets
var _lobby_players: VBoxContainer
var _lobby_settings: VBoxContainer
var _lobby_info: Label
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _float_bar: HBoxContainer
var _lan_pw: LineEdit
var _show_adv_invite := false
var _invite_box: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _lan_list: VBoxContainer
var _color_picker: ColorPickerButton
var _car_desc: Label
var _buy_row: HBoxContainer
var _car_stats: VBoxContainer
var _tuning_box: VBoxContainer
var _lb_track := 0
var _lb_cat := 0
var _lb_list: VBoxContainer
var _platform_bar: HBoxContainer   # turntable controls (main menu and garage), above the corner buttons
var _light_panel: Control
var _scroll: ScrollContainer
var _sub_panel: PanelContainer     # round the sub menus' list
var _platform_picker: ColorPickerButton
var _view_row: HBoxContainer
var _player_info: VBoxContainer   # driver / car / credits, top right
var _side: Control          # the menu column on the left
var _at_pc := false         # story mode: the camera is at the office PC, its screen takes the input


func _ready() -> void:
	# a new language: the current screen is built again (formatted texts too)
	Game.language_changed.connect(func(): show_screen.call_deferred(current))
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var margin := MarginContainer.new()
	margin.anchor_bottom = 1.0
	margin.anchor_right = 0.0
	margin.offset_right = 820
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	_root.add_child(margin)
	_side = margin
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	var t := UiKit.title("MIDNIGHT DRIFT", 64)
	outer.add_child(t)
	outer.add_child(UiKit.label(Game.t("v%s  ·  Drift-Racing mit Online-Lobbys") % Game.VERSION, 16, UiKit.TEXT_DIM))
	outer.add_child(UiKit.spacer(10))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# gamepad / keyboard: the list scrolls along with the selected entry
	scroll.follow_focus = true
	# a scrollbar in the sub menus (the main list shows none)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll = scroll
	# the sub menus sit on a rounded, translucent grey panel (the main list stays bare)
	_sub_panel = PanelContainer.new()
	_sub_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sub_panel.add_child(scroll)
	outer.add_child(_sub_panel)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	# Back / Done always in the same place: bottom right, outside the scrolling list
	_float_bar = HBoxContainer.new()
	_float_bar.add_theme_constant_override("separation", 12)
	_float_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_float_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_float_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_float_bar.offset_right = -40
	_float_bar.offset_bottom = -36
	_root.add_child(_float_bar)
	_build_platform_bar()
	_player_info = VBoxContainer.new()
	_player_info.add_theme_constant_override("separation", 4)
	_player_info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_player_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_player_info.offset_right = -40
	_player_info.offset_top = 36
	_player_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_player_info)
	_status = UiKit.label("", 17, UiKit.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(640, 0)
	outer.add_child(_status)

	Net.lobby_changed.connect(_on_lobby_changed)
	Net.chat_received.connect(_on_chat)
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(func(reason): show_status(reason, UiKit.BAD))
	Net.join_status.connect(func(text): show_status(text))
	Net.lan_lobbies_changed.connect(_refresh_lan)
	Net.upnp_finished.connect(func(_ok, _msg): _on_lobby_changed())


## Rims changed: the platform swings the car round to show them.
func _show_wheels() -> void:
	var sr = _showroom()
	if sr and sr.view != "wheels":
		sr.set_view("wheels")
		_sync_platform_buttons()


## The showroom's turntable: turn it left / right while held, pause or resume its slow turn; in the
## garage also the views (overview, rims, front, rear).
func _build_platform_bar() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -40
	box.offset_bottom = -112
	box.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(box)
	_view_row = HBoxContainer.new()
	_view_row.add_theme_constant_override("separation", 8)
	_view_row.alignment = BoxContainer.ALIGNMENT_END
	for v in [["Übersicht", "overview"], ["Felgen", "wheels"], ["Front", "front"], ["Heck", "rear"]]:
		var key: String = v[1]
		var b := UiKit.button(str(v[0]), func():
			var sr = _showroom()
			if sr:
				sr.set_view("garage" if key == "overview" and current == "garage" else key)
				_sync_platform_buttons(), 110)
		b.focus_mode = Control.FOCUS_NONE
		_view_row.add_child(b)
	box.add_child(_view_row)
	_platform_bar = HBoxContainer.new()
	_platform_bar.add_theme_constant_override("separation", 8)
	_platform_bar.alignment = BoxContainer.ALIGNMENT_END
	_platform_bar.add_child(UiKit.label("Plattform", 16, UiKit.TEXT_DIM))
	for d: float in [-1.0, 0.0, 1.0]:
		var b := UiKit.button("⟲" if d < 0.0 else ("⏸" if d == 0.0 else "⟳"), func(): pass, 64)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		if d == 0.0:
			b.name = "Pause"
			b.pressed.connect(func():
				var sr = _showroom()
				if sr:
					sr.auto_spin = not sr.auto_spin
					if sr.auto_spin:
						sr.set_view("garage" if current == "garage" else "overview")
					_sync_platform_buttons())
		else:
			b.tooltip_text = "Gedrückt halten: Plattform drehen"
			b.button_down.connect(func():
				var sr = _showroom()
				if sr:
					sr.manual_dir = d
					sr.auto_spin = false
					_sync_platform_buttons())
			b.button_up.connect(func():
				var sr = _showroom()
				if sr:
					sr.manual_dir = 0.0)
		_platform_bar.add_child(b)
	var lb := UiKit.button("💡 Licht", func(): _light_panel.visible = not _light_panel.visible, 110)
	lb.focus_mode = Control.FOCUS_NONE
	lb.tooltip_text = "Deckenlicht und Plattform-Beleuchtung einstellen"
	_platform_bar.add_child(lb)
	# the roller shutter: down / up (a small button)
	var gb := UiKit.button("⇕", func():
		var sr = _showroom()
		if sr and sr.has_method("toggle_shutter"):
			sr.toggle_shutter(), 48)
	gb.alignment = HORIZONTAL_ALIGNMENT_CENTER
	gb.focus_mode = Control.FOCUS_NONE
	gb.add_theme_font_size_override("font_size", 20)
	gb.tooltip_text = "Rolltor hoch- / runterfahren – während der Fahrt: anhalten, nochmal: weiter"
	_platform_bar.add_child(gb)
	_light_panel = _build_light_panel()
	_light_panel.visible = false
	box.add_child(_light_panel)
	box.move_child(_light_panel, 0)
	box.add_child(_platform_bar)
	box.visible = false


const PLATFORM_COLORS := [["Rot", "#ff0505"], ["Orange", "#ff6a00"], ["Gelb", "#ffd000"], ["Grün", "#10ff40"],
	["Cyan", "#00e5ff"], ["Blau", "#1040ff"], ["Lila", "#8a3dff"], ["Pink", "#ff2aa0"], ["Weiß", "#ffffff"]]


## Garage lights: the ceiling's brightness, the platform ring's brightness and colour (saved).
func _build_light_panel() -> Control:
	var ml: Dictionary = Game.settings["menu_lights"]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UiKit.label("Garagenlicht", 18, UiKit.TEXT))
	v.add_child(UiKit.labeled("Deckenlicht", UiKit.slider(0.0, 2.0, 0.05, float(ml.get("ceiling", 1.0)),
		func(x: float): _set_menu_light("ceiling", x), 220.0), 140.0))
	v.add_child(UiKit.labeled("Plattform-Licht", UiKit.slider(0.0, 2.0, 0.05, float(ml.get("platform", 1.0)),
		func(x: float): _set_menu_light("platform", x), 220.0), 140.0))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for c in PLATFORM_COLORS:
		var hex: String = c[1]
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 30)
		b.tooltip_text = str(c[0])
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(hex)
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override("normal", sb)
		var sh := sb.duplicate() as StyleBoxFlat
		sh.border_color = Color.WHITE
		sh.set_border_width_all(2)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.pressed.connect(func():
			_set_menu_light("platform_color", hex)
			_platform_picker.color = Color(hex))
		grid.add_child(b)
	_platform_picker = ColorPickerButton.new()
	_platform_picker.custom_minimum_size = Vector2(52, 30)
	_platform_picker.edit_alpha = false
	_platform_picker.tooltip_text = "Eigene Farbe"
	_platform_picker.focus_mode = Control.FOCUS_NONE
	_platform_picker.color = Color(str(ml.get("platform_color", "#ff0505")))
	_platform_picker.color_changed.connect(func(c: Color): _set_menu_light("platform_color", "#" + c.to_html(false)))
	grid.add_child(_platform_picker)
	v.add_child(UiKit.labeled("Plattform-Farbe", grid, 140.0))
	v.add_child(UiKit.button("Zurücksetzen", func():
		Game.settings["menu_lights"] = {"ceiling": 1.0, "platform": 1.0, "platform_color": "#ff0505"}
		Game.save_settings()
		var sr = _showroom()
		if sr:
			sr.apply_menu_lights()
		var open := _light_panel.visible
		var at := _light_panel.get_index()
		var parent := _light_panel.get_parent()
		_light_panel.queue_free()
		_light_panel = _build_light_panel()
		parent.add_child(_light_panel)
		parent.move_child(_light_panel, at)
		_light_panel.visible = open, 160))
	return UiKit.panel(v)


func _set_menu_light(key: String, value) -> void:
	var ml: Dictionary = Game.settings["menu_lights"]
	ml[key] = value
	Game.save_settings()
	var sr = _showroom()
	if sr and sr.has_method("apply_menu_lights"):
		sr.apply_menu_lights()


func _showroom():
	if main and is_instance_valid(main.showroom) and main.showroom.get("auto_spin") != null:
		return main.showroom
	return null


func _sync_platform_buttons() -> void:
	var sr = _showroom()
	var pause := _platform_bar.get_node_or_null("Pause") as Button
	if sr and pause:
		pause.text = "⏸" if sr.auto_spin else "▶"


func show_status(text: String, color := UiKit.GOLD) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	for c in _float_bar.get_children():
		_float_bar.remove_child(c)
		c.queue_free()
	_back_fn = Callable()


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.15, 0.62)
	sb.border_color = Color(0.6, 0.6, 0.66, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


## A big button pinned to the bottom right corner of the screen (Zurück / Fertig).
func _float_button(text: String, callback: Callable) -> Button:
	var b := UiKit.button(text, callback, 240)
	b.custom_minimum_size.y = 58
	b.add_theme_font_size_override("font_size", 24)
	_float_bar.add_child(b)
	# the corner button is the way back: (B) on the gamepad / Esc press it too
	_back_fn = callback
	return b


## A second corner button, right of the way back (e.g. START).
func _float_action(text: String, callback: Callable) -> Button:
	var b := UiKit.button(text, callback, 240)
	b.custom_minimum_size.y = 58
	b.add_theme_font_size_override("font_size", 24)
	_float_bar.add_child(b)
	return b


func show_screen(screen: String) -> void:
	if (current == "online" or current == "servers") and screen != current:
		Net.stop_lan_scan()
	current = screen
	_clear()
	_side.visible = screen != "story" and screen != "booth"
	_sub_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new() if screen == "main" else _panel_style())
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if screen == "main" else ScrollContainer.SCROLL_MODE_AUTO
	_player_info.visible = false      # (the main screen shows it again)
	if screen != "story":
		_at_pc_off()
	show_status("")
	# the turntable controls where the car is in view; the views only in the garage
	var sr = _showroom()
	var show_bar: bool = sr != null and (screen == "main" or screen == "garage")
	_platform_bar.get_parent().visible = show_bar
	_view_row.visible = screen == "garage"
	if sr and screen != "garage" and sr.view != "overview":
		sr.set_view("overview")
	# choosing the car: the camera drives over to the front left (lift, engine, the whole car)
	if sr and screen == "garage" and sr.view == "overview":
		sr.set_view("garage")
	_sync_platform_buttons()
	match screen:
		"story":
			_build_story()
		"booth":
			_build_booth()
		"single":
			_build_single()
		"garage":
			_build_garage()
		"online":
			_build_online()
		"lobby":
			_build_lobby()
		"leaderboard":
			_build_leaderboard()
		"options":
			_build_options()
		"controls":
			_build_controls()
		"editor":
			_build_editor()
		"replays":
			_build_replays()
		"credits":
			_build_credits()
		"servers":
			_build_servers()
		"admin":
			_header("ADMIN")
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 6)
			load("res://scripts/admin/admin_ui.gd").build_screen(func(c): box.add_child(c), func():
				show_screen("admin"), func(t): show_status(t, UiKit.GOOD))
			var sc := ScrollContainer.new()
			sc.custom_minimum_size = Vector2(900, 560)
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			sc.add_child(box)
			_add(sc)
			_float_button("◀  Zurück", func(): show_screen("main"))
		_:
			current = "main"
			_build_main()
	# focus first button for gamepad users
	_focus_first.call_deferred()


func _focus_first() -> void:
	if not is_inside_tree():
		return
	if not UiKit.focus_first(_content):
		UiKit.focus_first(_float_bar)


func _unhandled_input(event: InputEvent) -> void:
	# (B) on the gamepad or Esc: back (the screen's Zurück / Fertig / Verlassen)
	if event.is_action_pressed("ui_cancel") and _back_fn.is_valid():
		get_viewport().set_input_as_handled()
		_back_fn.call()
		return
	# gamepad: nothing focused yet (e.g. after a mouse click elsewhere) – the first stick / d-pad
	# move or (A) puts the focus on the screen's first control
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept")):
			_focus_first()
			get_viewport().set_input_as_handled()


func _add(c: Control) -> void:
	_content.add_child(c)


func _header(text: String) -> void:
	_add(UiKit.title(text, 34))
	_add(UiKit.sep())


# ---------------------------------------------------------------------------
# Story: the camera flies through the office door to the PC, whose screen is the chapter select
# ---------------------------------------------------------------------------
func _build_story() -> void:
	_back_fn = _leave_story
	var sr = _showroom()
	if sr == null or not sr.has_method("enter_story") or sr.pc_ui == null:
		show_status("Der Computer ist nur in der Werkstatt erreichbar.", UiKit.BAD)
		show_screen("main")
		return
	if not sr.story_arrived.is_connected(_on_story_arrived):
		sr.story_arrived.connect(_on_story_arrived)
		sr.story_left.connect(_on_story_left)
		sr.pc_ui.back_pressed.connect(_leave_story)
		sr.pc_ui.code_redeemed.connect(_fill_player_info)
	if not sr.enter_story():
		show_screen("main")


## At the PC: its screen takes the mouse (with its own pointer), the keys and the gamepad.
func _on_story_arrived() -> void:
	if current != "story":
		return
	var sr = _showroom()
	_at_pc = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	sr.pc_ui.power_on()
	_forward_mouse(get_viewport().get_mouse_position())


func _leave_story() -> void:
	_back_fn = Callable()
	_at_pc_off()
	var sr = _showroom()
	if sr and sr.story:
		sr.leave_story()
	else:
		show_screen("main")


func _on_story_left() -> void:
	if current == "story":
		show_screen("main")


func _at_pc_off() -> void:
	if _at_pc:
		_at_pc = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var sr = _showroom()
		if sr and sr.pc_ui:
			sr.pc_ui.set_cursor(Vector2.ZERO, false)


func _input(event: InputEvent) -> void:
	if not _at_pc:
		return
	var sr = _showroom()
	if sr == null or sr.pc_viewport == null:
		return
	if event.is_action_pressed("ui_cancel"):
		if sr.pc_ui and sr.pc_ui.has_method("terminal_open") and sr.pc_ui.terminal_open():
			sr.pc_ui.close_terminal()          # Esc closes the terminal first
			get_viewport().set_input_as_handled()
		return      # (back: _unhandled_input)
	if event is InputEventMouse:
		var ev := (event as InputEventMouse).duplicate() as InputEventMouse
		var px = _forward_mouse(ev.position)
		if px != null:
			ev.position = px
			ev.global_position = px
			sr.pc_viewport.push_input(ev)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		sr.pc_viewport.push_input(event)
		get_viewport().set_input_as_handled()


## Moves the PC's pointer to where the mouse is over its screen; the pixel there (or null).
func _forward_mouse(pos: Vector2):
	var sr = _showroom()
	if sr == null:
		return null
	var px = sr.pc_pixel(pos)
	if px != null:
		px = (px as Vector2).clamp(Vector2.ZERO, Vector2(StoryPc.W - 1, StoryPc.H - 1))
		sr.pc_ui.set_cursor(px, true)
	return px


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
func _build_main() -> void:
	var tut_new := not bool(Game.settings.get("tutorial_done", false))
	var play := [
		["Story-Mode", "", "story", func(): show_screen("story")],
		["Online-Modus", "Lobbys, Server", "online", func(): show_screen("online")],
		["Einzelspieler", "Rennen, Drift, Party", "single", func(): show_screen("single")],
		["Garage", "Autos, Lack, Tuning", "garage", func():
			_return_to = "main"
			show_screen("garage")],
		[Game.t("Tutorial") + ("  ★" if tut_new else ""), "Steuerung lernen", "tutorial", _ask_tutorial],
		["Lack & Sticker", "Lackierkabine: Decals bauen", "booth", func(): show_screen("booth")],
	]
	var more := [
		["Replays", "Gespeicherte Fahrten", "replays", func(): show_screen("replays")],
		["Welt-Editor", "Eigene Karten bauen", "editor", func(): show_screen("editor")],
		["Leaderboard", "Bestzeiten und Punkte", "leaderboard", func(): show_screen("leaderboard")],
		["Steuerung", "Tastatur und Gamepad", "controls", func(): show_screen("controls")],
		["Optionen", "Grafik, Audio, Spiel", "options", func():
			_opts_return = "main"
			show_screen("options")],
		["Credits", "", "credits", func(): show_screen("credits")],
		["Beenden", "", "quit", func(): get_tree().quit()],
	]
	if bool(Game.settings.get("admin_mode", false)):
		more.insert(4, ["Admin", "Werkzeuge mit Passwort", "admin", func():
			load("res://scripts/admin/admin_ui.gd").with_password(self, func(): show_screen("admin"))])
	var tiles := MainTiles.new()
	tiles.setup([play, more], ["SPIELEN", "MEHR"])
	tiles.page = 0
	_add(tiles)
	_fill_player_info()


## Lack & Sticker: the car drives into the paint booth, then the editor; "Fertig" saves and the
## car backs out onto the platform.
var _booth_ui: Control


func _build_booth() -> void:
	var sr = _showroom()
	if sr == null:
		show_screen("main")
		return
	_platform_bar.get_parent().visible = false
	var wait := UiKit.label("Das Auto fährt in die Lackierkabine …", 22, UiKit.TEXT)
	wait.position = Vector2(48, 40)
	_root.add_child(wait)
	sr.enter_booth()
	if sr.booth != "inside":
		await sr.booth_ready
	wait.queue_free()
	if current != "booth":
		return
	_booth_ui = load("res://scripts/ui/livery_editor.gd").new()
	_booth_ui.main = main
	_booth_ui.sr = sr
	_root.add_child(_booth_ui)
	_float_button("✔  Fertig", _leave_booth)


func _leave_booth() -> void:
	var sr = _showroom()
	if _booth_ui:
		_booth_ui.save()
		_booth_ui.queue_free()
		_booth_ui = null
	_clear()
	if sr and sr.booth == "inside":
		sr.leave_booth()
		await sr.booth_left
	show_screen("main")


## Driver, car and credits: top right on the main screen.
func _fill_player_info() -> void:
	_player_info.visible = true
	for c in _player_info.get_children():
		_player_info.remove_child(c)
		c.queue_free()
	var car: Dictionary = Game.get_car(Game.settings["car"])
	var paint: Dictionary = Game.get_paint(Game.settings["paint"], Game.settings["custom_color"], str(Game.settings.get("paint_finish", "gloss")))
	for l in [UiKit.label(Game.t("Fahrer: %s") % Game.settings["player_name"], 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT),
			UiKit.label(Game.t("Auto: %s – %s") % [Game.t(car["name"]), Game.t(paint["name"])], 18, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT),
			UiKit.label(Game.t("Credits: %s") % Game.format_points(int(Game.settings["credits"])), 18, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)]:
		_player_info.add_child(l)


# ---------------------------------------------------------------------------
# World editor
# ---------------------------------------------------------------------------
func _build_editor() -> void:
	_header("WELT-EDITOR")
	var info := UiKit.label("Gelände formen, Wasser, eigene Straßen, Bäume und Objekte verschieben, skalieren, löschen und neue setzen – auch eigene 3D-Modelle (.glb). Gespeicherte Karten sind im Einzelspieler unter „Eigene Karte“ fahrbar.", 16, UiKit.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(640, 0)
	_add(info)
	_add(UiKit.label("Neue Karte auf Basis von:", 19, UiKit.GOLD))
	var names: Array = []
	for t in Game.TRACKS:
		names.append(t["name"])
	var base_idx := [maxi(names.find(Game.track_name(str(Game.settings["track"]))), 0)]
	_add(UiKit.row([UiKit.option(names, base_idx[0], func(i): base_idx[0] = i, 300),
		UiKit.button("Neu erstellen", func(): main.start_editor(Game.TRACKS[base_idx[0]]["id"]), 220)]))
	_add(UiKit.spacer(8))
	var maps := MapData.list_maps()
	_add(UiKit.label("Gespeicherte Karten:" if not maps.is_empty() else "Noch keine gespeicherten Karten.", 19, UiKit.GOLD))
	for m in maps:
		var path: String = m[0]
		var del := UiKit.button("Löschen", func():
			var dlg := ConfirmationDialog.new()
			dlg.dialog_text = Game.t("Karte „%s“ löschen?") % m[1]
			add_child(dlg)
			dlg.confirmed.connect(func():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				if str(Game.settings.get("custom_map", "")) == path:
					Game.set_setting("custom_map", "")
				show_screen("editor"))
			dlg.canceled.connect(dlg.queue_free)
			dlg.popup_centered(), 140)
		_add(UiKit.row([UiKit.label("%s  ·  %s" % [m[1], Game.track_name(m[2])], 18), UiKit.button("Bearbeiten", func(): main.start_editor("", path), 180), del]))
	_add(UiKit.spacer(8))
	_add(UiKit.button("Karte importieren …", _import_map, 360))
	_float_button("◀  Zurück", func(): show_screen("main"))


# ---------------------------------------------------------------------------
# Server browser: public servers (internet, by short code) and lobbies in the LAN
# ---------------------------------------------------------------------------
var _srv_box: VBoxContainer
var _srv_pw: LineEdit


func _build_servers() -> void:
	_header("SERVERLISTE")
	_srv_pw = LineEdit.new()
	_srv_pw.placeholder_text = "nur für Server mit 🔒"
	_srv_pw.secret = true
	_srv_pw.custom_minimum_size = Vector2(260, 40)
	_add(UiKit.row([UiKit.button("⟳  Aktualisieren", func():
		Net.server_list.refresh()
		_fill_servers(), 220), UiKit.label("Passwort", 16), _srv_pw]))
	_srv_box = VBoxContainer.new()
	_srv_box.add_theme_constant_override("separation", 6)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(900, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(_srv_box)
	_add(sc)
	_add(UiKit.label("Eigene Server: MidnightDriftServer.exe (Einstellungen in server.cfg) – oder eine Lobby mit „In der öffentlichen Serverliste zeigen“.", 13, UiKit.TEXT_DIM))
	if not Net.server_list.changed.is_connected(_fill_servers):
		Net.server_list.changed.connect(_fill_servers)
	if not Net.lan_lobbies_changed.is_connected(_fill_servers):
		Net.lan_lobbies_changed.connect(_fill_servers)
	Net.start_lan_scan()
	Net.server_list.refresh()
	_fill_servers()
	_float_button("◀  Zurück", func(): show_screen("online"))


func _fill_servers() -> void:
	if current != "servers" or _srv_box == null or not is_instance_valid(_srv_box):
		return
	for c in _srv_box.get_children():
		c.queue_free()
	var head := "INTERNET"
	if Net.server_list.fetching:
		head += "  (lädt …)"
	_srv_box.add_child(UiKit.label(head, 19, UiKit.GOLD))
	if Net.server_list.last_error != "":
		_srv_box.add_child(UiKit.label(Net.server_list.last_error, 15, UiKit.BAD))
	var list: Array = Net.server_list.servers.values()
	list.sort_custom(func(a, b): return int(a["players"]) > int(b["players"]))
	if list.is_empty() and not Net.server_list.fetching:
		_srv_box.add_child(UiKit.label("Gerade keine öffentlichen Server.", 15, UiKit.TEXT_DIM))
	for sv in list:
		var e: Dictionary = sv
		var text := "%s%s   %d/%d   %s · %s%s%s" % ["🔒 " if bool(e["locked"]) else "", e["name"], int(e["players"]), int(e["max"]),
			Game.track_name(str(e["track"])), Game.mode_name(str(e["mode"])), "   [Server]" if bool(e["dedicated"]) else "",
			"   (Rennen läuft)" if bool(e["in_race"]) else ""]
		var full := int(e["players"]) >= int(e["max"])
		var b := UiKit.button("Voll" if full else "Beitreten", func():
			var err := Net.join_code(str(e["code"]), _srv_pw.text)
			show_status(err if err != "" else "Verbinde verschlüsselt …", UiKit.BAD if err != "" else UiKit.GOLD), 150)
		b.disabled = full or str(e["v"]) != Game.VERSION
		if str(e["v"]) != Game.VERSION:
			b.text = "Version %s" % e["v"]
		var row := UiKit.row([UiKit.label(text, 16), b])
		_srv_box.add_child(row)
		if str(e.get("motd", "")) != "":
			_srv_box.add_child(UiKit.label("      " + str(e["motd"]), 13, UiKit.TEXT_DIM))
	_srv_box.add_child(UiKit.spacer(6))
	_srv_box.add_child(UiKit.label("LOKALES NETZWERK", 19, UiKit.GOLD))
	if Net.lan_lobbies.is_empty():
		_srv_box.add_child(UiKit.label("Keine Lobbys im LAN gefunden.", 15, UiKit.TEXT_DIM))
	for key in Net.lan_lobbies:
		var info: Dictionary = Net.lan_lobbies[key]
		var ip := str(key).rsplit(":", true, 1)[0]
		var text := "%s%s   %d/%d   %s · %s" % ["🔒 " if bool(info.get("locked", false)) else "", info.get("name", "Lobby"),
			int(info.get("players", 0)), int(info.get("max", 8)), Game.track_name(str(info.get("track", ""))), Game.mode_name(str(info.get("mode", "")))]
		_srv_box.add_child(UiKit.row([UiKit.label(text, 16), UiKit.button("Beitreten", func():
			_lan_pw = _srv_pw
			_join(ip, int(info.get("port", Net.DEFAULT_PORT)), str(info.get("cert", ""))), 150)]))


# ---------------------------------------------------------------------------
# Credits
# ---------------------------------------------------------------------------
func _build_credits() -> void:
	_header("CREDITS")
	var Credits = load("res://scripts/ui/credits.gd")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for sec in Credits.ENTRIES:
		box.add_child(UiKit.spacer(6))
		box.add_child(UiKit.label(str(sec[0]).to_upper(), 20, UiKit.GOLD))
		for e in sec[1]:
			var line := "%s  –  %s" % [e[0], e[1]]
			var l := UiKit.label(line, 16, UiKit.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(760, 0)
			box.add_child(l)
			var sub := ("%s  ·  %s" % [e[2], e[3]]) if str(e[2]) != "" else str(e[3])
			box.add_child(UiKit.label("      " + sub, 13, UiKit.TEXT_DIM))
	box.add_child(UiKit.spacer(8))
	box.add_child(UiKit.label("Markennamen beschreiben nur die echten Autos, die die Modelle darstellen.", 13, UiKit.TEXT_DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(800, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(box)
	_add(sc)
	_float_button("◀  Zurück", func(): show_screen("main"))


# ---------------------------------------------------------------------------
# Replays
# ---------------------------------------------------------------------------
func _build_replays() -> void:
	_header("REPLAYS")
	var info := UiKit.label("Gespeichert am Ende einer Runde (Ergebnis-Bildschirm) oder im Pausemenü. Abgespielt wird die Fahrt aus den reinen Positions- und Geschwindigkeitsdaten – mit der Originalkamera oder einer freien Kamera.", 16, UiKit.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(640, 0)
	_add(info)
	var all := Replay.list()
	if all.is_empty():
		_add(UiKit.label("Noch keine Replays gespeichert.", 19, UiKit.GOLD))
	for r in all.slice(0, 12):
		var path: String = r[0]
		var h: Dictionary = r[1]
		var cars: Array = []
		for c in h.get("cars", []):
			cars.append(str(c.get("name", "?")))
		var text := "%s  ·  %s  ·  %s  ·  %s" % [str(h.get("name", "")), Game.mode_name(str(h.get("mode", ""))),
			Game.format_time(float(h.get("duration", 0.0))), ", ".join(cars)]
		var del := UiKit.button("Löschen", func():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			show_screen("replays"), 120)
		_add(UiKit.row([UiKit.label(text, 16), UiKit.button("▶ Abspielen", func(): main.start_replay(path), 160), del]))
	_float_button("◀  Zurück", func(): show_screen("main"))


## A .dmap file from elsewhere into the saved maps.
func _import_map() -> void:
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.use_native_dialog = true
	dlg.filters = PackedStringArray(["*.dmap ; Drift-Karte"])
	dlg.size = Vector2i(900, 600)
	add_child(dlg)
	dlg.file_selected.connect(func(p: String):
		var m = MapData.load_file(p)
		if m == null:
			show_status(Game.t("Keine gültige Karte: ") + p.get_file(), UiKit.BAD)
			return
		DirAccess.make_dir_recursive_absolute(MapData.MAP_DIR)
		var to := MapData.MAP_DIR.path_join(p.get_file())
		DirAccess.copy_absolute(p, ProjectSettings.globalize_path(to))
		show_screen("editor")
		show_status(Game.t("Importiert: ") + m.map_name))
	dlg.popup_centered()


## Played it already? Ask before starting it again.
func _ask_tutorial() -> void:
	if not bool(Game.settings.get("tutorial_done", false)):
		main.start_tutorial()
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Tutorial"
	dlg.dialog_text = "Du hast das Tutorial schon gespielt.\nNochmal starten?"
	dlg.ok_button_text = "Nochmal spielen"
	dlg.cancel_button_text = "Abbrechen"
	add_child(dlg)
	dlg.confirmed.connect(func():
		dlg.queue_free()
		main.start_tutorial())
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


# ---------------------------------------------------------------------------
# Single player
# ---------------------------------------------------------------------------
func _build_single() -> void:
	_header("EINZELSPIELER")
	var desc := UiKit.label("", 16, UiKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(600, 0)
	var track_names: Array = []
	var track_idx := 0
	for i in Game.TRACKS.size():
		track_names.append(Game.TRACKS[i]["name"])
		if Game.TRACKS[i]["id"] == Game.settings["track"]:
			track_idx = i
	var mode_names: Array = []
	var mode_idx := 0
	for i in Game.MODES.size():
		mode_names.append(Game.MODES[i]["name"])
		if Game.MODES[i]["id"] == Game.settings["mode"]:
			mode_idx = i
	var tod_names: Array = []
	var tod_idx := 0
	for i in Game.TIMES_OF_DAY.size():
		tod_names.append(Game.TIMES_OF_DAY[i]["name"])
		if Game.TIMES_OF_DAY[i]["id"] == Game.settings["time_of_day"]:
			tod_idx = i
	# laps for race / drift battle, match length for graffiti – only the one that matters is shown
	var gt_idx := maxi(Game.GRAFFITI_MINUTES.find(int(Game.settings.get("graffiti_minutes", 5))), 0)
	var gt_names: Array = []
	for m in Game.GRAFFITI_MINUTES:
		gt_names.append(Game.t("%d Minuten") % m)
	var graffiti_row := UiKit.labeled("Graffiti-Zeit", UiKit.option(gt_names, gt_idx, func(i):
		Game.set_setting("graffiti_minutes", Game.GRAFFITI_MINUTES[i])))
	var laps_label := UiKit.label("%d" % int(Game.settings["laps"]), 19)
	laps_label.custom_minimum_size = Vector2(40, 0)
	var laps_slider := UiKit.slider(1, 20, 1, float(Game.settings["laps"]), func(v):
		Game.set_setting("laps", int(v))
		laps_label.text = "%d" % int(v), 220)
	var laps_row := UiKit.labeled("Runden", UiKit.row([laps_slider, laps_label]))
	var party_rows := _party_rows(Game.settings, func(key, v): Game.set_setting(key, v))
	var bot_rows := _bot_rows(int(Game.settings.get("bots", 0)), int(Game.settings.get("bot_level", 1)),
		func(n): Game.set_setting("bots", n), func(l): Game.set_setting("bot_level", l))
	var update_desc := func():
		bot_rows.visible = Game.settings["mode"] == "race"
		graffiti_row.visible = Game.settings["mode"] == "graffiti"
		laps_row.visible = Game.settings["mode"] != "graffiti"
		party_rows.visible = Game.settings["track"] != "gruene_hoelle"
		var t: Dictionary = Game.TRACKS[track_names.find(Game.track_name(Game.settings["track"]))]
		var m_desc := ""
		for m in Game.MODES:
			if m["id"] == Game.settings["mode"]:
				m_desc = m["desc"]
		desc.text = "%s\n%s" % [t["desc"], m_desc]
	_add(UiKit.labeled("Strecke", UiKit.option(track_names, track_idx, func(i):
		Game.set_setting("track", Game.TRACKS[i]["id"])
		update_desc.call())))
	# maps from the world editor (they bring their own base track)
	var maps := MapData.list_maps()
	if not maps.is_empty():
		var map_names: Array = ["Keine (Originalstrecke)"]
		var map_idx := 0
		for k in maps.size():
			map_names.append("%s  (%s)" % [maps[k][1], Game.track_name(maps[k][2])])
			if maps[k][0] == str(Game.settings.get("custom_map", "")):
				map_idx = k + 1
		var map_opt := UiKit.option(map_names, map_idx, func(i):
			Game.set_setting("custom_map", "" if i == 0 else maps[i - 1][0]))
		map_opt.tooltip_text = "Im Welt-Editor gebaute Karten: ersetzt die gewählte Strecke durch ihre Basisstrecke mit allen Änderungen."
		_add(UiKit.labeled("Eigene Karte", map_opt))
	_add(UiKit.labeled("Modus", UiKit.option(mode_names, mode_idx, func(i):
		Game.set_setting("mode", Game.MODES[i]["id"])
		update_desc.call())))
	_add(laps_row)
	_add(bot_rows)
	_add(graffiti_row)
	_add(party_rows)
	var traffic_opt := UiKit.option(["Aus", "Wenig (10 / km)", "Mittel (18 / km)", "Viel (28 / km)", "Rushhour (40 / km)"], clampi(int(Game.settings.get("traffic", 0)), 0, 4), func(i):
		Game.set_setting("traffic", i))
	traffic_opt.tooltip_text = "NPC-Autos fahren auf beiden Spuren mit, wechseln die Spur und bremsen für alles vor ihnen; in Neo Tokyo auch in der ganzen Stadt. Nur offline, nicht auf Playground und Grüner Hölle."
	_add(UiKit.labeled("Verkehr", traffic_opt))
	var speed_opt := UiKit.option(["30 km/h", "50 km/h", "70 km/h", "90 km/h", "120 km/h"], clampi(int(Game.settings.get("traffic_speed", 1)), 0, 4), func(i):
		Game.set_setting("traffic_speed", i))
	speed_opt.tooltip_text = "Wie schnell der Verkehr fährt (in engen Kurven und in der Stadt langsamer)."
	_add(UiKit.labeled("Verkehrstempo", speed_opt))
	_add(UiKit.labeled("Tageszeit", UiKit.option(tod_names, tod_idx, func(i):
		Game.set_setting("time_of_day", Game.TIMES_OF_DAY[i]["id"]))))
	_add(UiKit.labeled("Tagesverlauf", _day_cycle_option(int(Game.settings["day_cycle"]), func(m): Game.set_setting("day_cycle", m))))
	_add(UiKit.labeled("Wetter", _weather_option(str(Game.settings["weather"]), func(w): Game.set_setting("weather", w))))
	_add(UiKit.labeled("Getriebe", UiKit.option(["Automatik", "Manuell"], 0 if Game.settings["transmission"] == "auto" else 1, func(i):
		Game.set_setting("transmission", "auto" if i == 0 else "manual"))))
	_add(desc)
	update_desc.call()
	_add(UiKit.spacer(8))
	_add(UiKit.button("Garage", func():
		_return_to = "single"
		show_screen("garage"), 360))
	_float_button("◀  Zurück", func(): show_screen("main"))
	_float_action("▶  START", func(): main.start_offline())


func _day_cycle_option(current: int, on_pick: Callable) -> OptionButton:
	var names: Array = []
	var sel := 0
	for i in Game.DAY_CYCLES.size():
		var m: int = Game.DAY_CYCLES[i]
		names.append(Game.day_cycle_name(m))
		if m == current:
			sel = i
	var o := UiKit.option(names, sel, func(i): on_pick.call(Game.DAY_CYCLES[i]))
	o.tooltip_text = "Die Zeit läuft ab der gewählten Tageszeit weiter – z. B. vom Sonnenuntergang in die Nacht."
	return o


func _weather_option(current: String, on_pick: Callable) -> OptionButton:
	var names: Array = []
	var sel := 0
	for i in Game.WEATHER_MODES.size():
		names.append(Game.WEATHER_MODES[i]["name"])
		if Game.WEATHER_MODES[i]["id"] == current:
			sel = i
	var o := UiKit.option(names, sel, func(i): on_pick.call(Game.WEATHER_MODES[i]["id"]))
	o.tooltip_text = "Regen macht die Strecke rutschiger, Pfützen noch mehr. Wechselhaft: Schauer kommen und gehen."
	return o


# ---------------------------------------------------------------------------
# Garage
# ---------------------------------------------------------------------------
func _build_garage() -> void:
	_header("GARAGE")
	var name_edit := LineEdit.new()
	name_edit.text = Game.settings["player_name"]
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(300, 42)
	name_edit.text_changed.connect(func(t): Game.set_setting("player_name", t.strip_edges() if t.strip_edges() != "" else "Driver"))
	_add(UiKit.labeled("Fahrername", name_edit))
	# the cars: owned ones, the shop (with prices) and the unlocked easter eggs
	var cars: Array = Game.garage_cars()
	var car_names: Array = []
	var car_idx := 0
	for i in cars.size():
		var id: String = cars[i]
		var label: String = Game.CARS[id]["name"]
		if not Game.owns_car(id):
			label = Game.t("🔒 %s – %s Cr") % [label, Game.format_points(Game.car_price(id))]
		elif bool(Game.CARS[id].get("egg", false)):
			label = "★ " + label
		car_names.append(label)
		if id == Game.settings["car"]:
			car_idx = i
	_buy_row = HBoxContainer.new()
	_add(UiKit.labeled("Auto", UiKit.option(car_names, car_idx, func(i):
		Game.set_setting("car", cars[i])
		_update_car_info()
		main.refresh_showroom(true))))
	_add(_buy_row)
	# (action codes are typed in at the office PC – Story)
	var paint_names: Array = []
	var paint_idx := 0
	for i in Game.PAINTS.size():
		paint_names.append(Game.PAINTS[i]["name"])
		if Game.PAINTS[i]["id"] == Game.settings["paint"]:
			paint_idx = i
	paint_names.append("Eigene Farbe …")
	if Game.settings["paint"] == "custom":
		paint_idx = paint_names.size() - 1
	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(120, 40)
	_color_picker.color = Color.from_string(str(Game.settings["custom_color"]), Color(0.3, 0.05, 0.5)) if str(Game.settings["custom_color"]) != "" else Color(0.3, 0.05, 0.5)
	_color_picker.edit_alpha = false
	_color_picker.visible = Game.settings["paint"] == "custom"
	_color_picker.color_changed.connect(func(c):
		Game.settings["custom_color"] = c.to_html(false)
		Game.set_setting("paint", "custom")
		main.refresh_showroom(false))
	_add(UiKit.labeled("Lackierung", UiKit.row([UiKit.option(paint_names, paint_idx, func(i):
		if i >= Game.PAINTS.size():
			_color_picker.visible = true
			Game.settings["custom_color"] = _color_picker.color.to_html(false)
			Game.set_setting("paint", "custom")
		else:
			_color_picker.visible = false
			Game.set_setting("paint", Game.PAINTS[i]["id"])
		main.refresh_showroom(false), 280), _color_picker])))
	# paint finish
	var fin_names: Array = []
	var fin_idx := 0
	for i in TexKit.PAINT_FINISHES.size():
		fin_names.append(TexKit.PAINT_FINISHES[i][1])
		if TexKit.PAINT_FINISHES[i][0] == str(Game.settings.get("paint_finish", "gloss")):
			fin_idx = i
	_add(UiKit.labeled("Lack-Effekt", UiKit.option(fin_names, fin_idx, func(i):
		Game.set_setting("paint_finish", TexKit.PAINT_FINISHES[i][0])
		main.refresh_showroom(false))))
	# rims (per car)
	var rims: Dictionary = Game.get_rims(str(Game.settings["car"]))
	var style_names: Array = []
	for st in CarBody.RIM_STYLES:
		style_names.append(st[0])
	var col_names: Array = []
	for cl in CarBody.RIM_COLORS:
		col_names.append(cl[0])
	var rim_col := UiKit.option(col_names, int(rims["color"]), func(i):
		var r2 := Game.get_rims(str(Game.settings["car"]))
		r2["color"] = i
		Game.set_rims(str(Game.settings["car"]), r2)
		main.refresh_showroom(true)
		_show_wheels(), 180)
	rim_col.disabled = int(rims["style"]) == 0
	_add(UiKit.labeled("Felgen", UiKit.row([UiKit.option(style_names, int(rims["style"]), func(i):
		var r2 := Game.get_rims(str(Game.settings["car"]))
		r2["style"] = i
		rim_col.disabled = i == 0
		Game.set_rims(str(Game.settings["car"]), r2)
		main.refresh_showroom(true)
		_show_wheels(), 280), rim_col])))
	_add(UiKit.labeled("Getriebe", UiKit.option(["Automatik (Standard)", "Manuell (E/Q schalten)"], 0 if Game.settings["transmission"] == "auto" else 1, func(i):
		Game.set_setting("transmission", "auto" if i == 0 else "manual"))))
	_car_desc = UiKit.label("", 16, UiKit.TEXT_DIM)
	_car_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_car_desc.custom_minimum_size = Vector2(600, 0)
	_add(_car_desc)
	_car_stats = VBoxContainer.new()
	_add(_car_stats)
	_add(UiKit.spacer(6))
	_add(UiKit.label("Tuning", 24, UiKit.ACCENT.lightened(0.3)))
	_tuning_box = VBoxContainer.new()
	_tuning_box.add_theme_constant_override("separation", 6)
	_add(_tuning_box)
	_update_car_info()
	_add(UiKit.spacer(8))
	_float_button("✔  Fertig", func():
		Net.update_local_info()
		show_screen(_return_to))


func _on_code_result(ok: bool, text: String) -> void:
	if current != "garage":
		return
	if ok:
		_build_garage_again()
	show_status(text, UiKit.GOOD if ok else UiKit.BAD)


func _build_garage_again() -> void:
	var msg := _status_text()
	show_screen("garage")
	show_status(msg, UiKit.GOOD)


func _status_text() -> String:
	return _status.text if _status else ""


## Buy button for a car not owned yet.
func _update_buy_row(car_id: String) -> void:
	if _buy_row == null:
		return
	for c in _buy_row.get_children():
		c.queue_free()
	if Game.owns_car(car_id):
		return
	var price := Game.car_price(car_id)
	_buy_row.add_child(UiKit.label(Game.t("Noch nicht gekauft – du hast %s Cr") % Game.format_points(int(Game.settings["credits"])), 17, UiKit.TEXT_DIM))
	_buy_row.add_child(UiKit.button(Game.t("Kaufen für %s Cr") % Game.format_points(price), func():
		var err := Game.buy_car(car_id)
		if err != "":
			show_status(err, UiKit.BAD)
			return
		show_screen("garage")
		show_status(Game.t("%s gekauft!") % Game.CARS[car_id]["name"], UiKit.GOOD), 300))


func _update_car_info() -> void:
	var car_id: String = Game.settings["car"]
	var car: Dictionary = Game.get_car(car_id)
	_update_buy_row(car_id)
	_car_desc.text = str(car["desc"])
	for c in _car_stats.get_children():
		c.queue_free()
	_update_tuning(car_id)
	var kw := float(car["torque"]) * float(car["redline"]) * 0.62 / 9549.0
	var stats := [
		["Leistung", clampf(kw / 330.0, 0.1, 1.0), Game.t("%d PS") % int(kw * 1.36)],
		["Gewicht", clampf(1.0 - (float(car["mass"]) - 900.0) / 800.0, 0.1, 1.0), "%d kg" % int(car["mass"])],
		["Grip", clampf((float(car["grip"]) - 0.9) / 0.25, 0.1, 1.0), ""],
		["Turbo", clampf(float(car["turbo"]) / 0.6, 0.0, 1.0), "Sauger" if float(car["turbo"]) <= 0.0 else "Twin-Turbo"],
		["Antrieb", float(car["rear_split"]), Game.t("%d %% hinten") % int(float(car["rear_split"]) * 100.0)],
	]
	for s in stats:
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = s[1]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(240, 14)
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiKit.ACCENT
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.15, 0.13, 0.2)
		bg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_car_stats.add_child(UiKit.labeled(s[0], UiKit.row([bar, UiKit.label(s[2], 16, UiKit.TEXT_DIM)])))


# ---------------------------------------------------------------------------
# Online: host / join / LAN
# ---------------------------------------------------------------------------
func _build_online() -> void:
	_header("ONLINE-MODUS")
	var srv := UiKit.button("Serverliste", func(): show_screen("servers"), 360)
	srv.icon = UiKit.globe_icon()
	srv.add_theme_constant_override("h_separation", 10)
	_add(srv)
	var name_edit := LineEdit.new()
	name_edit.text = Game.settings["player_name"]
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(300, 42)
	name_edit.text_changed.connect(func(t): Game.set_setting("player_name", t.strip_edges() if t.strip_edges() != "" else "Driver"))
	_add(UiKit.labeled("Fahrername", name_edit))

	_add(UiKit.label("Lobby erstellen (du bist der Host / Server)", 22, UiKit.ACCENT.lightened(0.3)))
	var lobby_name := LineEdit.new()
	lobby_name.placeholder_text = Game.t("%s's Lobby") % Game.settings["player_name"]
	lobby_name.text = str(Game.settings.get("lobby_name", ""))
	lobby_name.custom_minimum_size = Vector2(300, 42)
	_add(UiKit.labeled("Lobby-Name", lobby_name))
	var port_edit := LineEdit.new()
	port_edit.text = str(int(Game.settings["port"]))
	port_edit.custom_minimum_size = Vector2(140, 42)
	_add(UiKit.labeled("Port (UDP)", port_edit))
	var max_label := UiKit.label(str(int(Game.settings["max_players"])), 19)
	_add(UiKit.labeled("Max. Spieler", UiKit.row([UiKit.slider(2, 8, 1, float(Game.settings["max_players"]), func(v):
		Game.set_setting("max_players", int(v))
		max_label.text = str(int(v)), 200), max_label])))
	var pw_edit := LineEdit.new()
	pw_edit.text = str(Game.settings.get("lobby_password", ""))
	pw_edit.placeholder_text = "leer = ohne Passwort (nur LAN empfohlen)"
	pw_edit.secret = true
	pw_edit.max_length = 40
	pw_edit.custom_minimum_size = Vector2(300, 42)
	var show_pw := UiKit.button("👁", func(): pw_edit.secret = not pw_edit.secret, 50)
	var gen_pw := UiKit.button("Zufällig", func():
		var chars := "abcdefghjkmnpqrstuvwxyz23456789"
		var t := ""
		for k in 10:
			t += chars[randi() % chars.length()]
		pw_edit.text = t
		pw_edit.secret = false, 120)
	_add(UiKit.labeled("Lobby-Passwort", UiKit.row([pw_edit, show_pw, gen_pw])))
	var upnp := CheckBox.new()
	upnp.text = "Port automatisch per UPnP öffnen"
	upnp.button_pressed = bool(Game.settings["use_upnp"])
	upnp.toggled.connect(func(on): Game.set_setting("use_upnp", on))
	_add(upnp)
	var pub := CheckBox.new()
	pub.text = "In der öffentlichen Serverliste zeigen"
	pub.button_pressed = bool(Game.settings.get("list_public", false))
	pub.tooltip_text = "Andere finden deine Lobby unter „Serverliste“. Gezeigt werden nur Name, Spieler, Strecke und der Beitritts-Code – keine IP-Adresse."
	pub.toggled.connect(func(on): Game.set_setting("list_public", on))
	_add(pub)
	_add(UiKit.button("Lobby erstellen", func():
		var port := int(port_edit.text) if port_edit.text.is_valid_int() else Net.DEFAULT_PORT
		Game.settings["port"] = port
		Game.set_setting("lobby_name", lobby_name.text)
		Game.set_setting("lobby_password", pw_edit.text.strip_edges())
		var err := Net.host_lobby(lobby_name.text, port, int(Game.settings["max_players"]), bool(Game.settings["use_upnp"]), pw_edit.text, false, bool(Game.settings.get("list_public", false)))
		if err != "":
			show_status(err, UiKit.BAD)
		else:
			_chat_lines.clear()
			show_screen("lobby"), 360))

	_add(UiKit.spacer(10))
	_add(UiKit.label("Lobby beitreten (Internet)", 22, UiKit.ACCENT.lightened(0.3)))
	_add(UiKit.label("Gib den Code des Hosts ein (z. B. K7Q-M2X) – keine Portfreigabe nötig, verschlüsselt.", 16, UiKit.TEXT_DIM))
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "K7Q-M2X"
	code_edit.custom_minimum_size = Vector2(260, 42)
	code_edit.add_theme_font_size_override("font_size", 22)
	_add(UiKit.labeled("Code", UiKit.row([code_edit, UiKit.button("Einfügen", func():
		code_edit.text = DisplayServer.clipboard_get().strip_edges(), 120)])))
	var join_pw := LineEdit.new()
	join_pw.placeholder_text = "nur falls die Lobby ein Passwort hat"
	join_pw.secret = true
	join_pw.custom_minimum_size = Vector2(300, 42)
	_add(UiKit.labeled("Passwort", join_pw))
	_add(UiKit.button("Mit Code beitreten", func():
		var err := ""
		if Rendezvous.normalize(code_edit.text) != "":
			err = Net.join_code(code_edit.text, join_pw.text)
		else:
			# the long invite code from older versions / "Erweitert" still works
			err = Net.join_invite(code_edit.text)
		if err != "":
			show_status(err, UiKit.BAD)
		else:
			show_status("Verbinde verschlüsselt …"), 360))
	_add(UiKit.spacer(10))
	_add(UiKit.label("Lobbys im lokalen Netzwerk", 22, UiKit.ACCENT.lightened(0.3)))
	_lan_pw = LineEdit.new()
	_lan_pw.placeholder_text = "Passwort (falls die Lobby 🔒 hat)"
	_lan_pw.secret = true
	_lan_pw.custom_minimum_size = Vector2(300, 42)
	_add(UiKit.labeled("LAN-Passwort", _lan_pw))
	_lan_list = VBoxContainer.new()
	_add(_lan_list)
	Net.start_lan_scan()
	_refresh_lan()
	_add(UiKit.spacer(8))
	_float_button("◀  Zurück", func(): show_screen("main"))


func _join(ip: String, port: int, cert: String) -> void:
	var err := Net.join_lobby(ip, port, _lan_pw.text if _lan_pw and is_instance_valid(_lan_pw) else "", cert)
	if err != "":
		show_status(err, UiKit.BAD)
	else:
		show_status("Verbinde verschlüsselt …")


func _refresh_lan() -> void:
	if current != "online" or _lan_list == null or not is_instance_valid(_lan_list):
		return
	for c in _lan_list.get_children():
		c.queue_free()
	if Net.lan_lobbies.is_empty():
		_lan_list.add_child(UiKit.label("Suche … (keine Lobby gefunden)", 16, UiKit.TEXT_DIM))
		return
	for key in Net.lan_lobbies.keys():
		var info: Dictionary = Net.lan_lobbies[key]
		var text := Game.t("%s%s  –  %s  –  %d/%d Spieler%s") % ["🔒 " if info.get("locked", false) else "", info.get("name", "Lobby"),
			Game.track_name(str(info.get("track", ""))), int(info.get("players", 0)), int(info.get("max", 8)),
			"  (Rennen läuft)" if info.get("in_race", false) else ""]
		var ip: String = info.get("ip", "")
		var port := int(info.get("port", Net.DEFAULT_PORT))
		var cert := str(info.get("cert", ""))
		_lan_list.add_child(UiKit.button(text, func(): _join(ip, port, cert), 600))


func _on_connected() -> void:
	_chat_lines.clear()
	show_screen("lobby")


# ---------------------------------------------------------------------------
# Lobby
# ---------------------------------------------------------------------------
func _build_lobby() -> void:
	_header("LOBBY")
	_lobby_info = UiKit.label("", 17, UiKit.TEXT_DIM)
	_lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_info.custom_minimum_size = Vector2(640, 0)
	_add(_lobby_info)
	_invite_box = VBoxContainer.new()
	_invite_box.add_theme_constant_override("separation", 6)
	_add(_invite_box)
	_add(UiKit.label("Spieler", 22, UiKit.ACCENT.lightened(0.3)))
	_lobby_players = VBoxContainer.new()
	_add(_lobby_players)
	_add(UiKit.label("Renn-Optionen", 22, UiKit.ACCENT.lightened(0.3)))
	_lobby_settings = VBoxContainer.new()
	_lobby_settings.add_theme_constant_override("separation", 8)
	_add(_lobby_settings)
	_add(UiKit.label("Chat", 22, UiKit.ACCENT.lightened(0.3)))
	_chat_log = RichTextLabel.new()
	_chat_log.custom_minimum_size = Vector2(640, 150)
	_chat_log.scroll_following = true
	_chat_log.bbcode_enabled = true
	_add(_chat_log)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Nachricht … (Enter)"
	_chat_input.custom_minimum_size = Vector2(640, 40)
	_chat_input.text_submitted.connect(func(t):
		Net.send_chat(t)
		_chat_input.clear())
	_add(_chat_input)
	for l in _chat_lines:
		_chat_log.append_text(l + "\n")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_ready_btn = UiKit.button("Bereit", func():
		var me := Net.local_id()
		var cur: bool = Net.players.get(me, {}).get("ready", false)
		Net.set_ready(not cur), 150)
	_start_btn = UiKit.button("▶ Rennen starten", func():
		var err := Net.host_start_race()
		if err != "":
			show_status(err, UiKit.BAD), 220)
	buttons.add_child(_ready_btn)
	buttons.add_child(_start_btn)
	buttons.add_child(UiKit.button("Auto / Lack", func():
		_return_to = "lobby"
		show_screen("garage"), 160))
	var leave := func() -> void:
		Net.leave()
		show_screen("online")
	buttons.add_child(UiKit.button("Einstellungen", func():
		_opts_return = "lobby"
		show_screen("options"), 170))
	buttons.add_child(UiKit.button("Verlassen", leave, 140))
	_back_fn = leave
	_add(buttons)
	_refresh_lobby()


## Host: the invite code for internet players (contains this lobby's public address, port, password and
## certificate – only hand it to people you want to play with).
func _refresh_invite(host: bool) -> void:
	if _invite_box == null or not is_instance_valid(_invite_box):
		return
	for c in _invite_box.get_children():
		c.queue_free()
	if not host:
		return
	var port := int(Net.lobby.get("port", Net.DEFAULT_PORT))
	# the short code: all that friends need (no port forwarding)
	if Net.host_code != "":
		var sc := Rendezvous.pretty(Net.host_code)
		var big := UiKit.label(sc, 40, UiKit.GOLD)
		big.add_theme_font_override("font", UiKit.title_font())
		_invite_box.add_child(UiKit.row([UiKit.label("Code für Freunde:", 18), big, UiKit.button("Kopieren", func():
			DisplayServer.clipboard_set(sc)
			show_status(Game.t("Code %s kopiert – Freunde geben ihn unter Online → „Mit Code beitreten“ ein.") % sc), 130)], 14))
		_invite_box.add_child(UiKit.label("Keine Portfreigabe nötig. Nur an Mitspieler weitergeben.", 15, UiKit.TEXT_DIM))
	var adv := CheckButton.new()
	adv.text = "Erweitert: langer Einladungs-Code / Adresse (falls der Code nicht klappt)"
	adv.button_pressed = _show_adv_invite
	adv.toggled.connect(func(on):
		_show_adv_invite = on
		_refresh_invite(host))
	_invite_box.add_child(adv)
	if not _show_adv_invite:
		return
	var code := Net.invite_code()
	if code == "":
		var ip_edit := LineEdit.new()
		ip_edit.placeholder_text = "öffentliche IPv4 oder IPv6"
		ip_edit.custom_minimum_size = Vector2(300, 40)
		_invite_box.add_child(UiKit.label("Für Internet-Spieler wird deine öffentliche Adresse gebraucht (UPnP hat keine geliefert):", 16, UiKit.TEXT_DIM))
		_invite_box.add_child(UiKit.row([ip_edit, UiKit.button("Übernehmen", func():
			var a := str(Net.split_address(ip_edit.text, port)[0])
			if a.is_valid_ip_address():
				Net.public_ip = a
				_refresh_lobby()
			else:
				show_status("Keine gültige IP-Adresse.", UiKit.BAD), 150),
			UiKit.button("Automatisch ermitteln (IPv6 zuerst)", func(): Net.lookup_public_ip(), 360)]))
		# IPv6-only / DS-Lite connections: the PC's own global IPv6 addresses, one click each
		var v6 := Net.global_ipv6_addresses()
		if not v6.is_empty():
			_invite_box.add_child(UiKit.label("IPv6-Adressen dieses PCs – nimm die, für die im Router die Freigabe gilt (nicht die „temporäre“):", 15, UiKit.TEXT_DIM))
			for a in v6:
				var addr: String = a
				_invite_box.add_child(UiKit.button(addr, func():
					Net.public_ip = addr
					_refresh_lobby(), 460))
		return
	var code_edit := LineEdit.new()
	code_edit.text = code
	code_edit.editable = false
	code_edit.secret = true
	code_edit.custom_minimum_size = Vector2(420, 40)
	_invite_box.add_child(UiKit.labeled("Einladungs-Code", UiKit.row([code_edit, UiKit.button("Kopieren", func():
		DisplayServer.clipboard_set(code)
		show_status("Einladungs-Code kopiert – nur an Mitspieler weitergeben (enthält IP & Passwort)."), 130)])))
	var v6_host := Net.public_ip.contains(":")
	_invite_box.add_child(UiKit.row([UiKit.label(Game.t("Adresse im Code: %s (%s)") % [Net.public_ip, "IPv6" if v6_host else "IPv4"], 15, UiKit.TEXT_DIM),
		UiKit.button("Andere Adresse", func():
			Net.public_ip = ""
			_refresh_lobby(), 180)], 10))
	if v6_host:
		_invite_box.add_child(UiKit.label(Game.t("IPv6: Im Router die Freigabe für UDP-Port %d auf genau diese Adresse bzw. diesen PC setzen (FritzBox: Internet → Freigaben → Gerät → „IPv6 freigeben“ + Port), Windows-Firewall für das Spiel erlauben. Mitspieler brauchen selbst IPv6.") % port, 15, UiKit.TEXT_DIM))
	elif port > 0 and Net.upnp_message.begins_with("Kein UPnP"):
		_invite_box.add_child(UiKit.label(Game.t("Ohne UPnP: Port %d/UDP im Router auf diesen PC weiterleiten.") % port, 16, UiKit.TEXT_DIM))


func _refresh_lobby() -> void:
	if current != "lobby" or _lobby_players == null or not is_instance_valid(_lobby_players):
		return
	if not Net.is_online:
		show_screen("online")
		return
	var host := Net.is_host()
	var info_lines: Array = []
	info_lines.append(Game.t("Lobby: %s") % Net.lobby.get("name", "…"))
	if host:
		info_lines.append(Game.t("Du hostest diese Lobby (Port %d/UDP, verschlüsselt%s). Im LAN erscheint sie automatisch in der Liste.") % [
			int(Net.lobby.get("port", Net.DEFAULT_PORT)), ", mit Passwort" if Net.password != "" else ", OHNE Passwort"])
		if Net.upnp_message != "":
			info_lines.append(Net.upnp_message)
	elif bool(Net.lobby.get("dedicated", false)):
		info_lines.append("Dedizierter Server – das Rennen startet automatisch, sobald alle bereit sind.")
	else:
		info_lines.append("Verbunden (verschlüsselt) – warte darauf, dass der Host das Rennen startet.")
	_lobby_info.text = "\n".join(info_lines)
	_refresh_invite(host)

	for c in _lobby_players.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.players[id]
		var tag := "HOST" if id == 1 else ("BEREIT" if p.get("ready", false) else "nicht bereit")
		var col := UiKit.GOLD if id == 1 else (UiKit.GOOD if p.get("ready", false) else UiKit.TEXT_DIM)
		var car_name: String = Game.get_car(str(p.get("car", "r34")))["name"]
		var paint_name: String = Game.get_paint(str(p.get("paint", "red")), str(p.get("custom_color", "")))["name"]
		var me := " (du)" if id == Net.local_id() else ""
		var line := UiKit.row([
			UiKit.label(str(p.get("name", "?")) + me, 19, Color.WHITE),
			UiKit.label("%s · %s" % [car_name, paint_name], 15, UiKit.TEXT_DIM),
			UiKit.label(tag, 16, col),
		], 16)
		_lobby_players.add_child(line)

	for c in _lobby_settings.get_children():
		c.queue_free()
	var lobby := Net.lobby
	if host:
		var track_names: Array = []
		var ti := 0
		for i in Game.TRACKS.size():
			track_names.append(Game.TRACKS[i]["name"])
			if Game.TRACKS[i]["id"] == lobby.get("track", "ridge"):
				ti = i
		_lobby_settings.add_child(UiKit.labeled("Strecke", UiKit.option(track_names, ti, func(i): Net.host_set_option("track", Game.TRACKS[i]["id"]))))
		var modes: Array = []
		var mi := 0
		var race_modes := Game.MODES.filter(func(m): return m["id"] != "free")
		for i in race_modes.size():
			modes.append(race_modes[i]["name"])
			if race_modes[i]["id"] == lobby.get("mode", "race"):
				mi = i
		_lobby_settings.add_child(UiKit.labeled("Modus", UiKit.option(modes, mi, func(i): Net.host_set_option("mode", race_modes[i]["id"]))))
		if str(lobby.get("mode", "")) == "graffiti":
			var gnames: Array = []
			for m in Game.GRAFFITI_MINUTES:
				gnames.append(Game.t("%d Minuten") % m)
			var gi := maxi(Game.GRAFFITI_MINUTES.find(int(lobby.get("graffiti_minutes", 5))), 0)
			_lobby_settings.add_child(UiKit.labeled("Graffiti-Zeit", UiKit.option(gnames, gi, func(i):
				Net.host_set_option("graffiti_minutes", Game.GRAFFITI_MINUTES[i]))))
		var laps_label := UiKit.label(str(int(lobby.get("laps", 3))), 19)
		var laps_row := UiKit.labeled("Runden", UiKit.row([UiKit.slider(1, 20, 1, float(lobby.get("laps", 3)), func(v):
			laps_label.text = str(int(v))
			if int(v) != int(Net.lobby.get("laps", 3)):
				Net.host_set_option("laps", int(v)), 200), laps_label]))
		laps_row.visible = str(lobby.get("mode", "")) != "graffiti"
		_lobby_settings.add_child(laps_row)
		var brow := _bot_rows(int(lobby.get("bots", 0)), int(lobby.get("bot_level", 1)),
			func(n):
				if int(Net.lobby.get("bots", 0)) != n:
					Net.host_set_option("bots", n),
			func(l): Net.host_set_option("bot_level", l))
		brow.visible = str(lobby.get("mode", "")) == "race"
		_lobby_settings.add_child(brow)
		var tods: Array = []
		var tdi := 0
		for i in Game.TIMES_OF_DAY.size():
			tods.append(Game.TIMES_OF_DAY[i]["name"])
			if Game.TIMES_OF_DAY[i]["id"] == lobby.get("time_of_day", "dusk"):
				tdi = i
		_lobby_settings.add_child(UiKit.labeled("Tageszeit", UiKit.option(tods, tdi, func(i): Net.host_set_option("time_of_day", Game.TIMES_OF_DAY[i]["id"]))))
		_lobby_settings.add_child(UiKit.labeled("Tagesverlauf", _day_cycle_option(int(lobby.get("day_cycle", 0)), func(m): Net.host_set_option("day_cycle", m))))
		_lobby_settings.add_child(UiKit.labeled("Wetter", _weather_option(str(lobby.get("weather", "dry")), func(w): Net.host_set_option("weather", w))))
		var prow := _party_rows(lobby, func(key, v):
			if Net.lobby.get(key) != v:
				Net.host_set_option(key, v))
		prow.visible = str(lobby.get("track", "")) != "gruene_hoelle"
		_lobby_settings.add_child(prow)
		var coll := UiKit.option(["An – Autos prallen aneinander ab", "Aus – Geister-Modus (durchfahren)"], 0 if bool(lobby.get("collisions", true)) else 1, func(i):
			Net.host_set_option("collisions", i == 0))
		coll.tooltip_text = "Im Geister-Modus fahren alle durcheinander hindurch, die anderen Autos sind halbtransparent."
		_lobby_settings.add_child(UiKit.labeled("Kollisionen", coll))
	else:
		_lobby_settings.add_child(UiKit.label(Game.t("Strecke: %s") % Game.track_name(str(lobby.get("track", "ridge"))), 18))
		var len_text := (Game.t("Zeit: %d Minuten") % int(lobby.get("graffiti_minutes", 5))) if str(lobby.get("mode", "")) == "graffiti" else (Game.t("Runden: %d") % int(lobby.get("laps", 3)))
		_lobby_settings.add_child(UiKit.label(Game.t("Modus: %s  ·  %s") % [Game.mode_name(str(lobby.get("mode", "race"))), len_text], 18))
		_lobby_settings.add_child(UiKit.label(Game.t("Tageszeit: %s  ·  Kollisionen: %s") % [Game.time_name(str(lobby.get("time_of_day", "dusk"))), "an" if lobby.get("collisions", true) else "aus (Geister-Modus)"], 18))
		_lobby_settings.add_child(UiKit.label(Game.t("Wetter: %s  ·  Tagesverlauf: %s") % [Game.weather_name(str(lobby.get("weather", "dry"))), Game.day_cycle_name(int(lobby.get("day_cycle", 0)))], 18))
		if str(lobby.get("mode", "")) == "race" and int(lobby.get("bots", 0)) > 0:
			_lobby_settings.add_child(UiKit.label(Game.t("KI-Gegner: %d  ·  %s") % [int(lobby.get("bots", 0)), RaceAI.LEVELS[clampi(int(lobby.get("bot_level", 1)), 0, 3)]["name"]], 18))
		if bool(lobby.get("party", false)) and str(lobby.get("track", "")) != "gruene_hoelle":
			_lobby_settings.add_child(UiKit.label(Game.t("★ Party-Modus: %d Minispiele, %d Münzen") % [int(lobby.get("party_games", 3)), int(lobby.get("party_coins", 5))], 18, UiKit.GOLD))
	var me_ready: bool = Net.players.get(Net.local_id(), {}).get("ready", false)
	_ready_btn.visible = not host
	_ready_btn.text = "Nicht bereit" if me_ready else "Bereit"
	_start_btn.visible = host
	_start_btn.disabled = not Net.all_ready()


func _on_lobby_changed() -> void:
	if current == "lobby":
		_refresh_lobby()


func _on_chat(from_name: String, text: String) -> void:
	var line := "[color=#b58cff]%s:[/color] %s" % [from_name.replace("[", "("), text.replace("[", "(")]
	_chat_lines.append(line)
	if _chat_lines.size() > 100:
		_chat_lines.pop_front()
	if current == "lobby" and _chat_log and is_instance_valid(_chat_log):
		_chat_log.append_text(line + "\n")


# ---------------------------------------------------------------------------
# Leaderboard
# ---------------------------------------------------------------------------
func _build_leaderboard() -> void:
	_header("LEADERBOARD")
	var track_names: Array = []
	for t in Game.TRACKS:
		track_names.append(t["name"])
	var cats := [["drift", "Driftpunkte (Session/Rennen)"], ["combo", "Bester Einzeldrift"], ["lap", "Beste Runde"], ["race", "Rennzeit"]]
	var cat_names: Array = []
	for c in cats:
		cat_names.append(c[1])
	_add(UiKit.labeled("Strecke", UiKit.option(track_names, _lb_track, func(i):
		_lb_track = i
		_fill_leaderboard(cats))))
	_add(UiKit.labeled("Kategorie", UiKit.option(cat_names, _lb_cat, func(i):
		_lb_cat = i
		_fill_leaderboard(cats))))
	_lb_list = VBoxContainer.new()
	_add(_lb_list)
	_fill_leaderboard(cats)
	_add(UiKit.spacer(8))
	_add(UiKit.button("Leaderboard zurücksetzen", func():
		Game.clear_leaderboard()
		_fill_leaderboard(cats)
		show_status("Leaderboard gelöscht."), 360))
	_float_button("◀  Zurück", func(): show_screen("main"))


func _fill_leaderboard(cats: Array) -> void:
	for c in _lb_list.get_children():
		c.queue_free()
	var tid: String = Game.TRACKS[_lb_track]["id"]
	var cat: String = cats[_lb_cat][0]
	var entries: Array = Game.get_scores(tid, cat)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 22)
	for h in ["#", "Fahrer", "Wert", "Auto", "Datum"]:
		grid.add_child(UiKit.label(h, 16, UiKit.ACCENT.lightened(0.3)))
	if entries.is_empty():
		_lb_list.add_child(UiKit.label("Noch keine Einträge – fahr los!", 18, UiKit.TEXT_DIM))
		return
	for i in entries.size():
		var e: Dictionary = entries[i]
		var val := float(e["value"])
		var val_txt := Game.format_time(val) if cat == "lap" or cat == "race" else Game.format_points(val)
		var col := UiKit.GOLD if i == 0 else UiKit.TEXT
		grid.add_child(UiKit.label("%d." % (i + 1), 18, col))
		grid.add_child(UiKit.label(str(e.get("name", "?")), 18, col))
		grid.add_child(UiKit.label(val_txt, 18, col))
		grid.add_child(UiKit.label(str(Game.get_car(str(e.get("car", "r34")))["name"]).split(" (")[0], 15, UiKit.TEXT_DIM))
		grid.add_child(UiKit.label(str(e.get("date", "")), 15, UiKit.TEXT_DIM))
	_lb_list.add_child(grid)


## Gear ratios and top speed per gear (at the redline) including gearbox tuning.
func _gearing_text(car_id: String) -> String:
	var gb: Dictionary = Game.tuned_gearing(car_id)
	var r: float = float(CarBodyScript.physics_spec(car_id)["wheel_r"])
	var ratios: Array = []
	var speeds: Array = []
	var gears: Array = gb["gears"]
	var fd: float = gb["final"]
	var kmh: bool = bool(Game.settings.get("units_kmh", true))
	for i in gears.size():
		ratios.append("%.2f" % float(gears[i]))
		var v := float(gb["redline"]) / 60.0 * TAU * r / (float(gears[i]) * fd)
		speeds.append("%d" % int(v * (3.6 if kmh else 2.237)))
	return Game.t("Übersetzung  %s  ·  Achse %.2f\nBis Drehzahlgrenze (%d U/min): %s %s") % [" / ".join(ratios), fd, int(gb["redline"]), " / ".join(speeds), "km/h" if kmh else "mph"]


func _update_tuning(car_id: String) -> void:
	if _tuning_box == null or not is_instance_valid(_tuning_box):
		return
	for c in _tuning_box.get_children():
		c.queue_free()
	_tuning_box.add_child(UiKit.label(Game.t("Credits: %s   ·   verdienen durch Driftpunkte und Rennen") % Game.format_points(int(Game.settings["credits"])), 17, UiKit.GOLD))
	var t := Game.get_tuning(car_id)
	for cat in Game.TUNING:
		var cid: String = cat["id"]
		var lvl: int = t[cid]
		var stars := ""
		for k in 3:
			stars += "■" if k < lvl else "□"
		var name_l := UiKit.label(str(cat["name"]), 19)
		name_l.custom_minimum_size = Vector2(110, 0)
		var lvl_l := UiKit.label("%s  %s" % [stars, Game.TUNING_LEVELS[lvl]], 18, UiKit.ACCENT.lightened(0.4))
		lvl_l.custom_minimum_size = Vector2(150, 0)
		var cost := Game.tuning_cost(car_id, cid)
		var buy_text := "Max" if cost < 0 else Game.t("Upgrade (%s)") % Game.format_points(cost)
		var buy := UiKit.button(buy_text, func():
			var err := Game.buy_tuning(car_id, cid)
			if err != "":
				show_status(err, UiKit.BAD)
			else:
				show_status(Game.t("%s verbessert!") % cat["name"], UiKit.GOOD)
				Net.update_local_info()
			_update_tuning(car_id), 200)
		buy.disabled = cost < 0
		var sell := UiKit.button("−", func():
			Game.downgrade_tuning(car_id, cid)
			_update_tuning(car_id), 44)
		sell.disabled = lvl == 0
		sell.tooltip_text = "Stufe zurückbauen (halber Preis zurück)"
		_tuning_box.add_child(UiKit.row([name_l, lvl_l, buy, sell], 10))
		var d := UiKit.label(str(cat["desc"]), 14, UiKit.TEXT_DIM)
		_tuning_box.add_child(d)
		if cid == "gearbox":
			var gl := UiKit.label(_gearing_text(car_id), 14, UiKit.ACCENT.lightened(0.45))
			_tuning_box.add_child(gl)
		elif cid == "steering":
			var lock := float(Game.get_car(car_id)["steer_lock"]) + float(Game.STEER_KIT[lvl])
			_tuning_box.add_child(UiKit.label(Game.t("Lenkeinschlag: %d°") % int(lock), 14, UiKit.ACCENT.lightened(0.45)))
	# Burble-Tune: software map, free to switch
	var bl := Game.get_burble(car_id)
	var b_name := UiKit.label("Burble-Tune", 19)
	b_name.custom_minimum_size = Vector2(110, 0)
	var b_desc := UiKit.label(str(Game.BURBLE_DESC[bl]), 14, UiKit.TEXT_DIM)
	var b_opt := UiKit.option(Game.BURBLE_LEVELS, bl, func(i):
		Game.set_burble(car_id, i)
		b_desc.text = str(Game.BURBLE_DESC[i])
		Net.update_local_info(), 200)
	b_opt.tooltip_text = "Fehlzündungen im Schiebebetrieb (Blubbern, Knallen, Flammen) – kostenlos umstellbar."
	var b_def := UiKit.label(Game.t("Werkseinstellung: %s") % Game.BURBLE_LEVELS[int(Game.get_car(car_id).get("burble", 1))], 14, UiKit.TEXT_DIM)
	_tuning_box.add_child(UiKit.row([b_name, b_opt, b_def], 10))
	_tuning_box.add_child(b_desc)
	# throttle response: free fine tuning of how eagerly the engine revs up with the throttle
	var r_name := UiKit.label("Ansprechverhalten", 19)
	r_name.custom_minimum_size = Vector2(110, 0)
	var r_val := UiKit.label("%d %%" % int(round(Game.get_response(car_id) * 100.0)), 16, UiKit.TEXT_DIM)
	r_val.custom_minimum_size = Vector2(56, 0)
	var r_sl := UiKit.slider(Game.RESPONSE_MIN, 1.0, 0.05, Game.get_response(car_id), func(x):
		r_val.text = "%d %%" % int(round(x * 100.0))
		Game.set_response(car_id, x), 200)
	r_sl.tooltip_text = "Wie spontan der Motor auf Gas hochdreht. 100 % = Serie, weniger = Gaspedal, Drehzahl und\ndurchdrehende Räder bauen sich sanfter auf – leichter zu dosieren. Kostenlos umstellbar."
	_tuning_box.add_child(UiKit.row([r_name, r_sl, r_val], 10))
	_underglow_ui(car_id)


## Underglow: on/off, flasher mode and speed, and per side on/off, colour and "Flasher" (joins the
## mode; otherwise that side stays lit steadily). Free, applied to the car on the turntable at once.
func _underglow_ui(car_id: String) -> void:
	var cfg := Game.get_underglow(car_id)
	var apply := func():
		Game.set_underglow(car_id, cfg)
		main.refresh_showroom(false)
		Net.update_local_info()
	_tuning_box.add_child(UiKit.spacer(4))
	var title := UiKit.label("Underglow", 19)
	title.custom_minimum_size = Vector2(110, 0)
	var on := CheckButton.new()
	on.text = "An"
	on.button_pressed = bool(cfg["on"])
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 4)
	details.visible = on.button_pressed
	on.toggled.connect(func(v):
		cfg["on"] = v
		details.visible = v
		apply.call())
	_tuning_box.add_child(UiKit.row([title, on], 10))
	var mode := UiKit.option(Game.UNDERGLOW_MODES, int(cfg["mode"]), func(i):
		cfg["mode"] = i
		apply.call(), 200)
	mode.tooltip_text = "Flasher: alle eingeschalteten Seiten blinken gemeinsam und synchron in diesem Muster.\n„Tempo“ stellt die Geschwindigkeit ein. [N] halten = Blitzen, egal welcher Modus."
	var speed := UiKit.slider(0.25, 3.0, 0.05, float(cfg["speed"]), func(x):
		cfg["speed"] = x
		apply.call(), 150)
	details.add_child(UiKit.row([UiKit.label("Flasher", 15, UiKit.TEXT_DIM), mode, UiKit.label("Tempo", 15, UiKit.TEXT_DIM), speed], 8))
	var pickers: Array = []
	for sd in Game.UNDERGLOW_SIDES:
		var key: String = sd[0]
		var side: Dictionary = cfg["sides"][key]
		var lbl := UiKit.label(sd[1], 15)
		lbl.custom_minimum_size = Vector2(70, 0)
		var s_on := CheckBox.new()
		s_on.text = "an"
		s_on.button_pressed = bool(side["on"])
		s_on.toggled.connect(func(v):
			side["on"] = v
			apply.call())
		var pick := ColorPickerButton.new()
		pick.custom_minimum_size = Vector2(90, 32)
		pick.edit_alpha = false
		pick.color = Color.from_string(str(side["color"]), Color(0.55, 0.25, 1.0))
		pick.color_changed.connect(func(c):
			side["color"] = "#" + c.to_html(false)
			apply.call())
		pickers.append([pick, side])
		var br := UiKit.slider(0.1, 2.0, 0.05, float(side.get("bright", 1.0)), func(x):
			side["bright"] = x
			apply.call(), 110)
		br.tooltip_text = "Helligkeit dieser Seite"
		details.add_child(UiKit.row([lbl, s_on, pick, UiKit.label("Hell", 14, UiKit.TEXT_DIM), br], 8))
	details.add_child(UiKit.button("Alle Seiten wie vorne", func():
		var front: Dictionary = cfg["sides"]["front"]
		for pk in pickers:
			(pk[1] as Dictionary)["color"] = front["color"]
			(pk[0] as ColorPickerButton).color = Color.from_string(str(front["color"]), Color.WHITE)
		apply.call(), 240))
	_tuning_box.add_child(details)


## AI opponents for races: how many and how good.
func _bot_rows(count: int, lvl: int, set_count: Callable, set_level: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var n_label := UiKit.label(("%d" % count) if count > 0 else "keine", 19)
	n_label.custom_minimum_size = Vector2(60, 0)
	var sl := UiKit.slider(0, 7, 1, float(count), func(v):
		n_label.text = ("%d" % int(v)) if int(v) > 0 else "keine"
		set_count.call(int(v)), 220)
	sl.tooltip_text = "KI-Fahrer im Rennen (offline und online – online steuert der Host sie)."
	box.add_child(UiKit.labeled("KI-Gegner", UiKit.row([sl, n_label])))
	var names: Array = []
	for l in RaceAI.LEVELS:
		names.append(l["name"])
	var opt := UiKit.option(names, clampi(lvl, 0, names.size() - 1), func(i): set_level.call(i))
	opt.tooltip_text = "Leicht: vorsichtig, früh auf der Bremse.  Mittel: solide.\nSchwer: schnell, fährt die Ideallinie.  Profi: am Limit."
	box.add_child(UiKit.labeled("KI-Stärke", opt))
	return box


## Party mode options (minigame coins on the track): on/off, number of minigames, number of coins.
## `src` holds the current values, `set_fn(key, value)` stores a change.
func _party_rows(src: Dictionary, set_fn: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	details.visible = bool(src.get("party", false))
	var on := UiKit.option(["Aus", "An – Minispiel-Münzen auf der Strecke"], 1 if bool(src.get("party", false)) else 0, func(i):
		details.visible = i == 1
		set_fn.call("party", i == 1))
	on.tooltip_text = "Wer durch eine Münze fährt, hält das Rennen für alle an und startet ein Minispiel\n(Rotes Licht Grünes Licht, Offroad-Parkour, König des Hügels, Donut-Duell).\nNicht auf der Grünen Hölle."
	box.add_child(UiKit.labeled("Party-Modus", on))
	var g_label := UiKit.label(str(int(src.get("party_games", 3))), 19)
	g_label.custom_minimum_size = Vector2(40, 0)
	details.add_child(UiKit.labeled("Minispiele", UiKit.row([UiKit.slider(1, 10, 1, float(src.get("party_games", 3)), func(v):
		g_label.text = str(int(v))
		set_fn.call("party_games", int(v)), 220), g_label])))
	var c_label := UiKit.label(str(int(src.get("party_coins", 5))), 19)
	c_label.custom_minimum_size = Vector2(40, 0)
	details.add_child(UiKit.labeled("Münzen", UiKit.row([UiKit.slider(1, 15, 1, float(src.get("party_coins", 5)), func(v):
		c_label.text = str(int(v))
		set_fn.call("party_coins", int(v)), 220), c_label])))
	var spread := UiKit.option(["Nur auf der Strecke", "In der ganzen Stadt"], 1 if bool(src.get("party_coins_city", false)) else 0, func(i):
		set_fn.call("party_coins_city", i == 1))
	spread.tooltip_text = "Neo Tokyo: Münzen nur auf der Rennstrecke (Standard) oder über alle Straßen der Stadt verteilt."
	details.add_child(UiKit.labeled("Münzen (Neo Tokyo)", spread))
	box.add_child(details)
	return box


func _build_controls() -> void:
	_header("STEUERUNG")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for pair in Game.CONTROLS_HELP:
		grid.add_child(UiKit.label(pair[0], 18, UiKit.GOLD))
		grid.add_child(UiKit.label(pair[1], 18))
	_add(grid)
	_add(UiKit.spacer(8))
	_add(UiKit.label("Tipps: Handbremse kurz ziehen und Gas halten leitet Drifts ein. W + S im Stand aktiviert die\nLaunch Control – S loslassen für einen Start mit durchdrehenden Reifen.", 15, UiKit.TEXT_DIM))
	_add(UiKit.spacer(8))
	_float_button("◀  Zurück", func(): show_screen("main"))


# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
func _build_options() -> void:
	_header("OPTIONEN")
	_add(UiKit.label("Kategorie wechseln: RB / LB  ·  E / Q", 15, UiKit.TEXT_DIM))
	_add(SettingsUi.tabs(func(): main.refresh_showroom(true)))
	_add(UiKit.spacer(8))
	_float_button("◀  Zurück", func(): show_screen(_opts_return))
