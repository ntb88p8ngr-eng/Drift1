extends CanvasLayer
## In-game admin panel (F10, admin mode on): a free camera with adjustable speed, the game speed,
## live tuning of every bot (personality and each parameter), and the bots' best laps of this
## session – one can be set as the default lap all bots drive on this track.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const FreeCam = preload("res://scripts/util/free_cam.gd")
const BotProfiles = preload("res://scripts/admin/bot_profiles.gd")
const AdminUi = preload("res://scripts/admin/admin_ui.gd")

var world
var cam: Camera3D
var _prev_cam: Camera3D
var _panel: Control
var _bots_box: VBoxContainer
var _laps_box: VBoxContainer
var _bot_i := 0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = FreeCam.new()
	cam.far = 8000.0
	cam.active = false
	add_child(cam)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(420, 660)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(v)
	_panel = UiKit.panel(sc)
	_panel.position = Vector2(14, 14)
	root.add_child(_panel)
	_panel.visible = false
	v.add_child(UiKit.label("ADMIN  (F10)", 22, UiKit.GOLD))
	var fc := CheckBox.new()
	fc.text = "Freie Kamera (WASD, Q/E, rechte Maustaste)"
	fc.toggled.connect(_set_freecam)
	v.add_child(fc)
	var sp_l := UiKit.label("Kamera-Tempo: %d m/s" % int(cam.speed), 15)
	v.add_child(sp_l)
	v.add_child(UiKit.slider(1, 300, 1, cam.speed, func(x):
		cam.speed = x
		sp_l.text = "Kamera-Tempo: %d m/s" % int(x), 380))
	var sm_l := UiKit.label("Kamera-Weichheit", 15)
	v.add_child(sm_l)
	v.add_child(UiKit.slider(0, 0.95, 0.01, cam.smoothing, func(x): cam.smoothing = x, 380))
	var ts_l := UiKit.label("Spieltempo: 1.0", 15)
	v.add_child(ts_l)
	v.add_child(UiKit.slider(0.05, 2.0, 0.05, 1.0, func(x):
		Engine.time_scale = x
		ts_l.text = "Spieltempo: %.2f" % x, 380))
	v.add_child(UiKit.button("Auto zur Kamera holen", func():
		if world.local_car and cam.current:
			var f := -cam.global_transform.basis.z
			f.y = 0.0
			world.local_car.place(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), cam.global_position)), 380))
	v.add_child(UiKit.sep())
	v.add_child(UiKit.label("BOTS", 19, UiKit.GOLD))
	_bots_box = VBoxContainer.new()
	v.add_child(_bots_box)
	v.add_child(UiKit.sep())
	v.add_child(UiKit.label("BESTRUNDEN DER BOTS", 19, UiKit.GOLD))
	_laps_box = VBoxContainer.new()
	v.add_child(_laps_box)
	v.add_child(UiKit.button("Aktualisieren", _refresh, 200))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F10:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


func _set_freecam(on: bool) -> void:
	if on:
		_prev_cam = get_viewport().get_camera_3d()
		cam.start_from(_prev_cam.global_transform if _prev_cam else Transform3D.IDENTITY)
		cam.active = true
		cam.make_current()
		if world.local_car:
			world.local_car.controls_locked = true
	else:
		cam.active = false
		if _prev_cam and is_instance_valid(_prev_cam):
			_prev_cam.make_current()
		if world.local_car and world.state == "running":
			world.local_car.controls_locked = false


func _refresh() -> void:
	for c in _bots_box.get_children():
		c.queue_free()
	for c in _laps_box.get_children():
		c.queue_free()
	var ai = world.race_ai
	if ai == null or ai.bots.is_empty():
		_bots_box.add_child(UiKit.label("Keine Bots in diesem Rennen.", 14, UiKit.TEXT_DIM))
		return
	var bot_names: Array = []
	for b in ai.bots:
		bot_names.append("%s (%s)" % [b["car"].player_name, b.get("personality", "")])
	_bot_i = clampi(_bot_i, 0, ai.bots.size() - 1)
	_bots_box.add_child(UiKit.option(bot_names, _bot_i, func(i):
		_bot_i = i
		_refresh(), 380))
	var b: Dictionary = ai.bots[_bot_i]
	var pers := BotProfiles.all_names()
	_bots_box.add_child(UiKit.labeled("Persönlichkeit", UiKit.option(pers, maxi(pers.find(str(b.get("personality", ""))), 0), func(i):
		ai.set_personality(b, str(pers[i]))
		_refresh(), 220), 130))
	_bots_box.add_child(AdminUi.param_editor(b["p"], func(p):
		ai.set_personality(b, str(b.get("personality", "")), p)))
	_bots_box.add_child(UiKit.button("Als Persönlichkeit speichern …", func():
		var nm := "%s (angepasst)" % str(b.get("personality", "Bot"))
		BotProfiles.save_profile(nm, (b["p"] as Dictionary).duplicate())
		world.hud.show_message("GESPEICHERT", nm, UiKit.GOOD, 2.0), 380))
	if ai.best_laps.is_empty():
		_laps_box.add_child(UiKit.label("Noch keine volle Bot-Runde gefahren.", 14, UiKit.TEXT_DIM))
	for lap in ai.best_laps:
		var l: Dictionary = lap
		_laps_box.add_child(UiKit.row([UiKit.label("%s  %s  %s" % [Game.format_time(float(l["time"])), l["name"], Game.get_car(str(l["car"]))["name"]], 14),
			UiKit.button("Als Standard", func():
				BotProfiles.save_line(str(world.track.track_id), l)
				ai.default_line = l
				world.hud.show_message("STANDARD-RUNDE", "Alle Bots fahren jetzt diese Runde (%s)" % Game.format_time(float(l["time"])), UiKit.GOOD, 3.0), 150)]))


func _exit_tree() -> void:
	Engine.time_scale = 1.0
