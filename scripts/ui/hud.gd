extends CanvasLayer
## In-race HUD: lap/time panel, drift combo display, tachometer, minimap, messages, countdown,
## scoreboard (Tab) and the results screen.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Gauge = preload("res://scripts/ui/gauge.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")

var world   # world.gd

var _root: Control
var _info_lines: Label
var _mode_label: Label
var _drift_box: VBoxContainer
var _chain_label: Label
var _mult_label: Label
var _angle_label: Label
var _total_label: Label
var _message: Label
var _sub_message: Label
var _countdown: Label
var _cam_label: Label
var _scoreboard: PanelContainer
var _score_grid: GridContainer
var _results: PanelContainer
var _results_box: VBoxContainer
var _gauge: Control
var _minimap: Control
var _msg_time := 0.0
var _cam_time := 0.0
var _last_cam := ""
var _chain_shown := 0.0
var _score_refresh := 0.0
var _count_time := 0.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	# --- top-left info panel ---
	var info := VBoxContainer.new()
	_mode_label = UiKit.label("", 16, UiKit.ACCENT.lightened(0.3))
	_info_lines = UiKit.label("", 22, Color.WHITE)
	_info_lines.add_theme_constant_override("line_spacing", 2)
	info.add_child(_mode_label)
	info.add_child(_info_lines)
	var info_panel := UiKit.panel(info)
	_anchor(info_panel, 0, 0, 20, 20, 300, 0)
	_root.add_child(info_panel)

	# --- drift display (top centre) ---
	_drift_box = VBoxContainer.new()
	_drift_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_chain_label = UiKit.title("", 58)
	_chain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mult_label = UiKit.label("", 26, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_angle_label = UiKit.label("", 18, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_total_label = UiKit.label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	for l in [_total_label, _chain_label, _mult_label, _angle_label]:
		_drift_box.add_child(l)
	_anchor(_drift_box, 0.5, 0, -300, 18, 600, 200)
	_root.add_child(_drift_box)

	# --- messages ---
	_message = UiKit.title("", 44)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_message, 0.5, 0.3, -500, 0, 1000, 60)
	_root.add_child(_message)
	_sub_message = UiKit.label("", 22, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_sub_message, 0.5, 0.3, -500, 62, 1000, 40)
	_root.add_child(_sub_message)
	_countdown = UiKit.title("", 150)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_countdown, 0.5, 0.42, -300, -80, 600, 180)
	_root.add_child(_countdown)
	_cam_label = UiKit.label("", 18, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_cam_label, 0.5, 1.0, -200, -50, 400, 30)
	_root.add_child(_cam_label)

	# --- gauge (bottom right) ---
	_gauge = Gauge.new()
	_gauge.car = world.local_car
	_anchor(_gauge, 1, 1, -290, -290, 270, 270)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_gauge)

	# --- minimap (top right) ---
	_minimap = Minimap.new()
	_anchor(_minimap, 1, 0, -260, 20, 240, 240)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_minimap)
	_minimap.setup(world)

	# --- scoreboard ---
	_score_grid = GridContainer.new()
	_score_grid.add_theme_constant_override("h_separation", 26)
	_score_grid.add_theme_constant_override("v_separation", 6)
	var sb_box := UiKit.col([UiKit.title("LEADERBOARD", 34), UiKit.sep(), _score_grid])
	_scoreboard = UiKit.panel(sb_box)
	_anchor(_scoreboard, 0.5, 0.2, -420, 0, 840, 0)
	_scoreboard.visible = false
	_root.add_child(_scoreboard)

	# --- results ---
	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 10)
	_results = UiKit.panel(_results_box)
	_results.mouse_filter = Control.MOUSE_FILTER_STOP
	_anchor(_results, 0.5, 0.15, -460, 0, 920, 0)
	_results.visible = false
	_root.add_child(_results)


func _anchor(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


# ---------------------------------------------------------------------------
func show_message(text: String, sub := "", color := Color.WHITE, duration := 2.2) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_sub_message.text = sub
	_msg_time = duration


func set_countdown(text: String, color := Color.WHITE) -> void:
	_countdown.text = text
	_countdown.add_theme_color_override("font_color", color)
	_count_time = 1.0 if text != "" else 0.0


func on_drift_event(ev: Array) -> void:
	match str(ev[0]):
		"bank":
			var pts: float = ev[1]
			if pts > 150.0:
				var grade := "DRIFT!"
				if pts > 20000.0:
					grade = "LEGENDÄR!"
				elif pts > 8000.0:
					grade = "GIGANTISCH!"
				elif pts > 3000.0:
					grade = "SAUBER!"
				show_message("+%s  %s" % [Game.format_points(pts), grade], "", UiKit.GOOD, 1.8)
		"fail":
			var lost: float = ev[1]
			var reason := str(ev[2]) if ev.size() > 2 else "Wand"
			show_message("COMBO VERLOREN", "%s – %s Punkte weg" % [reason, Game.format_points(lost)], UiKit.BAD, 1.8)
		"transition":
			_mult_label.add_theme_color_override("font_color", Color(0.5, 1.0, 1.0))


func _process(delta: float) -> void:
	if world == null or world.local_car == null:
		return
	_scoreboard.visible = Input.is_action_pressed("scoreboard") and not _results.visible
	if _scoreboard.visible:
		_score_refresh -= delta
		if _score_refresh <= 0.0:
			_score_refresh = 0.4
			_fill_scoreboard()

	# info panel
	_mode_label.text = "%s · %s" % [Game.mode_name(world.mode).to_upper(), Game.track_name(world.track.track_id)]
	var lines: Array = []
	if world.mode == "free":
		lines.append("Runde %d" % (int(world.lap) + 1))
	else:
		lines.append("Runde %d / %d" % [mini(int(world.lap) + 1, int(world.laps_total)), int(world.laps_total)])
	if world.mode == "race" and world.state != "countdown":
		lines.append("Gesamt  %s" % Game.format_time(float(world.race_time)))
	lines.append("Zeit     %s" % (Game.format_time(float(world.race_time) - float(world.lap_start)) if world.crossed_start else "-- Einführungsrunde --"))
	lines.append("Letzte  %s" % Game.format_time(float(world.last_lap)))
	lines.append("Beste   %s" % Game.format_time(float(world.best_lap)))
	var pos_text: String = world.position_text()
	if pos_text != "":
		lines.append("Platz   %s" % pos_text)
	_info_lines.text = "\n".join(lines)

	# drift
	var sc = world.scorer
	_total_label.text = "DRIFT  %s" % Game.format_points(float(sc.total))
	var chain: float = sc.chain
	_chain_shown = lerpf(_chain_shown, chain, 1.0 - exp(-delta * 12.0)) if chain > 0.0 else 0.0
	if chain > 0.0:
		_chain_label.text = Game.format_points(_chain_shown)
		var m: float = sc.effective_multiplier()
		_mult_label.text = "x%.1f%s" % [m, "   WAND-BONUS" if sc.near_wall else ""]
		_angle_label.text = "%d°" % int(float(sc.angle))
		var pulse := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.02) * clampf(m - 1.0, 0.0, 1.0)
		_chain_label.scale = Vector2(pulse, pulse)
		_chain_label.pivot_offset = _chain_label.size * 0.5
		_chain_label.add_theme_color_override("font_color", Color.WHITE.lerp(UiKit.GOLD, clampf((m - 1.0) / 4.0, 0.0, 1.0)))
	else:
		_chain_label.text = ""
		_mult_label.text = ""
		_angle_label.text = ""
		_mult_label.add_theme_color_override("font_color", UiKit.GOLD)

	# message fade
	if _msg_time > 0.0:
		_msg_time -= delta
		var a := clampf(_msg_time / 0.4, 0.0, 1.0)
		_message.modulate.a = a
		_sub_message.modulate.a = a
	else:
		_message.text = ""
		_sub_message.text = ""
	if _count_time > 0.0:
		_count_time -= delta
		_countdown.modulate.a = clampf(_count_time * 2.0, 0.0, 1.0)
		var s := 1.0 + (1.0 - _count_time) * 0.3
		_countdown.scale = Vector2(s, s)
		_countdown.pivot_offset = _countdown.size * 0.5
	# camera mode flash
	var cam_name: String = world.camera.mode_name()
	if cam_name != _last_cam:
		_last_cam = cam_name
		_cam_time = 1.6
	if _cam_time > 0.0:
		_cam_time -= delta
		_cam_label.text = "Kamera: " + cam_name
		_cam_label.modulate.a = clampf(_cam_time, 0.0, 1.0)
	else:
		_cam_label.text = ""


func _fill_scoreboard() -> void:
	for c in _score_grid.get_children():
		c.queue_free()
	var data: Dictionary = world.scoreboard_data()
	var header: Array = data["header"]
	var rows: Array = data["rows"]
	_score_grid.columns = header.size()
	for h in header:
		_score_grid.add_child(UiKit.label(str(h), 16, UiKit.ACCENT.lightened(0.3)))
	for r in rows:
		var highlight: bool = r.size() > header.size() and bool(r[header.size()])
		for k in header.size():
			_score_grid.add_child(UiKit.label(str(r[k]), 19, UiKit.GOLD if highlight else UiKit.TEXT))


## buttons: Array of [text, Callable]
func show_results(title_text: String, header: Array, rows: Array, notes: Array, buttons: Array) -> void:
	for c in _results_box.get_children():
		c.queue_free()
	_results_box.add_child(UiKit.title(title_text, 42))
	_results_box.add_child(UiKit.sep())
	var grid := GridContainer.new()
	grid.columns = header.size()
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	for h in header:
		grid.add_child(UiKit.label(str(h), 16, UiKit.ACCENT.lightened(0.3)))
	for r in rows:
		var highlight: bool = r.size() > header.size() and bool(r[header.size()])
		for k in header.size():
			grid.add_child(UiKit.label(str(r[k]), 20, UiKit.GOLD if highlight else UiKit.TEXT))
	_results_box.add_child(grid)
	if not notes.is_empty():
		_results_box.add_child(UiKit.sep())
		for n in notes:
			_results_box.add_child(UiKit.label(str(n), 18, UiKit.GOOD))
	_results_box.add_child(UiKit.spacer(8))
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	for b in buttons:
		brow.add_child(UiKit.button(str(b[0]), b[1], 220))
	_results_box.add_child(brow)
	_results.visible = true
	_drift_box.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if brow.get_child_count() > 0:
		(brow.get_child(0) as Button).grab_focus.call_deferred()


func hide_results() -> void:
	_results.visible = false
	_drift_box.visible = true


func results_visible() -> bool:
	return _results.visible
