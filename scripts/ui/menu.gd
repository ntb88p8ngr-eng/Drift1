extends CanvasLayer
## Main menu: single player setup, garage, online (host / join / LAN browser), lobby, leaderboard, options.
## The 3D showroom behind the menu shows the selected car.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

var main   # main.gd
var current := ""
var _root: Control
var _panel: PanelContainer
var _content: VBoxContainer
var _status: Label
var _chat_lines: Array = []
var _return_to := "main"

# lobby widgets
var _lobby_players: VBoxContainer
var _lobby_settings: VBoxContainer
var _lobby_info: Label
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _ready_btn: Button
var _start_btn: Button
var _lan_list: VBoxContainer
var _color_picker: ColorPickerButton
var _car_desc: Label
var _car_stats: VBoxContainer
var _tuning_box: VBoxContainer
var _lb_track := 0
var _lb_cat := 0
var _lb_list: VBoxContainer


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# gradient shade on the left so the menu stays readable over the showroom
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.0, 0.03, 0.9))
	grad.set_color(1, Color(0.01, 0.0, 0.03, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.62
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var margin := MarginContainer.new()
	margin.anchor_bottom = 1.0
	margin.anchor_right = 0.0
	margin.offset_right = 760
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	_root.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	var t := UiKit.title("MIDNIGHT DRIFT", 64)
	outer.add_child(t)
	outer.add_child(UiKit.label("v%s  ·  Drift-Racing mit Online-Lobbys" % Game.VERSION, 16, UiKit.TEXT_DIM))
	outer.add_child(UiKit.spacer(10))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_status = UiKit.label("", 17, UiKit.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(640, 0)
	outer.add_child(_status)

	Net.lobby_changed.connect(_on_lobby_changed)
	Net.chat_received.connect(_on_chat)
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(func(reason): show_status(reason, UiKit.BAD))
	Net.lan_lobbies_changed.connect(_refresh_lan)
	Net.upnp_finished.connect(func(_ok, _msg): _on_lobby_changed())


func show_status(text: String, color := UiKit.GOLD) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func show_screen(screen: String) -> void:
	if current == "online" and screen != "online":
		Net.stop_lan_scan()
	current = screen
	_clear()
	show_status("")
	match screen:
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
		_:
			current = "main"
			_build_main()
	# focus first button for gamepad users
	_focus_first.call_deferred()


func _focus_first() -> void:
	for c in _content.get_children():
		if c is Button and (c as Button).is_inside_tree() and (c as Button).is_visible_in_tree():
			(c as Button).grab_focus()
			return


func _add(c: Control) -> void:
	_content.add_child(c)


func _header(text: String) -> void:
	_add(UiKit.title(text, 34))
	_add(UiKit.sep())


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
func _build_main() -> void:
	_add(UiKit.button("Einzelspieler", func(): show_screen("single"), 360))
	_add(UiKit.button("Online-Modus", func(): show_screen("online"), 360))
	_add(UiKit.button("Garage", func():
		_return_to = "main"
		show_screen("garage"), 360))
	_add(UiKit.button("Leaderboard", func(): show_screen("leaderboard"), 360))
	_add(UiKit.button("Steuerung", func(): show_screen("controls"), 360))
	_add(UiKit.button("Optionen", func(): show_screen("options"), 360))
	_add(UiKit.button("Beenden", func(): get_tree().quit(), 360))
	_add(UiKit.spacer(18))
	var car: Dictionary = Game.get_car(Game.settings["car"])
	var paint: Dictionary = Game.get_paint(Game.settings["paint"], Game.settings["custom_color"])
	_add(UiKit.label("Fahrer: %s" % Game.settings["player_name"], 18, UiKit.TEXT))
	_add(UiKit.label("Auto: %s – %s" % [car["name"], paint["name"]], 18, UiKit.TEXT_DIM))
	_add(UiKit.label("Credits: %s" % Game.format_points(int(Game.settings["credits"])), 18, UiKit.GOLD))


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
	var update_desc := func():
		var t: Dictionary = Game.TRACKS[track_names.find(Game.track_name(Game.settings["track"]))]
		var m_desc := ""
		for m in Game.MODES:
			if m["id"] == Game.settings["mode"]:
				m_desc = m["desc"]
		desc.text = "%s\n%s" % [t["desc"], m_desc]
	_add(UiKit.labeled("Strecke", UiKit.option(track_names, track_idx, func(i):
		Game.set_setting("track", Game.TRACKS[i]["id"])
		update_desc.call())))
	_add(UiKit.labeled("Modus", UiKit.option(mode_names, mode_idx, func(i):
		Game.set_setting("mode", Game.MODES[i]["id"])
		update_desc.call())))
	var laps_label := UiKit.label("%d" % int(Game.settings["laps"]), 19)
	laps_label.custom_minimum_size = Vector2(40, 0)
	var laps_slider := UiKit.slider(1, 20, 1, float(Game.settings["laps"]), func(v):
		Game.set_setting("laps", int(v))
		laps_label.text = "%d" % int(v), 220)
	_add(UiKit.labeled("Runden", UiKit.row([laps_slider, laps_label])))
	_add(UiKit.labeled("Tageszeit", UiKit.option(tod_names, tod_idx, func(i):
		Game.set_setting("time_of_day", Game.TIMES_OF_DAY[i]["id"]))))
	_add(UiKit.labeled("Getriebe", UiKit.option(["Automatik", "Manuell"], 0 if Game.settings["transmission"] == "auto" else 1, func(i):
		Game.set_setting("transmission", "auto" if i == 0 else "manual"))))
	_add(desc)
	update_desc.call()
	_add(UiKit.spacer(8))
	_add(UiKit.button("▶  START", func(): main.start_offline(), 360))
	_add(UiKit.button("Garage", func():
		_return_to = "single"
		show_screen("garage"), 360))
	_add(UiKit.button("Zurück", func(): show_screen("main"), 360))


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
	var car_names: Array = []
	var car_idx := 0
	for i in Game.CAR_ORDER.size():
		car_names.append(Game.CARS[Game.CAR_ORDER[i]]["name"])
		if Game.CAR_ORDER[i] == Game.settings["car"]:
			car_idx = i
	_add(UiKit.labeled("Auto", UiKit.option(car_names, car_idx, func(i):
		Game.set_setting("car", Game.CAR_ORDER[i])
		_update_car_info()
		main.refresh_showroom(true))))
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
	_add(UiKit.button("Fertig", func():
		Net.update_local_info()
		show_screen(_return_to), 360))


func _update_car_info() -> void:
	var car_id: String = Game.settings["car"]
	var car: Dictionary = Game.get_car(car_id)
	_car_desc.text = str(car["desc"])
	for c in _car_stats.get_children():
		c.queue_free()
	_update_tuning(car_id)
	var kw := float(car["torque"]) * float(car["redline"]) * 0.62 / 9549.0
	var stats := [
		["Leistung", clampf(kw / 330.0, 0.1, 1.0), "%d PS" % int(kw * 1.36)],
		["Gewicht", clampf(1.0 - (float(car["mass"]) - 900.0) / 800.0, 0.1, 1.0), "%d kg" % int(car["mass"])],
		["Grip", clampf((float(car["grip"]) - 0.9) / 0.25, 0.1, 1.0), ""],
		["Turbo", clampf(float(car["turbo"]) / 0.6, 0.0, 1.0), "Sauger" if float(car["turbo"]) <= 0.0 else "Twin-Turbo"],
		["Antrieb", float(car["rear_split"]), "%d %% hinten" % int(float(car["rear_split"]) * 100.0)],
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
	var name_edit := LineEdit.new()
	name_edit.text = Game.settings["player_name"]
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(300, 42)
	name_edit.text_changed.connect(func(t): Game.set_setting("player_name", t.strip_edges() if t.strip_edges() != "" else "Driver"))
	_add(UiKit.labeled("Fahrername", name_edit))

	_add(UiKit.label("Lobby erstellen (du bist der Host / Server)", 22, UiKit.ACCENT.lightened(0.3)))
	var lobby_name := LineEdit.new()
	lobby_name.placeholder_text = "%s's Lobby" % Game.settings["player_name"]
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
	var upnp := CheckBox.new()
	upnp.text = "Port automatisch per UPnP öffnen"
	upnp.button_pressed = bool(Game.settings["use_upnp"])
	upnp.toggled.connect(func(on): Game.set_setting("use_upnp", on))
	_add(upnp)
	_add(UiKit.button("Lobby erstellen", func():
		var port := int(port_edit.text) if port_edit.text.is_valid_int() else Net.DEFAULT_PORT
		Game.settings["port"] = port
		Game.set_setting("lobby_name", lobby_name.text)
		var err := Net.host_lobby(lobby_name.text, port, int(Game.settings["max_players"]), bool(Game.settings["use_upnp"]))
		if err != "":
			show_status(err, UiKit.BAD)
		else:
			_chat_lines.clear()
			show_screen("lobby"), 360))

	_add(UiKit.spacer(10))
	_add(UiKit.label("Lobby beitreten", 22, UiKit.ACCENT.lightened(0.3)))
	var ip_edit := LineEdit.new()
	ip_edit.text = str(Game.settings["last_ip"])
	ip_edit.placeholder_text = "IP-Adresse des Hosts"
	ip_edit.custom_minimum_size = Vector2(300, 42)
	var jport := LineEdit.new()
	jport.text = str(int(Game.settings["port"]))
	jport.custom_minimum_size = Vector2(110, 42)
	_add(UiKit.labeled("Adresse : Port", UiKit.row([ip_edit, jport])))
	_add(UiKit.button("Beitreten", func():
		var port := int(jport.text) if jport.text.is_valid_int() else Net.DEFAULT_PORT
		Game.set_setting("last_ip", ip_edit.text.strip_edges())
		_join(ip_edit.text, port), 360))

	_add(UiKit.spacer(10))
	_add(UiKit.label("Lobbys im lokalen Netzwerk", 22, UiKit.ACCENT.lightened(0.3)))
	_lan_list = VBoxContainer.new()
	_add(_lan_list)
	Net.start_lan_scan()
	_refresh_lan()
	_add(UiKit.spacer(8))
	_add(UiKit.button("Zurück", func(): show_screen("main"), 360))


func _join(ip: String, port: int) -> void:
	var err := Net.join_lobby(ip, port)
	if err != "":
		show_status(err, UiKit.BAD)
	else:
		show_status("Verbinde mit %s:%d …" % [ip.strip_edges(), port])


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
		var text := "%s  –  %s  –  %d/%d Spieler%s" % [info.get("name", "Lobby"), Game.track_name(str(info.get("track", ""))),
			int(info.get("players", 0)), int(info.get("max", 8)), "  (Rennen läuft)" if info.get("in_race", false) else ""]
		var ip: String = info.get("ip", "")
		var port := int(info.get("port", Net.DEFAULT_PORT))
		_lan_list.add_child(UiKit.button(text, func(): _join(ip, port), 600))


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
	buttons.add_child(UiKit.button("Verlassen", func():
		Net.leave()
		show_screen("online"), 140))
	_add(buttons)
	_refresh_lobby()


func _refresh_lobby() -> void:
	if current != "lobby" or _lobby_players == null or not is_instance_valid(_lobby_players):
		return
	if not Net.is_online:
		show_screen("online")
		return
	var host := Net.is_host()
	var info_lines: Array = []
	info_lines.append("Lobby: %s" % Net.lobby.get("name", "…"))
	if host:
		var ips := Net.get_local_addresses()
		info_lines.append("Du hostest diese Lobby. Mitspieler verbinden sich mit deiner IP und Port %d:" % int(Net.lobby.get("port", Net.DEFAULT_PORT)))
		info_lines.append("LAN: %s" % (", ".join(ips) if not ips.is_empty() else "unbekannt"))
		if Net.upnp_message != "":
			info_lines.append(Net.upnp_message)
	else:
		info_lines.append("Verbunden – warte darauf, dass der Host das Rennen startet.")
	_lobby_info.text = "\n".join(info_lines)

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
		var race_modes := [Game.MODES[1], Game.MODES[2]]
		for i in race_modes.size():
			modes.append(race_modes[i]["name"])
			if race_modes[i]["id"] == lobby.get("mode", "race"):
				mi = i
		_lobby_settings.add_child(UiKit.labeled("Modus", UiKit.option(modes, mi, func(i): Net.host_set_option("mode", race_modes[i]["id"]))))
		var laps_label := UiKit.label(str(int(lobby.get("laps", 3))), 19)
		_lobby_settings.add_child(UiKit.labeled("Runden", UiKit.row([UiKit.slider(1, 20, 1, float(lobby.get("laps", 3)), func(v):
			laps_label.text = str(int(v))
			if int(v) != int(Net.lobby.get("laps", 3)):
				Net.host_set_option("laps", int(v)), 200), laps_label])))
		var tods: Array = []
		var tdi := 0
		for i in Game.TIMES_OF_DAY.size():
			tods.append(Game.TIMES_OF_DAY[i]["name"])
			if Game.TIMES_OF_DAY[i]["id"] == lobby.get("time_of_day", "dusk"):
				tdi = i
		_lobby_settings.add_child(UiKit.labeled("Tageszeit", UiKit.option(tods, tdi, func(i): Net.host_set_option("time_of_day", Game.TIMES_OF_DAY[i]["id"]))))
		var coll := CheckBox.new()
		coll.text = "Kollisionen zwischen Autos"
		coll.button_pressed = bool(lobby.get("collisions", true))
		coll.toggled.connect(func(on): Net.host_set_option("collisions", on))
		_lobby_settings.add_child(coll)
	else:
		_lobby_settings.add_child(UiKit.label("Strecke: %s" % Game.track_name(str(lobby.get("track", "ridge"))), 18))
		_lobby_settings.add_child(UiKit.label("Modus: %s  ·  Runden: %d" % [Game.mode_name(str(lobby.get("mode", "race"))), int(lobby.get("laps", 3))], 18))
		_lobby_settings.add_child(UiKit.label("Tageszeit: %s  ·  Kollisionen: %s" % [Game.time_name(str(lobby.get("time_of_day", "dusk"))), "an" if lobby.get("collisions", true) else "aus"], 18))
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
	_add(UiKit.button("Zurück", func(): show_screen("main"), 360))


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


func _update_tuning(car_id: String) -> void:
	if _tuning_box == null or not is_instance_valid(_tuning_box):
		return
	for c in _tuning_box.get_children():
		c.queue_free()
	_tuning_box.add_child(UiKit.label("Credits: %s   ·   verdienen durch Driftpunkte und Rennen" % Game.format_points(int(Game.settings["credits"])), 17, UiKit.GOLD))
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
		var buy_text := "Max" if cost < 0 else "Upgrade (%s)" % Game.format_points(cost)
		var buy := UiKit.button(buy_text, func():
			var err := Game.buy_tuning(car_id, cid)
			if err != "":
				show_status(err, UiKit.BAD)
			else:
				show_status("%s verbessert!" % cat["name"], UiKit.GOOD)
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
	_add(UiKit.button("Zurück", func(): show_screen("main"), 360))


# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
func _build_options() -> void:
	_header("OPTIONEN")
	_add(UiKit.labeled("Gesamtlautstärke", UiKit.slider(0, 1, 0.05, float(Game.settings["master_volume"]), func(v): Game.set_setting("master_volume", v))))
	_add(UiKit.labeled("Motorsound", UiKit.slider(0, 1.5, 0.05, float(Game.settings["engine_volume"]), func(v): Game.set_setting("engine_volume", v))))
	_add(UiKit.labeled("Grafikqualität", UiKit.option(["Niedrig", "Mittel", "Hoch", "Ultra"], int(Game.settings["quality"]), func(i):
		Game.set_setting("quality", i)
		main.refresh_showroom(true))))
	var fs := CheckBox.new()
	fs.text = "Vollbild"
	fs.button_pressed = bool(Game.settings["fullscreen"])
	fs.toggled.connect(func(on): Game.set_setting("fullscreen", on))
	_add(fs)
	_add(UiKit.labeled("Sichtfeld (FOV)", UiKit.slider(60, 100, 1, float(Game.settings["fov"]), func(v): Game.set_setting("fov", v))))
	_add(UiKit.labeled("Maus-Empfindlichkeit", UiKit.slider(0.05, 1.0, 0.05, float(Game.settings["mouse_sensitivity"]), func(v): Game.set_setting("mouse_sensitivity", v))))
	_add(UiKit.labeled("Konter-Lenkhilfe", UiKit.slider(0, 1, 0.05, float(Game.settings["steer_assist"]), func(v): Game.set_setting("steer_assist", v))))
	_add(UiKit.labeled("Einheit", UiKit.option(["km/h", "mph"], 0 if Game.settings["units_kmh"] else 1, func(i): Game.set_setting("units_kmh", i == 0))))
	_add(UiKit.spacer(8))
	_add(UiKit.button("Zurück", func(): show_screen("main"), 360))
