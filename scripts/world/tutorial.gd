extends Node
## The tutorial: a short in-game cutscene in the house (the clock strikes twelve, lightning outside,
## a message on the phone, a sprint to the garage, the R34 starts), then the night drive in the rain
## along the Nordschleife with the controls explained in short pauses, and at the end a gravel track
## into the woods to a caravan and a campfire. [Enter] skips a scene, [F1] the whole tutorial.

const Site = preload("res://scripts/world/tutorial_site.gd")
const Sfx = preload("res://scripts/util/sfx_kit.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const REWARD := 5000

var world          # world.gd
var site: Site
var car
var cam: Camera3D
var state := "intro"           # intro, drive, ending, done
var _shots: Array = []         # {"d": seconds, "enter": Callable, "update": Callable(k, t)}
var _shot := -1
var _st := 0.0                 # time in the current shot
var _clock_strikes := 0
var _next_strike := -1.0
var _audio_db := 0.0
var _drone: AudioStreamPlayer
var _fire_snd: AudioStreamPlayer3D
var _hum: AudioStreamPlayer3D

# lightning
var _flash := 0.0
var _flash_seq: Array = []     # [time, strength] still to come
var _flash_t := 0.0
var _next_bolt := 9.0
var _thunder_in := -1.0
var _thunder_near := false
var _base_ambient := 1.0
var _figure_shown := false

# mission
var _hints: Array = []
var _hint_i := 0
var _hint_open := false
var _progress := 0.0
var _hint_label_t := 0.0
var _arrived := false

# UI
var _layer: CanvasLayer
var _fade: ColorRect
var _bars: Array = []
var _sub: Label
var _skip: Label
var _title: Label
var _title_sub: Label
var _phone_ui: PanelContainer
var _msgs: VBoxContainer
var _hint_panel: PanelContainer
var _hint_title: Label
var _hint_text: Label
var _objective: Label
var _banner: Label


func setup(p_world, p_site: Site) -> void:
	world = p_world
	site = p_site
	car = world.local_car


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	cam = Camera3D.new()
	cam.name = "CutsceneCam"
	cam.fov = 55.0
	cam.near = 0.03
	world.add_child(cam)
	cam.current = true
	world.hud.visible = false
	car.place(site.car_xf)
	car.controls_locked = true
	car.headlights = false
	if car.audio and car.audio.player:
		_audio_db = car.audio.player.volume_db
		car.audio.player.volume_db = -80.0
	world.atmosphere.set_indoor(true)
	world.atmosphere.add_rain_shelter(site.shelter)
	_base_ambient = world.atmosphere.env.ambient_light_energy
	site.set_roller(0.0)
	site.set_garage_lights(0.0)
	site.set_hazards(false)
	site.set_clock(23.0, 59.0, 52.0)
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = Sfx.get_sound("hum")
	_hum.volume_db = -14.0
	_hum.unit_size = 3.0
	world.add_child(_hum)
	_hum.global_position = site.to_world(Vector3(Site.GARAGE_X, Site.CEIL - 0.3, 0.0))
	_fire_snd = AudioStreamPlayer3D.new()
	_fire_snd.stream = Sfx.get_sound("fire")
	_fire_snd.unit_size = 5.0
	_fire_snd.volume_db = -2.0
	world.add_child(_fire_snd)
	_fire_snd.global_position = site.camp
	_fire_snd.play()
	_drone = AudioStreamPlayer.new()
	_drone.stream = Sfx.get_sound("drone")
	_drone.volume_db = -80.0
	add_child(_drone)
	_drone.play()
	_make_intro()
	_make_hints()
	_next_shot()


# ---------------------------------------------------------------------------
# Timeline
# ---------------------------------------------------------------------------
func _shot_add(d: float, enter: Callable, update: Callable) -> void:
	_shots.append({"d": d, "enter": enter, "update": update})


func _next_shot() -> void:
	_shot += 1
	_st = 0.0
	if _shot >= _shots.size():
		_shots.clear()
		_shot = -1
		if state == "intro":
			_start_drive()
		elif state == "ending":
			_finish()
		return
	(_shots[_shot]["enter"] as Callable).call()


func _process(delta: float) -> void:
	var dt := delta if not get_tree().paused else 0.0
	_update_lightning(dt)
	_update_clock_strikes()
	site.set_hazards(fmod(Time.get_ticks_msec() * 0.001, 1.0) < 0.5)
	if site.fire_light:
		var ft := Time.get_ticks_msec() * 0.001
		site.fire_light.light_energy = 1.6 + 0.4 * sin(ft * 17.0) * sin(ft * 5.3) + 0.2 * sin(ft * 31.0)
		site.caravan_light.light_energy = 0.8 + (0.4 if fmod(ft * 1.3, 7.0) < 0.12 else 0.0) - (0.6 if fmod(ft, 11.0) < 0.08 else 0.0)
	if site.tv_light:
		site.tv_light.light_energy = 0.5 + 0.25 * sin(Time.get_ticks_msec() * 0.013) * sin(Time.get_ticks_msec() * 0.0071)
	if _shot >= 0 and not _shots.is_empty() and not get_tree().paused:
		_st += delta
		var s: Dictionary = _shots[_shot]
		var d: float = s["d"]
		(s["update"] as Callable).call(clampf(_st / d, 0.0, 1.0), _st)
		if _st >= d:
			_next_shot()
	match state:
		"drive":
			_drive(dt)
	if _hint_open and not get_tree().paused and not world.pause_menu.visible:
		get_tree().paused = true
	if _hint_label_t > 0.0:
		_hint_label_t -= delta
		if _hint_label_t <= 0.0:
			_banner.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_F1:
			_skip_all()
			get_viewport().set_input_as_handled()
			return
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			if _hint_open:
				_close_hint()
				get_viewport().set_input_as_handled()
			elif _shot >= 0 and state == "intro":
				_skip_intro()
				get_viewport().set_input_as_handled()
			elif _shot >= 0 and state == "ending" and k != KEY_SPACE:
				_skip_ending()
				get_viewport().set_input_as_handled()


## Smooth camera move between two transforms.
func _cam_move(a: Transform3D, b: Transform3D, k: float) -> void:
	var e := k * k * (3.0 - 2.0 * k)
	cam.global_transform = Transform3D(a.basis.slerp(b.basis, e).orthonormalized(), a.origin.lerp(b.origin, e))


# ---------------------------------------------------------------------------
# The intro
# ---------------------------------------------------------------------------
func _make_intro() -> void:
	var fl := Site.FL
	var clock := Vector3(-1.08, fl + 1.95, -3.0)
	# 1 – the clock: 23:59:52 … midnight
	var e1 := func() -> void:
		_letterbox(true)
		_fade_to(0.0, 2.0)
		cam.fov = 38.0
	var u1 := func(k: float, t: float) -> void:
		_cam_move(site.cam_xf(Vector3(-2.7, fl + 1.72, -3.35), clock), site.cam_xf(Vector3(-2.0, fl + 1.86, -3.1), clock), k)
		var sec := 52.0 + t
		if int(sec) != int(sec - get_process_delta_time()) and sec < 60.0:
			Sfx.play(world, "tick", -12.0, site.to_world(clock))
		if sec >= 60.0:
			site.set_clock(0.0, 0.0, sec - 60.0)
			if _clock_strikes == 0:
				_clock_strikes = 1
				_next_strike = 0.0
				Sfx.play(world, "chime", -2.0, site.to_world(clock))
		else:
			site.set_clock(23.0, 59.0, sec)
	_shot_add(8.6, e1, u1)
	# 2 – out of the window: rain on the glass, lightning, thunder
	var e2 := func() -> void:
		cam.fov = 52.0
	var u2 := func(k: float, t: float) -> void:
		_cam_move(site.cam_xf(Vector3(-5.3, fl + 1.5, -1.9), Vector3(-6.4, fl + 1.6, -4.6)), site.cam_xf(Vector3(-5.9, fl + 1.52, -3.35), Vector3(-6.5, fl + 1.65, -6.0)), k)
		if t > 2.0 and not _shot_flag("w_flash"):
			_bolt(1.0, true, 0.9)
	_shot_add(7.0, e2, u2)
	# 3 – the phone lights up on the table
	var e3 := func() -> void:
		cam.fov = 45.0
	var u3 := func(k: float, t: float) -> void:
		var pp: Vector3 = site.phone.global_position
		var eye_a := site.to_world(Vector3(-6.0, fl + 1.25, -0.9))
		var eye_b := site.to_world(Vector3(-6.45, fl + 0.85, -1.35))
		_cam_move(Transform3D(Basis.looking_at((pp - eye_a).normalized(), Vector3.UP), eye_a), Transform3D(Basis.looking_at((pp - eye_b).normalized(), Vector3.UP), eye_b), k)
		if t > 0.4 and not _shot_flag("vib"):
			Sfx.play(world, "vibrate", -4.0, pp)
			site.phone_mat.emission_energy_multiplier = 1.4
			site.phone_light.light_energy = 0.6
		if t > 0.4 and t < 1.4:
			site.phone.rotation.y = 0.35 + sin(t * 90.0) * 0.02 * (1.4 - t)
		if t > 1.3 and not _shot_flag("ui"):
			_phone_show(true)
			_phone_msg("Kenji", "Ich brauch Hilfe, hier ist was im Wald.", false)
			Sfx.play(world, "notify", -6.0)
		if t > 3.6 and not _shot_flag("ui2"):
			_phone_msg("Kenji", "Beim Wohnwagen, kurz vorm Adenauer Forst. Beeil dich!!", false)
			Sfx.play(world, "notify", -6.0)
		if t > 5.6 and not _shot_flag("ui3"):
			_phone_msg("Du", "Bin unterwegs.", true)
			Sfx.play(world, "whoosh", -14.0)
	_shot_add(7.5, e3, u3)
	# 4 – POV: up from the sofa, through the hallway, into the garage, round to the driver's door
	var seat := Vector3(-5.05, fl + 1.12, -1.8)
	var run_path := [Vector3(-4.6, fl + 1.66, -1.3), Vector3(-2.2, fl + 1.66, -0.45), Vector3(-1.0, fl + 1.66, -0.3),
		Vector3(0.8, fl + 1.66, -0.05), Vector3(2.05, fl + 1.64, 0.0), Vector3(3.3, 1.5, 0.35), Vector3(3.9, 1.5, 2.5), Vector3(6.35, 1.5, 2.55), Vector3(6.6, 1.45, 0.7)]
	var e4 := func() -> void:
		_phone_show(false)
		cam.fov = 70.0
	var u4 := func(k: float, t: float) -> void:
		# 0 … 0.9 s: stand up; then run along the path, slowing down at the end
		var p: Vector3
		var ahead: Vector3
		if t < 0.9:
			var su := t / 0.9
			p = seat.lerp(run_path[0], su * su * (3.0 - 2.0 * su))
			ahead = run_path[1]
		else:
			var run := clampf((t - 0.9) / 6.6, 0.0, 1.0)
			var s := run * run * (3.0 - 2.0 * run)
			p = _along(run_path, s)
			ahead = _along(run_path, minf(s + 0.08, 1.0))
		if t > 7.5:
			ahead = Vector3(Site.GARAGE_X + 0.3, 1.2, 0.3)
		var bob := sin(t * 15.0) * 0.045 * (1.0 if t > 1.0 and t < 7.4 else 0.0)
		var eye := site.to_world(p + Vector3(0, bob, 0))
		var look := site.to_world(ahead + Vector3(0, -0.1, 0))
		var want := Transform3D(Basis.looking_at((look - eye).normalized(), Vector3.UP), eye)
		cam.global_transform = Transform3D(cam.global_transform.basis.slerp(want.basis, 0.2).orthonormalized(), eye)
		cam.fov = lerpf(70.0, 80.0, clampf((t - 1.0) * 2.0, 0.0, 1.0) * (1.0 - clampf((t - 7.0) * 2.0, 0.0, 1.0)))
		if t > 1.0 and t < 7.4 and fmod(t, 0.33) < get_process_delta_time():
			Sfx.play(world, "step", -8.0, eye - Vector3(0, 1.5, 0), randf_range(0.9, 1.1))
		var door_k := clampf((t - 3.2) / 0.5, 0.0, 1.0)
		site.door_pivot.rotation.y = 1.6 * door_k * door_k
		if t > 3.1 and not _shot_flag("door"):
			Sfx.play(world, "door_open", -4.0, site.to_world(Vector3(2.0, 1.2, 0.0)))
		if t > 3.9 and not _shot_flag("fluoro"):
			Sfx.play(world, "fluoro_on", -3.0, site.to_world(Vector3(Site.GARAGE_X, 2.8, 0.0)))
			_hum.play()
		# the tubes flicker on
		if t > 3.9:
			var ft := t - 3.9
			site.set_garage_lights(1.0 if ft > 0.7 or fmod(ft, 0.18) < 0.07 else 0.08)
		world.atmosphere.set_indoor(t < 3.3)
	_shot_add(8.5, e4, u4)
	# 5 – in the garage: door shut, starter, engine, headlights, roller door
	var e5 := func() -> void:
		cam.fov = 50.0
		Sfx.play(world, "car_door", -2.0, car.global_position)
	var u5 := func(k: float, t: float) -> void:
		_cam_move(site.cam_xf(Vector3(Site.GARAGE_X - 1.9, 0.75, -3.8), Vector3(Site.GARAGE_X, 0.75, -0.3)),
			site.cam_xf(Vector3(Site.GARAGE_X - 1.2, 0.95, -4.2), Vector3(Site.GARAGE_X + 0.2, 0.8, -0.6)), k)
		if t > 1.0 and not _shot_flag("starter"):
			Sfx.play(world, "starter", -2.0, car.global_position)
		if t > 2.2 and not _shot_flag("engine"):
			if car.audio and car.audio.player:
				car.audio.player.volume_db = _audio_db
			car.headlights = true
		if t > 2.4 and t < 3.4:
			car.rpm = lerpf(car.rpm, car.redline * 0.45, 0.1)      # a blip
		if t > 3.6 and not _shot_flag("roller"):
			Sfx.play(world, "roller_door", -2.0, site.to_world(Vector3(Site.GARAGE_X, 2.5, -4.5)))
		site.set_roller(clampf((t - 3.6) / 3.3, 0.0, 1.0))
		if t > 5.8 and not _shot_flag("bolt2"):
			_bolt(0.9, true, 1.2)
	_shot_add(8.0, e5, u5)
	# 6 – outside: the open garage, the car's lights in the rain, the title
	var e6 := func() -> void:
		cam.fov = 60.0
		world.atmosphere.set_indoor(false)
		_title_show("MITTERNACHT", "Fahr zu Kenji – Waldweg vor dem Adenauer Forst · 3,1 km")
	var u6 := func(k: float, t: float) -> void:
		_cam_move(site.cam_xf(Vector3(Site.GARAGE_X + 4.5, 1.1, -13.0), Vector3(Site.GARAGE_X, 1.0, -3.0)),
			site.cam_xf(Vector3(Site.GARAGE_X + 2.5, 1.6, -11.0), Vector3(Site.GARAGE_X, 1.0, -2.0)), k)
		if t > 4.6:
			_fade_to(1.0, 0.8)
	_shot_add(5.5, e6, u6)


var _flags := {}


## True the second time it is asked in the current shot (one-shot events inside update functions).
func _shot_flag(name: String) -> bool:
	var key := "%d_%s_%s" % [_shot, state, name]
	if _flags.has(key):
		return true
	_flags[key] = true
	return false


func _along(pts: Array, k: float) -> Vector3:
	var total := 0.0
	for i in pts.size() - 1:
		total += (pts[i] as Vector3).distance_to(pts[i + 1])
	var d := clampf(k, 0.0, 1.0) * total
	for i in pts.size() - 1:
		var l := (pts[i] as Vector3).distance_to(pts[i + 1])
		if d <= l:
			return (pts[i] as Vector3).lerp(pts[i + 1], d / maxf(l, 0.001))
		d -= l
	return pts[pts.size() - 1]


func _update_clock_strikes() -> void:
	if _clock_strikes <= 0 or _clock_strikes >= 12:
		return
	_next_strike += get_process_delta_time()
	if _next_strike >= 1.6:
		_next_strike = 0.0
		_clock_strikes += 1
		var vol := -2.0 - (_clock_strikes * 1.5 if state != "intro" else 0.0)
		Sfx.play(world, "chime", vol, site.to_world(Vector3(-1.08, Site.FL + 1.95, -3.0)))


func _skip_intro() -> void:
	_shots.clear()
	_shot = -1
	_clock_strikes = 12
	_phone_show(false)
	site.set_clock(0.0, 0.1, 0.0)
	site.set_garage_lights(1.0)
	site.set_roller(1.0)
	site.door_pivot.rotation.y = 1.6
	site.phone_mat.emission_energy_multiplier = 0.4
	if not _hum.playing:
		_hum.play()
	world.atmosphere.set_indoor(false)
	if car.audio and car.audio.player:
		car.audio.player.volume_db = _audio_db
	car.headlights = true
	_start_drive()


# ---------------------------------------------------------------------------
# The drive
# ---------------------------------------------------------------------------
func _make_hints() -> void:
	var hp := Site.HOUSE_P
	# [progress (m, -1 = at the start), title, text, pause]
	_hints = [
		[-1.0, "GAS & BREMSE", "[W] / [↑] / RT  –  Gas\n[S] / [↓] / LT  –  Bremse, im Stand rückwärts\n\nFahr aus der Garage die Einfahrt hinunter und bieg RECHTS auf die Strecke ab.", true],
		[hp + 45.0, "LENKEN", "[A] [D] / [←] [→] / linker Stick  –  lenken\n\nDie Strecke ist nass und es ist dunkel: lenk sanft, gib gefühlvoll Gas.\nJe schneller du fährst, desto feiner lenkt das Auto.", true],
		[hp + 380.0, "SCHALTEN", "Die Automatik schaltet selbst.\n[E] / RB  –  hoch,  [Q] / LB  –  runter: wie Schaltwippen, auch in der Automatik.\n[M]  –  Automatik ⇄ Manuell", true],
		[hp + 820.0, "HANDBREMSE & DRIFTEN", "[Leertaste] / (A)  –  Handbremse\n\nKurz ziehen, einlenken, Gas geben: das Heck kommt – gegenlenken und mit dem Gas halten.\nJeder Drift bringt Punkte (DRIFT-SCORE oben). Ab 50.000 am Stück ziehst du eine Driftspur.", true],
		[hp + 1320.0, "NITRO", "[Shift] / (B)  –  Nitro\n\nDer blaue Balken im Tacho. Am besten auf der Geraden – und nicht vor der Kurve!", true],
		[hp + 1760.0, "LICHT & KAMERA", "[L]  –  Licht an / aus      [C]  –  Kamera wechseln\n[B]  –  Blick zurück       [R]  –  zurücksetzen, falls du feststeckst\n\nGleich kommt Aremberg: eine harte Rechtskurve. Früh bremsen!", true],
		[Site.EXIT_P - 420.0, "", "Kurz vor dem Adenauer Forst: rechts geht ein Waldweg ab – achte auf die Warnblinker.", false],
		[Site.EXIT_P - 90.0, "", "Da vorne – RECHTS in den Waldweg!", false],
	]


func _start_drive() -> void:
	state = "drive"
	_letterbox(false)
	_fade_to(0.0, 0.6)
	_title_show("", "")
	cam.current = false
	world.camera.make_current()
	world.hud.visible = true
	world.hud.show_message("MITTERNACHT", "Fahr zu Kenji – Waldweg vor dem Adenauer Forst", Color(1.0, 0.8, 0.5), 3.0)
	car.controls_locked = false
	car.input_enabled = true
	car.headlights = true
	_skip.text = "[F1] Tutorial überspringen"
	_objective.visible = true
	# the car audio was muted during the cutscene
	if car.audio and car.audio.player:
		car.audio.player.volume_db = _audio_db
	world.atmosphere.set_indoor(false)
	car.surface_override = _surface
	_hint_i = 0
	_show_hint(_hints[0])
	_hint_i = 1


## Grip: the gravel track and the clearing are loose, everything else as the track says.
func _surface(p: Vector3) -> Array:
	if site.on_track_path(p) and world.track.distance_to_center(p) > float(world.track.half_w) + 1.5:
		return [0.8, "gravel"]
	return world.track.surface_at(p, car.track_hint)


func _drive(_dt: float) -> void:
	var proj: Array = world.track.project(car.global_position, car.track_hint)
	_progress = fposmod(float(proj[1]), float(world.track.length))
	var to_go := Site.EXIT_P - _progress
	var d_camp: float = Vector2(car.global_position.x - site.camp.x, car.global_position.z - site.camp.z).length()
	if to_go > 0.0 and to_go < 4000.0:
		_objective.text = "ZIEL: Waldweg vor dem Adenauer Forst  ·  %.1f km" % (to_go / 1000.0)
	else:
		_objective.text = "ZIEL: Kenji am Wohnwagen  ·  %d m" % int(d_camp)
	var sec: String = world.track.section_at(_progress)
	if sec != "":
		_objective.text += "\n" + sec
	# hints by distance
	if _hint_i < _hints.size() and not _hint_open:
		var h: Array = _hints[_hint_i]
		if _progress >= float(h[0]) and _progress < Site.EXIT_P + 200.0:
			_hint_i += 1
			if bool(h[3]):
				_show_hint(h)
			else:
				_banner.text = str(h[2])
				_hint_label_t = 6.0
	# the shape between the trees: a lightning strike as you pass it
	if not _figure_shown and _progress > Site.FIGURE_P - 110.0 and _progress < Site.FIGURE_P - 40.0:
		_figure_shown = true
		_bolt(1.0, false, 1.6)
	# on the gravel track: guidance, then the camp
	if d_camp < 120.0 and not _arrived and site.on_track_path(car.global_position):
		if _banner.text == "":
			_banner.text = "Folge dem Schotterweg …"
			_hint_label_t = 4.0
	if d_camp < 15.0 and not _arrived:
		_arrived = true
		_start_ending()


func _show_hint(h: Array) -> void:
	_hint_title.text = str(h[1])
	_hint_text.text = str(h[2])
	_hint_panel.visible = true
	_hint_open = true
	get_tree().paused = true


func _close_hint() -> void:
	_hint_panel.visible = false
	_hint_open = false
	get_tree().paused = false


# ---------------------------------------------------------------------------
# The ending at the campfire
# ---------------------------------------------------------------------------
func _start_ending() -> void:
	state = "ending"
	_objective.visible = false
	_banner.text = ""
	car.controls_locked = true
	world.hud.visible = false
	cam.current = true
	_letterbox(true)
	var camp_xf: Transform3D = site.kenji.get_parent().global_transform
	var kenji_p: Vector3 = site.kenji.global_position
	var fire_p: Vector3 = site.fire_light.global_position
	# 1 – the car rolls into the clearing, Kenji turns
	var e1 := func() -> void:
		cam.fov = 50.0
	var u1 := func(k: float, t: float) -> void:
		# from behind the car, past it into the clearing: the headlights on Kenji and the fire
		var cx: Transform3D = car.global_transform
		var eye := cx.origin + cx.basis.z * lerpf(5.5, 4.5, k) + cx.basis.x * 2.2 + Vector3(0, 1.5, 0)
		var tgt := kenji_p + Vector3(0, 1.1, 0)
		cam.global_transform = Transform3D(Basis.looking_at((tgt - eye).normalized(), Vector3.UP), eye)
		if t > 1.0:
			_say("Kenji", "Da bist du ja! Endlich …")
	_shot_add(4.5, e1, u1)
	# 2 – by the fire
	var e2 := func() -> void:
		cam.fov = 40.0
		_drone_fade(-18.0)
	var u2 := func(k: float, t: float) -> void:
		var eye_a := kenji_p + (camp_xf.basis * Vector3(-0.9, 1.35, -3.4))
		var eye_b := eye_a + camp_xf.basis * Vector3(0.4, 0, 0.5)
		var tgt := kenji_p + Vector3(0, 1.55, 0)
		_cam_move(Transform3D(Basis.looking_at((tgt - eye_a).normalized(), Vector3.UP), eye_a), Transform3D(Basis.looking_at((tgt - eye_b).normalized(), Vector3.UP), eye_b), k)
		site.kenji.rotation.y = lerpf(site.kenji.rotation.y, 0.2 + sin(t * 0.8) * 0.15, 0.05)
		if t > 0.6:
			_say("Kenji", "Hörst du das? Da draußen … zwischen den Bäumen.")
	_shot_add(6.0, e2, u2)
	# 3 – into the dark woods: lightning, eyes
	var e3 := func() -> void:
		cam.fov = 45.0
		_say("", "")
	var u3 := func(k: float, t: float) -> void:
		var eye := fire_p + Vector3(0, 0.9, 0)
		var tgt_a := camp_xf * Vector3(3.0, 1.2, 10.0)
		var tgt_b := camp_xf * Vector3(-1.0, 1.8, 18.0)
		_cam_move(Transform3D(Basis.looking_at((tgt_a - eye).normalized(), Vector3.UP), eye), Transform3D(Basis.looking_at((tgt_b - eye).normalized(), Vector3.UP), eye), minf(k * 1.4, 1.0))
		if t > 2.2 and not _shot_flag("eyes"):
			_bolt(1.0, true, 0.35)
			_drone_fade(-8.0)
		for e in site.eyes:
			(e as Node3D).visible = t > 2.2 and t < 4.1
	_shot_add(5.0, e3, u3)
	# 4 – "come on" – up and away, fade out
	var e4 := func() -> void:
		cam.fov = 55.0
		_say("Kenji", "Komm. Wir sollten hier nicht bleiben.")
	var u4 := func(k: float, t: float) -> void:
		var eye := camp_xf * Vector3(0.0, lerpf(3.0, 22.0, k), lerpf(-6.0, -14.0, k))
		var tgt := camp_xf * Vector3(0, 0.5, 3.0)
		cam.global_transform = Transform3D(Basis.looking_at((tgt - eye).normalized(), Vector3.UP), eye)
		if t > 4.4:
			_fade_to(1.0, 1.4)
	_shot_add(6.0, e4, u4)
	_next_shot()


func _skip_ending() -> void:
	_shots.clear()
	_shot = -1
	_finish()


func _finish() -> void:
	if state == "done":
		return
	state = "done"
	_say("", "")
	_letterbox(false)
	_fade_to(0.85, 0.5)
	for e in site.eyes:
		(e as Node3D).visible = false
	Game.settings["tutorial_done"] = true
	Game.add_credits(REWARD)
	Game.save_settings()
	_title_show("TUTORIAL ABGESCHLOSSEN", "+%s Credits   ·   Fortsetzung folgt …" % Game.format_points(REWARD))
	_skip.text = ""
	var btn := UiKit.button("Hauptmenü", func(): world.request_main_menu(), 260)
	btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	btn.position = Vector2(-130, -140)
	_layer.get_child(0).add_child(btn)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	btn.grab_focus()


func _skip_all() -> void:
	if state == "done":
		return
	get_tree().paused = false
	Game.settings["tutorial_done"] = true
	Game.save_settings()
	world.request_main_menu()


func _drone_fade(db: float) -> void:
	var tw := create_tween()
	tw.tween_property(_drone, "volume_db", db, 2.0)


# ---------------------------------------------------------------------------
# Lightning and thunder
# ---------------------------------------------------------------------------
## A strike: two or three quick flashes, thunder after `delay` seconds (near = the crack).
func _bolt(strength: float, near: bool, delay: float) -> void:
	_flash_t = 0.0
	_flash_seq = [[0.0, strength], [0.09, strength * 0.35], [0.16, strength * 0.9], [0.45, strength * 0.5]]
	_thunder_in = delay
	_thunder_near = near


func _update_lightning(dt: float) -> void:
	if state == "drive" or state == "ending" or (state == "intro" and _shot >= 1):
		_next_bolt -= dt
		if _next_bolt <= 0.0 and state == "drive":
			_next_bolt = randf_range(10.0, 24.0)
			_bolt(randf_range(0.5, 1.0), randf() < 0.3, randf_range(0.8, 3.0))
	_flash_t += dt
	var target := 0.0
	var keep: Array = []
	for f in _flash_seq:
		if _flash_t >= float(f[0]):
			target = maxf(target, float(f[1]))
		else:
			keep.append(f)
	if keep.size() < _flash_seq.size():
		_flash = maxf(_flash, target)
	_flash_seq = keep
	_flash = maxf(_flash - dt * 7.0, 0.0)
	site.lightning.light_energy = _flash * 6.0
	world.atmosphere.env.ambient_light_energy = _base_ambient * (1.0 + _flash * 5.0)
	site.window_mat.set_shader_parameter("flash", _flash)
	if site.figure:
		site.figure.visible = _flash > 0.25 and state == "drive"
	if _thunder_in > 0.0:
		_thunder_in -= dt
		if _thunder_in <= 0.0:
			var pos = null
			Sfx.play(world, "thunder_near" if _thunder_near else "thunder_far", 2.0 if _thunder_near else -2.0, pos, randf_range(0.9, 1.05))


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	_layer.add_child(root)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
		root.add_child(bar)
		_bars.append(bar)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_sub = UiKit.label("", 26, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.position = Vector2(-600, -150)
	_sub.size = Vector2(1200, 60)
	_sub.add_theme_constant_override("outline_size", 10)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	root.add_child(_sub)
	_skip = UiKit.label("[Enter] Szene überspringen   ·   [F1] Tutorial überspringen", 15, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	_skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.position = Vector2(-620, -40)
	_skip.size = Vector2(600, 24)
	root.add_child(_skip)
	_title = UiKit.label("", 64, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_override("font", UiKit.title_font())
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.position = Vector2(-600, -90)
	_title.size = Vector2(1200, 90)
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	root.add_child(_title)
	_title_sub = UiKit.label("", 22, Color(0.95, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_title_sub.set_anchors_preset(Control.PRESET_CENTER)
	_title_sub.position = Vector2(-600, 10)
	_title_sub.size = Vector2(1200, 40)
	_title_sub.add_theme_constant_override("outline_size", 8)
	_title_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	root.add_child(_title_sub)
	# the phone: a dark rounded screen with message bubbles, lower right
	_phone_ui = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.04, 0.06, 0.96)
	ps.set_corner_radius_all(26)
	ps.border_color = Color(0.2, 0.2, 0.24)
	ps.set_border_width_all(6)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 22
	ps.content_margin_bottom = 22
	_phone_ui.add_theme_stylebox_override("panel", ps)
	_phone_ui.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_phone_ui.position = Vector2(-430, -300)
	_phone_ui.custom_minimum_size = Vector2(360, 540)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	var head := UiKit.label("00:00                         Kenji", 16, Color(0.8, 0.8, 0.85))
	pv.add_child(head)
	var line := ColorRect.new()
	line.color = Color(0.25, 0.25, 0.3)
	line.custom_minimum_size = Vector2(0, 1)
	pv.add_child(line)
	_msgs = VBoxContainer.new()
	_msgs.add_theme_constant_override("separation", 10)
	pv.add_child(_msgs)
	_phone_ui.add_child(pv)
	_phone_ui.visible = false
	root.add_child(_phone_ui)
	# hint panel (the game pauses while it is open)
	_hint_panel = PanelContainer.new()
	_hint_panel.set_anchors_preset(Control.PRESET_CENTER)
	_hint_panel.position = Vector2(-360, -170)
	_hint_panel.custom_minimum_size = Vector2(720, 0)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 12)
	_hint_title = UiKit.label("", 34, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_hint_title.add_theme_font_override("font", UiKit.title_font())
	_hint_text = UiKit.label("", 20, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_text.custom_minimum_size = Vector2(680, 0)
	hv.add_child(_hint_title)
	hv.add_child(_hint_text)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	hb.add_child(UiKit.button("Weiter  [Enter]", _close_hint, 240))
	hb.add_child(UiKit.button("Tutorial überspringen  [F1]", _skip_all, 320))
	hv.add_child(hb)
	_hint_panel.add_child(hv)
	_hint_panel.visible = false
	root.add_child(_hint_panel)
	_objective = UiKit.label("", 18, Color(1.0, 0.85, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_objective.position = Vector2(-400, 100)
	_objective.size = Vector2(800, 50)
	_objective.add_theme_constant_override("outline_size", 8)
	_objective.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_objective.visible = false
	root.add_child(_objective)
	_banner = UiKit.label("", 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-600, -230)
	_banner.size = Vector2(1200, 60)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	root.add_child(_banner)


func _letterbox(on: bool) -> void:
	var h := 90.0 if on else 0.0
	var tw := create_tween()
	tw.tween_property(_bars[0], "offset_bottom", h, 0.6)
	tw.parallel().tween_property(_bars[1], "offset_top", -h, 0.6)


func _fade_to(a: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, secs)


func _title_show(t: String, s: String) -> void:
	_title.text = t
	_title_sub.text = s


func _say(who: String, text: String) -> void:
	_sub.text = ("%s:  %s" % [who, text]) if who != "" else text


func _phone_show(on: bool) -> void:
	_phone_ui.visible = on
	if not on:
		for c in _msgs.get_children():
			c.queue_free()


func _phone_msg(who: String, text: String, mine: bool) -> void:
	var bubble := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.1, 0.45, 0.95) if mine else Color(0.2, 0.2, 0.24)
	bs.set_corner_radius_all(16)
	bs.content_margin_left = 14
	bs.content_margin_right = 14
	bs.content_margin_top = 10
	bs.content_margin_bottom = 10
	bubble.add_theme_stylebox_override("panel", bs)
	var l := UiKit.label(text, 18, Color(1, 1, 1))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(250, 0)
	bubble.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	row.add_child(bubble)
	_msgs.add_child(row)
