extends CanvasLayer
## In-race HUD: lap/time panel, drift combo display, tachometer, minimap, messages, countdown,
## scoreboard (Tab) and the results screen.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Gauge = preload("res://scripts/ui/gauge.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const IsoArrow = preload("res://scripts/ui/iso_arrow.gd")
const IsoCompass = preload("res://scripts/ui/iso_compass.gd")
const RadioWidget = preload("res://scripts/ui/radio_widget.gd")
const MISSION_COL := Color(0.3, 0.95, 0.9)
const NAV_ORANGE := Color(1.0, 0.55, 0.1)
const NAV_RED := Color(1.0, 0.12, 0.08)
## The arrow only comes up once its reason (a bend, the wrong way, off the road) has lasted this long.
const NAV_DELAY := 3.0
const WRONG_WAY_DELAY := 10.0

var world   # world.gd

var _root: Control
var _radio: Control         # the car radio, small, bottom left (P)
var _radio_box: Control     # it and its ✕
var _radio_pill: Button     # ♪: brings it back while it is hidden
var _radio_tapes: PopupMenu
var _info_lines: Label
var _mode_label: Label
var _drift_box: VBoxContainer
var _chain_label: Label
var _mult_label: Label
var _angle_label: Label
var _total_label: Label
var _total_caption: Label
var _top_drift_label: Label
var _top_drift_sub: Label
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


var _fps_label: Label
var _nav: Control               # the 3D direction arrow (iso_arrow.gd)
var _nav_caption: Label
var _nav_alpha := 0.0
var _nav_on := false             # the reason for the arrow holds (before the delay)
var _nav_hold := 0.0            # ... for this long
var _forced_nav = null          # [yaw, caption, colour] while something (the tutorial) shows its own way
var _compass: Control           # the mission compass (iso_compass.gd)
var _compass_label: Label
var _compass_alpha := 0.0
var _mission = null             # [target Vector3, name] or null
var _fps_t := 0.0
var _fps_frames := 0
var _fps_worst := 0.0
var _gpu_ms := 0.0
var _cpu_ms := 0.0
var _perf_measuring := false


func _update_fps(delta: float) -> void:
	var fps_on := bool(Game.settings.get("show_fps", false))
	var perf_on := bool(Game.settings.get("show_perf", false))
	_fps_label.visible = fps_on or perf_on
	if perf_on != _perf_measuring:
		# GPU/CPU render timings cost a little themselves: only measured while shown
		_perf_measuring = perf_on
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), perf_on)
	if not _fps_label.visible:
		return
	_fps_frames += 1
	_fps_t += delta
	_fps_worst = maxf(_fps_worst, delta)
	if perf_on:
		var vp := get_viewport().get_viewport_rid()
		_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		# CPU: game scripts + physics steps of this frame + preparing the draw calls
		var steps := maxf(float(Engine.physics_ticks_per_second) * delta, 1.0)
		_cpu_ms += (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * steps) * 1000.0 \
			+ RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	if _fps_t >= 0.5:
		var frame_ms := _fps_t / _fps_frames * 1000.0
		var lines: Array = []
		lines.append("%d FPS  ·  %.1f ms  ·  max %.0f ms" % [roundi(_fps_frames / _fps_t), frame_ms, _fps_worst * 1000.0])
		if perf_on:
			var gpu := _gpu_ms / _fps_frames
			var cpu := _cpu_ms / _fps_frames
			lines.append("GPU %.1f ms  (%d %%)   ·   CPU %.1f ms  (%d %%)" % [gpu, mini(roundi(gpu / frame_ms * 100.0), 100), cpu, mini(roundi(cpu / frame_ms * 100.0), 100)])
			var limit := "GPU-limitiert" if gpu > cpu * 1.15 and gpu > frame_ms * 0.75 else ("CPU-limitiert" if cpu > gpu * 1.15 and cpu > frame_ms * 0.75 else "")
			if limit == "" and gpu < frame_ms * 0.75 and cpu < frame_ms * 0.75:
				limit = "begrenzt durch VSync / FPS-Limit"
			lines.append(limit)
		_fps_label.text = "\n".join(lines)
		_fps_t = 0.0
		_fps_frames = 0
		_fps_worst = 0.0
		_gpu_ms = 0.0
		_cpu_ms = 0.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)
	# FPS counter (options: Grafik → FPS-Anzeige / GPU- und CPU-Last), bottom-right; shows the worst frame of the last
	# half second too, so hitches are visible
	_fps_label = UiKit.label("", 16, Color(0.7, 1.0, 0.7))
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	# bottom right, just above the tachometer
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_anchor(_fps_label, 1, 1, -520, -372, 500, 80)
	_root.add_child(_fps_label)

	# --- top-left info panel ---
	var info := VBoxContainer.new()
	_mode_label = UiKit.label("", 16, UiKit.ACCENT.lightened(0.3))
	_info_lines = UiKit.label("", 22, Color.WHITE)
	_info_lines.add_theme_constant_override("line_spacing", 2)
	info.add_child(_mode_label)
	info.add_child(_info_lines)
	var info_panel := UiKit.panel(info)
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 10)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(left_col, 0, 0, 20, 20, 300, 0)
	_root.add_child(left_col)
	left_col.add_child(info_panel)
	# highest drift of the session (you or another player), below the info panel
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 0)
	var cap := UiKit.label("TOP-DRIFT", 14, UiKit.GOLD)
	_top_drift_label = UiKit.label("–", 24, Color.WHITE)
	_top_drift_label.add_theme_font_override("font", UiKit.title_font())
	_top_drift_sub = UiKit.label("", 14, UiKit.TEXT_DIM)
	top.add_child(cap)
	top.add_child(_top_drift_label)
	top.add_child(_top_drift_sub)
	var top_panel := UiKit.panel(top)
	left_col.add_child(top_panel)

	# --- drift display (top centre) ---
	_drift_box = VBoxContainer.new()
	_drift_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_chain_label = UiKit.title("", 58)
	_chain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mult_label = UiKit.label("", 26, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_angle_label = UiKit.label("", 18, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	# total score: caption + big number on a dark plate so it stays readable on any background
	_total_caption = UiKit.label("DRIFT-SCORE", 17, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_total_label = UiKit.label("0", 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_total_label.add_theme_font_override("font", UiKit.title_font())
	_total_label.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.45))
	_total_label.add_theme_constant_override("outline_size", 6)
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", -4)
	score_box.add_child(_total_caption)
	score_box.add_child(_total_label)
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.07, 0.72)
	sb.border_color = UiKit.ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	plate.add_theme_stylebox_override("panel", sb)
	plate.add_child(score_box)
	var plate_row := CenterContainer.new()
	plate_row.add_child(plate)
	_drift_box.add_child(plate_row)
	for l in [_chain_label, _mult_label, _angle_label]:
		_drift_box.add_child(l)
	_anchor(_drift_box, 0.5, 0, -300, 14, 600, 230)
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

	# --- 3D direction arrow (bends ahead, wrong way, back to the road) ---
	_nav = IsoArrow.new()
	_anchor(_nav, 0.5, 0.29, -80, 0, 160, 112)
	_nav.modulate.a = 0.0
	_nav.visible = false
	_root.add_child(_nav)
	_nav_caption = UiKit.label("", 20, NAV_ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	_nav_caption.add_theme_constant_override("outline_size", 10)
	_nav_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_anchor(_nav_caption, 0.5, 0.29, -250, 106, 500, 32)
	_root.add_child(_nav_caption)
	# --- mission compass (points at the goal whenever there is one) ---
	_compass = IsoCompass.new()
	# (below the tutorial's yellow objective line, 100-150 px from the top)
	_anchor(_compass, 0.5, 0.0, -66, 176, 132, 96)
	_compass.modulate.a = 0.0
	_compass.visible = false
	_root.add_child(_compass)
	_compass_label = UiKit.label("", 16, MISSION_COL, HORIZONTAL_ALIGNMENT_CENTER)
	_compass_label.add_theme_constant_override("outline_size", 8)
	_compass_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_anchor(_compass_label, 0.5, 0.0, -200, 268, 400, 26)
	_root.add_child(_compass_label)

	# --- the car radio, small in the bottom left corner: ✕ (or P) hides it, ♪ (or P) brings it back ---
	_radio_box = Control.new()
	_anchor(_radio_box, 0, 1, 14, -142, 380, 118)
	_root.add_child(_radio_box)
	_radio = RadioWidget.new()
	_radio.floating = false
	_radio.set_anchors_preset(Control.PRESET_FULL_RECT)
	_radio_box.add_child(_radio)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Radio ausblenden (P)"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 14)
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -26
	close.offset_top = -4
	close.offset_right = 2
	close.offset_bottom = 22
	close.pressed.connect(func(): _show_radio(false))
	_radio_box.add_child(close)
	_radio_pill = Button.new()
	_radio_pill.text = "♪"
	_radio_pill.tooltip_text = "Radio einblenden (P)"
	_radio_pill.focus_mode = Control.FOCUS_NONE
	_radio_pill.add_theme_font_size_override("font_size", 20)
	_anchor(_radio_pill, 0, 1, 14, -58, 44, 40)
	_radio_pill.pressed.connect(func(): _show_radio(true))
	_root.add_child(_radio_pill)
	_show_radio(bool(Game.settings.get("radio_hud", true)), false)
	_radio_tapes = PopupMenu.new()
	_radio_tapes.id_pressed.connect(func(i):
		var ids: Array = _radio_tapes.get_meta("ids", [])
		if i >= 0 and i < ids.size():
			_radio.insert(str(ids[i])))
	_root.add_child(_radio_tapes)
	_radio.tape_list_wanted.connect(func():
		_radio_tapes.clear()
		var ids: Array = Radio.owned_tapes()
		for i in ids.size():
			_radio_tapes.add_item(Radio.tape_title(ids[i]), i)
		if ids.is_empty():
			_radio_tapes.add_item("Noch keine Kassetten gefunden", -1)
		_radio_tapes.set_meta("ids", ids)
		_radio_tapes.reset_size()
		_radio_tapes.position = Vector2i(_radio_box.get_global_rect().position - Vector2(0, _radio_tapes.size.y + 6))
		_radio_tapes.popup())

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


## Shows the 3D arrow pointing `yaw` (radians, + = right of the car) with a caption until
## clear_forced_arrow(), whatever the road does (the tutorial's way out of the yard).
func force_arrow(yaw: float, caption := "", color := NAV_ORANGE) -> void:
	_forced_nav = [yaw, caption, color]


func clear_forced_arrow() -> void:
	_forced_nav = null


## The mission goal the compass points at (a tutorial destination, the nearest party coin …).
func set_mission(target: Vector3, title := "") -> void:
	_mission = [target, title]


func clear_mission() -> void:
	_mission = null


## The compass: the goal's bearing relative to the view (which follows the car), its distance.
func _update_compass(delta: float) -> void:
	var want := _mission != null and not _results.visible
	_compass_alpha = move_toward(_compass_alpha, 1.0 if want else 0.0, delta * (4.0 if want else 2.5))
	_compass.visible = _compass_alpha > 0.01
	_compass.modulate.a = _compass_alpha
	_compass_label.visible = _compass.visible
	_compass_label.modulate.a = _compass_alpha
	if not want:
		return
	var car = world.local_car
	var target: Vector3 = _mission[0]
	var p: Vector3 = car.global_position
	var fwd: Vector3 = -car.global_transform.basis.z
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		fwd = -cam.global_transform.basis.z
	var f2 := Vector2(fwd.x, fwd.z)
	var to := Vector2(target.x - p.x, target.z - p.z)
	if f2.length() > 0.01 and to.length() > 0.01:
		_compass.bearing = f2.normalized().angle_to(to.normalized())
	var dist := to.length()
	_compass.near = clampf(1.0 - dist / 60.0, 0.0, 1.0)
	var d_text := ("%d m" % int(dist)) if dist < 1000.0 else ("%.1f km" % (dist / 1000.0))
	var title: String = _mission[1]
	_compass_label.text = ("%s  ·  %s" % [title, d_text]) if title != "" else d_text


## The arrow: where the road goes 40+ m ahead when that's a real bend, the way round when driving
## the wrong way, the way back when off the road – each only after it has held for NAV_DELAY
## seconds (the tutorial's own arrows come up at once). Fades in and out.
func _update_nav(delta: float) -> void:
	var car = world.local_car
	var want := false
	var yaw := 0.0
	var cap := ""
	var col := NAV_ORANGE
	if _forced_nav != null:
		want = true
		yaw = _forced_nav[0]
		cap = _forced_nav[1]
		col = _forced_nav[2]
	elif bool(Game.settings.get("nav_arrow", true)) and world.state == "running" and not _results.visible \
			and (world.party == null or not world.party.active()):
		var tr = world.track
		var p: Vector3 = car.global_position
		var pr: Array = tr.project(p, int(car.track_hint))
		var lateral := absf(float(pr[2]))
		var vel: Vector3 = (car as RigidBody3D).linear_velocity
		var dir: Vector3 = vel if car.speed > 6.0 else -car.global_transform.basis.z
		var f2 := Vector2(dir.x, dir.z).normalized()
		var tan: Vector3 = tr.tangents[int(pr[0])]
		var off_road := lateral > float(tr.half_w) + 8.0
		var ahead: float = 15.0 if off_road else 40.0 + float(car.speed)
		var target: Vector3 = tr.samples[tr.index_at(float(pr[1]) + ahead)]
		var to := Vector2(target.x - p.x, target.z - p.z).normalized()
		yaw = f2.angle_to(to)
		if f2.dot(Vector2(tan.x, tan.z).normalized()) < -0.3 and car.speed > 3.0 and not off_road:
			want = true
			col = NAV_RED
			cap = "FALSCHE RICHTUNG"
		elif off_road:
			want = true
			cap = "ZUR STRECKE"
		else:
			# a real bend coming (a little hysteresis so it doesn't flicker)
			var lim := 0.3 if _nav_on else 0.42
			want = absf(yaw) > lim and car.speed > 2.0
		_nav_on = want
		_nav_hold = _nav_hold + delta if want else 0.0
		# the wrong way only after 10 s of really driving that way (a spin doesn't count)
		want = want and _nav_hold >= (WRONG_WAY_DELAY if col == NAV_RED else NAV_DELAY)
	else:
		_nav_on = false
		_nav_hold = 0.0
	_nav_alpha = move_toward(_nav_alpha, 1.0 if want else 0.0, delta * (5.0 if want else 2.5))
	_nav.visible = _nav_alpha > 0.01
	_nav.modulate.a = _nav_alpha
	if want:
		_nav.yaw = yaw
		_nav.tint = col
		_nav_caption.text = cap
		_nav_caption.add_theme_color_override("font_color", col.lightened(0.15))
	_nav_caption.modulate.a = _nav_alpha
	_nav_caption.visible = _nav.visible and _nav_caption.text != ""


## Highest single drift of the session – yours or another player's (online), or the track record.
func _update_top_drift() -> void:
	var sc = world.scorer
	var mine := maxf(float(sc.best_chain), float(sc.chain))
	var best := mine
	var holder := "Du"
	var live := float(sc.chain) > 0.0 and float(sc.chain) >= float(sc.best_chain)
	if world.online:
		for id in world.cars.keys():
			var c = world.cars[id]
			if not is_instance_valid(c) or c == world.local_car:
				continue
			var v := maxf(float(c.remote_best_chain), float(c.remote_chain))
			if v > best:
				best = v
				holder = str(c.player_name)
				live = float(c.remote_chain) > 0.0 and float(c.remote_chain) >= float(c.remote_best_chain)
		_top_drift_sub.text = "%s%s" % [holder, "  · läuft" if live and best > 0.0 else ""]
	else:
		var rec: Array = Game.get_scores(world.track.track_id, "combo")
		var rec_txt := ""
		if rec.size() > 0:
			rec_txt = Game.t("Rekord %s · %s") % [Game.format_points(float(rec[0]["value"])), rec[0]["name"]]
		_top_drift_sub.text = (Game.t("Du%s") % ("  · läuft" if live and best > 0.0 else "")) + ("\n" + rec_txt if rec_txt != "" else "")
	_top_drift_label.text = Game.format_points(best) if best > 0.0 else "–"
	_top_drift_label.add_theme_color_override("font_color", UiKit.GOLD if live and best > 0.0 else Color.WHITE)


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
			show_message("COMBO VERLOREN", Game.t("%s – %s Punkte weg") % [reason, Game.format_points(lost)], UiKit.BAD, 1.8)
		"transition":
			_mult_label.add_theme_color_override("font_color", Color(0.5, 1.0, 1.0))
		"spin":
			var count := int(ev[2]) if ev.size() > 2 else 1
			show_message("%d°!" % (360 * count), Game.t("+%s  ·  Reifen durchgehend durchgedreht") % Game.format_points(float(ev[1])), UiKit.GOLD, 1.6)
		"reverse":
			show_message("REVERSE ENTRY!", "+%s" % Game.format_points(float(ev[1])), UiKit.GOLD, 1.6)


## Held M: the minimap grows to twice its size towards the bottom left (its top right corner stays).
var _map_zoom := 0.0


func _update_map_zoom(delta: float) -> void:
	var want := 1.0 if Input.is_action_pressed("map_zoom") else 0.0
	_map_zoom = move_toward(_map_zoom, want, delta * 6.0)
	var k := _map_zoom * _map_zoom * (3.0 - 2.0 * _map_zoom)
	var sz := 240.0 * (1.0 + k)
	_minimap.offset_left = -20.0 - sz
	_minimap.offset_right = -20.0
	_minimap.offset_bottom = 20.0 + sz


func _process(delta: float) -> void:
	if _minimap:
		_update_map_zoom(delta)
	_update_fps(delta)
	if world == null or world.local_car == null:
		return
	_update_nav(delta)
	_update_compass(delta)
	_scoreboard.visible = Input.is_action_pressed("scoreboard") and not _results.visible
	if _scoreboard.visible:
		_score_refresh -= delta
		if _score_refresh <= 0.0:
			_score_refresh = 0.4
			_fill_scoreboard()

	# info panel
	_mode_label.text = "%s · %s" % [Game.mode_name(world.mode).to_upper(), Game.track_name(world.track.track_id)]
	var lines: Array = []
	if world.graffiti:
		lines.append(Game.t("Zeit     %s") % Game.format_time(maxf(float(world.time_limit) - float(world.race_time), 0.0)))
		for st in world.graffiti.standings():
			lines.append("%s  %d m  (%d %%)" % [str(world.graffiti.names.get(st[0], "?")).substr(0, 10), int(st[1]), int(round(float(st[2]) * 100.0))])
	elif world.mode == "free":
		lines.append(Game.t("Runde %d") % (int(world.lap) + 1))
	else:
		lines.append(Game.t("Runde %d / %d") % [mini(int(world.lap) + 1, int(world.laps_total)), int(world.laps_total)])
	if world.graffiti:
		pass
	elif world.mode == "race" and world.state != "countdown":
		lines.append(Game.t("Gesamt  %s") % Game.format_time(float(world.race_time)))
	if not world.graffiti:
		lines.append(Game.t("Zeit     %s") % (Game.format_time(float(world.race_time) - float(world.lap_start)) if world.crossed_start else "-- Einführungsrunde --"))
		lines.append(Game.t("Letzte  %s") % Game.format_time(float(world.last_lap)))
		lines.append(Game.t("Beste   %s") % Game.format_time(float(world.best_lap)))
	var pos_text: String = world.position_text()
	if pos_text != "":
		lines.append(Game.t("Platz   %s") % pos_text)
	var section: String = world.track.section_at(float(world.progress))
	if section != "":
		lines.append("» %s" % section)
	_info_lines.text = "\n".join(lines)

	# drift
	var sc = world.scorer
	_total_label.text = Game.format_points(float(sc.total))
	_update_top_drift()
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
		_cam_label.text = Game.t("Kamera: ") + cam_name
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


func _show_radio(on: bool, click := true) -> void:
	_radio_box.visible = on
	_radio_pill.visible = not on
	if click:
		Radio.click_sound()
	if bool(Game.settings.get("radio_hud", true)) != on:
		Game.settings["radio_hud"] = on
		Game.save_settings()


## P: the radio in / out of view; while it shows: 1-6 the presets, + / - the volume, 0 on / off.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("radio"):
		_show_radio(not _radio_box.visible)
		get_viewport().set_input_as_handled()
		return
	if not _radio_box.visible or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var k := (event as InputEventKey).physical_keycode
	if k >= KEY_1 and k <= KEY_6:
		Radio.click_sound()
		Radio.pick_preset(k - KEY_1)
	elif k == KEY_0:
		Radio.click_sound()
		Radio.toggle_power()
	elif k == KEY_EQUAL or k == KEY_KP_ADD or k == KEY_PAGEUP:
		Radio.set_volume(Radio.volume + 1.0 / 30.0)
	elif k == KEY_MINUS or k == KEY_KP_SUBTRACT or k == KEY_PAGEDOWN:
		Radio.set_volume(Radio.volume - 1.0 / 30.0)
	else:
		return
	get_viewport().set_input_as_handled()
