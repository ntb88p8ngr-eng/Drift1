extends Node
## Plays a replay back in a rebuilt world: the cars are driven by the recorded samples (interpolated),
## the time can be paused, scrubbed and slowed down, and it is filmed with the original camera or a
## new one – chase, orbit, TV cameras along the track or a free camera, each with its own settings.

const Replay = preload("res://scripts/replay/replay.gd")
const FreeCam = preload("res://scripts/util/free_cam.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const CAM_MODES := [["original", "Original"], ["chase", "Verfolger"], ["orbit", "Orbit"], ["tv", "TV-Kameras"], ["free", "Frei"]]
const SPEEDS := [0.1, 0.25, 0.5, 1.0, 2.0, 4.0]

var world
var header := {}
var data := PackedFloat32Array()
var stride := 1
var n_cars := 0
var frames := 0
var duration := 0.0
var t := 0.0
var playing := true
var speed := 1.0
var cam_mode := "original"
var target := 0                 # the car the cameras look at
var cars: Array = []            # Car per recorded car

# camera settings
var fov := 70.0
var cam_dist := 6.0
var cam_height := 1.8
var smoothing := 0.6
var orbit_speed := 0.25
var dof := false

var cam: Camera3D
var free_cam: Camera3D
var _cam_xf := Transform3D.IDENTITY
var _orbit := 0.0
var _tv_spots: Array = []
var _tv_i := -1

var ui: CanvasLayer
var _bar: Control
var _settings: Control
var _time_l: Label
var _slider: HSlider
var _play_b: Button
var _scrubbing := false


func setup(p_world, h: Dictionary, d: PackedFloat32Array) -> void:
	world = p_world
	header = h
	data = d
	n_cars = (h.get("cars", []) as Array).size()
	stride = 1 + Replay.CAM_FLOATS + n_cars * Replay.CAR_FLOATS
	frames = data.size() / stride
	duration = data[(frames - 1) * stride] if frames > 0 else 0.0
	target = int(h.get("local", 0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -20
	for id in range(n_cars):
		var c = world.cars.get(id)
		cars.append(c)
		if c:
			c.replay_driven = true
	cam = Camera3D.new()
	cam.far = 8000.0
	add_child(cam)
	free_cam = FreeCam.new()
	free_cam.far = 8000.0
	add_child(free_cam)
	cam.make_current()
	_make_tv_spots()
	_build_ui()
	_apply_time(0.0, true)
	if not world.online:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if frames < 2:
		return
	if playing and not _scrubbing:
		t += delta          # (already scaled by Engine.time_scale = playback speed)
		if t >= duration:
			t = duration
			_set_playing(false)
	_apply_time(t, false)


func _process(delta: float) -> void:
	if frames < 2:
		return
	if not playing:
		_apply_time(t, true)
	_update_camera(delta / maxf(Engine.time_scale, 0.01))
	if _time_l:
		_time_l.text = "%s / %s   ×%s" % [Game.format_time(t), Game.format_time(duration), str(speed)]
	if _slider and not _scrubbing:
		_slider.set_value_no_signal(t)


## The sample index at or before time `tt`.
func _index(tt: float) -> int:
	var lo := 0
	var hi := frames - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if data[mid * stride] <= tt:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Puts every car where it was at time `tt` (instantly when paused / scrubbing).
func _apply_time(tt: float, snap: bool) -> void:
	var i := _index(tt)
	var j := mini(i + 1, frames - 1)
	var ta := data[i * stride]
	var tb := data[j * stride]
	var f := clampf((tt - ta) / maxf(tb - ta, 1e-4), 0.0, 1.0)
	for k in n_cars:
		var c = cars[k]
		if c == null or not is_instance_valid(c):
			continue
		var a := i * stride + 1 + Replay.CAM_FLOATS + k * Replay.CAR_FLOATS
		var b := j * stride + 1 + Replay.CAM_FLOATS + k * Replay.CAR_FLOATS
		var pa := Vector3(data[a], data[a + 1], data[a + 2])
		var pb := Vector3(data[b], data[b + 1], data[b + 2])
		var qa := Quaternion(data[a + 3], data[a + 4], data[a + 5], data[a + 6])
		var qb := Quaternion(data[b + 3], data[b + 4], data[b + 5], data[b + 6])
		if qa.length_squared() < 0.5:
			continue
		var p := pa.lerp(pb, f)
		var q := qa.slerp(qb, f) if qb.length_squared() > 0.5 else qa
		var v := Vector3(data[a + 7], data[a + 8], data[a + 9]).lerp(Vector3(data[b + 7], data[b + 8], data[b + 9]), f)
		var st := [p, q, v, lerpf(data[a + 10], data[b + 10], f), lerpf(data[a + 11], data[b + 11], f), int(data[a + 12]),
			0.0, 0, 0.0, lerpf(data[a + 13], data[b + 13], f), lerpf(data[a + 14], data[b + 14], f),
			lerpf(data[a + 15], data[b + 15], f), lerpf(data[a + 16], data[b + 16], f)]
		c.apply_net_state(st)
		if snap:
			var xf := Transform3D(Basis(q), p)
			c.global_transform = xf
			c._xf_prev = xf
			c._xf_curr = xf
	# the recorded camera
	var ca := i * stride + 1
	var cb := j * stride + 1
	var cqa := Quaternion(data[ca + 3], data[ca + 4], data[ca + 5], data[ca + 6])
	var cqb := Quaternion(data[cb + 3], data[cb + 4], data[cb + 5], data[cb + 6])
	if cqa.length_squared() > 0.5:
		_cam_xf = Transform3D(Basis(cqa.slerp(cqb, f) if cqb.length_squared() > 0.5 else cqa),
			Vector3(data[ca], data[ca + 1], data[ca + 2]).lerp(Vector3(data[cb], data[cb + 1], data[cb + 2]), f))
		if cam_mode == "original":
			cam.fov = lerpf(data[ca + 7], data[cb + 7], f)


func _set_playing(on: bool) -> void:
	playing = on
	get_tree().paused = not on
	Engine.time_scale = speed if on else 1.0
	if _play_b:
		_play_b.text = "❚❚" if on else "▶"


func seek(tt: float) -> void:
	t = clampf(tt, 0.0, duration)
	_apply_time(t, true)


# ---------------------------------------------------------------------------
# Cameras
# ---------------------------------------------------------------------------
func _target_xf() -> Transform3D:
	var c = cars[target] if target < cars.size() else null
	if c == null or not is_instance_valid(c):
		return Transform3D.IDENTITY
	return c.visual_transform()


func _update_camera(dt: float) -> void:
	var k := 1.0 - pow(clampf(smoothing, 0.0, 0.97), dt * 60.0)
	var txf := _target_xf()
	var tp := txf.origin + Vector3(0, 0.8, 0)
	match cam_mode:
		"original":
			cam.global_transform = _cam_xf
		"chase":
			var back := txf.basis.z
			back.y = 0.0
			back = back.normalized() if back.length() > 0.01 else Vector3.BACK
			var want := tp + back * cam_dist + Vector3(0, cam_height, 0)
			var p := cam.global_position.lerp(want, k) if cam.global_position.distance_to(want) < 60.0 else want
			cam.global_transform = Transform3D(Basis.looking_at(tp - p, Vector3.UP), p)
			cam.fov = fov
		"orbit":
			_orbit += dt * orbit_speed
			var p := tp + Vector3(sin(_orbit), 0, cos(_orbit)) * cam_dist + Vector3(0, cam_height, 0)
			cam.global_transform = Transform3D(Basis.looking_at(tp - p, Vector3.UP), p)
			cam.fov = fov
		"tv":
			# the nearest trackside camera, zoomed in on the car
			var best := -1
			var bd := 1e9
			for i in _tv_spots.size():
				var d := (_tv_spots[i] as Vector3).distance_to(tp)
				if d < bd:
					bd = d
					best = i
			if best >= 0:
				_tv_i = best
				var p: Vector3 = _tv_spots[best]
				var aim := cam.global_transform.basis.z * -1.0
				var want := (tp - p).normalized()
				aim = aim.slerp(want, k) if aim.length() > 0.5 else want
				cam.global_transform = Transform3D(Basis.looking_at(aim, Vector3.UP), p)
				cam.fov = clampf(rad_to_deg(2.0 * atan(5.0 / maxf(bd, 1.0))) * (fov / 70.0), 4.0, 75.0)
		"free":
			free_cam.fov = fov
			free_cam.smoothing = smoothing
	var attrs: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
	if dof:
		if attrs == null:
			attrs = CameraAttributesPractical.new()
			cam.attributes = attrs
			free_cam.attributes = attrs
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = maxf((tp - get_viewport().get_camera_3d().global_position).length() + 4.0, 6.0)
		attrs.dof_blur_far_transition = 20.0
		attrs.dof_blur_near_enabled = true
		attrs.dof_blur_near_distance = 2.0
	elif attrs:
		attrs.dof_blur_far_enabled = false
		attrs.dof_blur_near_enabled = false


func _make_tv_spots() -> void:
	var tr = world.track
	if tr == null or tr.samples.is_empty():
		return
	var spacing: float = tr.length / maxf(tr.samples.size(), 1.0)
	var step := maxi(int(110.0 / maxf(spacing, 0.5)), 1)
	var side := 1.0
	for i in range(0, tr.samples.size(), step):
		var s: Vector3 = tr.samples[i]
		var nxt: Vector3 = tr.samples[(i + 1) % tr.samples.size()]
		var right := (nxt - s).cross(Vector3.UP).normalized()
		var p: Vector3 = s + right * side * (tr.width * 0.5 + 9.0)
		p.y = maxf(world.terrain.height_at(p.x, p.z), s.y) + 5.5
		_tv_spots.append(p)
		side = -side


func set_cam_mode(m: String) -> void:
	cam_mode = m
	if m == "free":
		free_cam.start_from(get_viewport().get_camera_3d().global_transform)
		free_cam.make_current()
	else:
		cam.make_current()


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	ui.add_child(root)
	# bottom bar: play, time line, speed, camera, car
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_bar = UiKit.panel(row)
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = 12
	_bar.offset_right = -12
	_bar.offset_top = -74
	_bar.offset_bottom = -12
	root.add_child(_bar)
	_play_b = UiKit.button("❚❚", func(): _set_playing(not playing), 56)
	row.add_child(_play_b)
	row.add_child(UiKit.button("⟲", func(): seek(0.0), 50))
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = maxf(duration, 0.1)
	_slider.step = 0.01
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(300, 24)
	_slider.drag_started.connect(func(): _scrubbing = true)
	_slider.drag_ended.connect(func(_c): _scrubbing = false)
	_slider.value_changed.connect(func(v): seek(v))
	row.add_child(_slider)
	_time_l = UiKit.label("", 16)
	_time_l.custom_minimum_size = Vector2(190, 0)
	row.add_child(_time_l)
	var sp_names: Array = []
	for s in SPEEDS:
		sp_names.append("×%s" % str(s))
	row.add_child(UiKit.option(sp_names, SPEEDS.find(1.0), func(i):
		speed = SPEEDS[i]
		if playing:
			Engine.time_scale = speed, 90))
	var cm_names: Array = []
	for m in CAM_MODES:
		cm_names.append(m[1])
	row.add_child(UiKit.option(cm_names, 0, func(i): set_cam_mode(CAM_MODES[i][0]), 150))
	var car_names: Array = []
	for c in header.get("cars", []):
		car_names.append(str(c.get("name", "?")))
	row.add_child(UiKit.option(car_names, target, func(i): target = i, 160))
	row.add_child(UiKit.button("⚙", func(): _settings.visible = not _settings.visible, 50))
	row.add_child(UiKit.button("Beenden", func():
		_set_playing(true)
		Engine.time_scale = 1.0
		get_tree().paused = false
		world.exit_requested.emit("menu"), 120))
	# camera settings
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_settings = UiKit.panel(box)
	_settings.position = Vector2(12, 12)
	_settings.visible = false
	root.add_child(_settings)
	box.add_child(UiKit.label("KAMERA", 20, UiKit.GOLD))
	_slider_row(box, "Brennweite (FOV)", 10, 110, 1, fov, func(v): fov = v)
	_slider_row(box, "Abstand", 2, 40, 0.5, cam_dist, func(v): cam_dist = v)
	_slider_row(box, "Höhe", -0.5, 20, 0.1, cam_height, func(v): cam_height = v)
	_slider_row(box, "Weichheit", 0, 0.95, 0.01, smoothing, func(v): smoothing = v)
	_slider_row(box, "Orbit-Tempo", -2, 2, 0.05, orbit_speed, func(v): orbit_speed = v)
	_slider_row(box, "Freie Kamera: Tempo", 1, 150, 1, free_cam.speed, func(v): free_cam.speed = v)
	var dof_cb := CheckBox.new()
	dof_cb.text = "Tiefenunschärfe"
	dof_cb.toggled.connect(func(on): dof = on)
	box.add_child(dof_cb)
	var names_cb := CheckBox.new()
	names_cb.text = "Namen anzeigen"
	names_cb.button_pressed = true
	names_cb.toggled.connect(func(on):
		for c in cars:
			if c and is_instance_valid(c):
				for l in c.find_children("*", "Label3D", false, false):
					(l as Label3D).visible = on)
	box.add_child(names_cb)
	box.add_child(UiKit.label("Freie Kamera: WASD, Q/E, rechte Maustaste: umsehen\nH: Bedienelemente aus/ein · Leertaste: Pause", 14, UiKit.TEXT_DIM))


func _slider_row(box: Control, text: String, lo: float, hi: float, step: float, val: float, f: Callable) -> void:
	var l := UiKit.label("%s: %s" % [text, str(snappedf(val, step))], 15)
	box.add_child(l)
	box.add_child(UiKit.slider(lo, hi, step, val, func(v):
		f.call(v)
		l.text = "%s: %s" % [text, str(snappedf(v, step))], 260))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_H:
				ui.visible = not ui.visible
			KEY_SPACE:
				if cam_mode != "free":
					_set_playing(not playing)
			KEY_LEFT:
				seek(t - 5.0)
			KEY_RIGHT:
				seek(t + 5.0)
			KEY_TAB:
				target = (target + 1) % maxi(n_cars, 1)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().paused = false
