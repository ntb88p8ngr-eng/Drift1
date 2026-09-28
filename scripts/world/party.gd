extends Node3D
## Party mode: glowing minigame coins lie on the track. Whoever drives through one stops the race for
## everybody and a minigame is drawn: all cars are taken to its stretch of the track, where its props
## are put up for the time of the game (party_sites.gd), play it, get credits by rank and are put
## back where they were. Offline the local player plays
## alone; online the host referees (who got the coin first, which game, the final ranking).
## Flow per minigame: announce (roulette) -> travel (countdown on the stretch) -> play -> results -> back.

const PartySites = preload("res://scripts/world/party_sites.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const GAMES := [
	{"id": "rlgl", "name": "Rotes Licht, Grünes Licht", "time": 90.0, "unit": "m",
		"desc": "Fahr ins Ziel – aber bei ROT musst du stillstehen! Wer sich bei Rot bewegt, muss zurück zum Start."},
	{"id": "parkour", "name": "Offroad-Parkour", "time": 120.0, "unit": "m",
		"desc": "Schlamm, Reifenslalom, Baumstämme, Sprungschanzen und Schikanen: zuerst im Ziel gewinnt. [R] = zurück zum letzten Checkpoint."},
	{"id": "koth", "name": "König der Zone", "time": 60.0, "unit": "s",
		"desc": "Bleib in der leuchtenden Zone – sie wandert alle 10 Sekunden über die Straße. Schubs die anderen raus!"},
	{"id": "donut", "name": "Donut-Duell", "time": 30.0, "unit": "x",
		"desc": "Dreh so viele Donuts wie möglich – jede volle Drehung zählt. 30 Sekunden!"},
]
const ANNOUNCE_TIME := 4.5
const COUNTDOWN_TIME := 3.5
const RESULTS_TIME := 6.0
const COIN_RESPAWN := 20.0
const REWARDS := [2500, 1200, 600, 300]
const KOTH_STEP := 10.0

var world: Node3D
var sites: PartySites
var games_total := 3
var games_played := 0
var coin_count := 5
var seed_base := 0

var state := "idle"          # idle, announce, travel, play, wait, results, back
var _t := 0.0
var _game := -1              # index into GAMES
var _seed := 0
var _slot := 0
var _ids: Array = []         # participants (peer ids) of the current minigame
var _return_xf := Transform3D.IDENTITY
var _coins: Array = []       # {node, gen, active, timer}
var _value := 0.0            # local score of the current minigame (higher is better)
var _done := false
var _finish_t := 0.0
var _results := {}           # host: peer id -> value
var _checkpoint := -104.0
var _rl_phases: Array = []   # red light green light: [end time, green?]
var _red_since := -1.0
var _penalty := 0.0
var _yaw_acc := 0.0
var _last_yaw := 0.0
var _hint := -1              # track sample near the car (for projecting)
var _zone := Vector2.ZERO     # king of the zone: current spot (along, lateral)
var _coin_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D

# UI
var _layer: CanvasLayer
var _info: Label
var _banner: PanelContainer
var _b_title: Label
var _b_game: Label
var _b_desc: Label
var _b_by: Label
var _status: Label
var _line: Label
var _table: VBoxContainer
var _status_t := 0.0


func setup(p_world: Node3D, p_sites: PartySites, cfg: Dictionary) -> void:
	world = p_world
	sites = p_sites
	games_total = clampi(int(cfg.get("party_games", 3)), 1, 20)
	coin_count = clampi(int(cfg.get("party_coins", 5)), 1, 20)
	seed_base = int(cfg.get("weather_seed", 1)) * 7919 + 17


func _ready() -> void:
	_build_ui()
	_make_coins()
	if world.online:
		Net.party_msg.connect(_on_msg)
	_update_info()


## True while a minigame holds up the race (the world stops its clock and lap counting).
func active() -> bool:
	return state != "idle"


# ---------------------------------------------------------------------------
# Coins
# ---------------------------------------------------------------------------
func _make_coins() -> void:
	_coin_mat = StandardMaterial3D.new()
	_coin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_coin_mat.albedo_color = Color(1.0, 0.82, 0.12, 0.6)
	_coin_mat.metallic = 0.7
	_coin_mat.roughness = 0.25
	_coin_mat.emission_enabled = true
	_coin_mat.emission = Color(1.0, 0.7, 0.05)
	_coin_mat.emission_energy_multiplier = 1.6
	_coin_mat.rim_enabled = true
	_coin_mat.rim = 1.0
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(1.0, 0.75, 0.1, 0.12)
	for i in coin_count:
		var node := _coin_node()
		add_child(node)
		_coins.append({"node": node, "gen": 0, "active": true, "timer": 0.0})
		_place_coin(i)


func _coin_node() -> Node3D:
	var root := Node3D.new()
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.95
	disc.bottom_radius = 0.95
	disc.height = 0.2
	disc.radial_segments = 40
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.material_override = _coin_mat
	mi.rotation = Vector3(PI * 0.5, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(mi)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.8
	rim.outer_radius = 1.0
	rim.rings = 40
	rim.ring_segments = 10
	var rmi := MeshInstance3D.new()
	rmi.mesh = rim
	rmi.material_override = _coin_mat
	rmi.rotation = Vector3(PI * 0.5, 0, 0)
	rmi.scale = Vector3(1, 1.6, 1)
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(rmi)
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "★"
		l.font_size = 120
		l.pixel_size = 0.009
		l.modulate = Color(1.0, 0.95, 0.6, 0.95)
		l.outline_size = 0
		l.position = Vector3(0, 0, 0.12 * side)
		l.rotation = Vector3(0, 0.0 if side > 0.0 else PI, 0)
		spin.add_child(l)
	# a faint light column so the coin can be found from far away
	var beam := CylinderMesh.new()
	beam.top_radius = 0.25
	beam.bottom_radius = 0.7
	beam.height = 30.0
	beam.cap_top = false
	beam.cap_bottom = false
	beam.radial_segments = 16
	var bmi := MeshInstance3D.new()
	bmi.mesh = beam
	bmi.material_override = _beam_mat
	bmi.position = Vector3(0, 15.0, 0)
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bmi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.2)
	light.omni_range = 6.0
	light.light_energy = 1.2
	light.shadow_enabled = false
	root.add_child(light)
	return root


## Deterministic coin spot (the same on every machine): coin i, generation gen.
func _place_coin(i: int) -> void:
	var c: Dictionary = _coins[i]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_base, i, int(c["gen"])])
	var tr = world.track
	var n: int = tr.sample_count()
	# spread the coins around the lap, away from the start line
	var base := (float(i) + r.randf_range(0.15, 0.85)) / float(coin_count)
	var idx := int(base * n) % n
	var lat := r.randf_range(-1.0, 1.0) * (float(tr.half_w) - 2.5)
	var xf: Transform3D = tr.transform_at(idx, lat, 1.3)
	(c["node"] as Node3D).global_position = xf.origin
	(c["node"] as Node3D).visible = bool(c["active"])


func _process_coins(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_coin_mat.emission_energy_multiplier = 1.3 + 0.6 * sin(t * 3.0)
	var can_take: bool = state == "idle" and games_played < games_total and world.state == "running" and not world.finished
	var car = world.local_car
	for i in _coins.size():
		var c: Dictionary = _coins[i]
		var node: Node3D = c["node"]
		if not bool(c["active"]):
			if games_played < games_total and state == "idle":
				c["timer"] = float(c["timer"]) - delta
				if float(c["timer"]) <= 0.0:
					c["active"] = true
					_place_coin(i)
			node.visible = false
			continue
		node.visible = games_played < games_total and state == "idle"
		var spin: Node3D = node.get_node("Spin")
		spin.rotation.y = fmod(t * 2.2 + i, TAU)
		spin.position.y = 0.25 * sin(t * 2.0 + i * 1.7)
		if can_take and car and node.visible:
			var d: Vector3 = car.global_position - node.global_position
			if Vector2(d.x, d.z).length() < 2.6 and absf(d.y) < 3.0:
				_claim(i)
				can_take = false


func _claim(i: int) -> void:
	if world.online:
		if not Net.is_host():
			# hide it right away (the host decides; a start message follows)
			(_coins[i]["node"] as Node3D).visible = false
		Net.party_to_host({"t": "claim", "i": i})
	else:
		_host_start(i, 1)


# ---------------------------------------------------------------------------
# Host / referee
# ---------------------------------------------------------------------------
func _host_start(coin: int, by: int) -> void:
	if state != "idle" or games_played >= games_total or coin < 0 or coin >= _coins.size() or not bool(_coins[coin]["active"]):
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_base, games_played, Time.get_ticks_usec()])
	# only the minigames whose venue found room on this map
	var avail: Array = []
	for k in GAMES.size():
		if sites.sites.has(GAMES[k]["id"]) and (k != _game or sites.sites.size() == 1):
			avail.append(k)
	var g: int = avail[r.randi() % avail.size()]
	var ids: Array = []
	for id in world.cars.keys():
		if is_instance_valid(world.cars[id]):
			ids.append(int(id))
	ids.sort()
	var msg := {"t": "start", "i": coin, "g": g, "s": r.randi() % 1000000, "by": by, "ids": ids}
	if world.online:
		Net.party_broadcast(msg)
	else:
		_on_start(msg)


func _on_msg(from_id: int, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"claim":
			if Net.is_host():
				_host_start(int(msg.get("i", -1)), from_id)
		"res":
			if Net.is_host() and state != "idle" and _ids.has(from_id):
				_results[from_id] = float(msg.get("v", 0.0))
				_host_check_final(false)
		"start":
			_on_start(msg)
		"final":
			_on_final(msg.get("rows", []))


func _host_check_final(force: bool) -> void:
	if state == "results" or state == "back" or state == "idle":
		return
	var all_in := true
	for id in _ids:
		if not _results.has(id) and world.cars.has(id) and is_instance_valid(world.cars[id]):
			all_in = false
	if not all_in and not force:
		return
	var rows: Array = []
	for id in _results:
		rows.append([int(id), float(_results[id])])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	if world.online:
		Net.party_broadcast({"t": "final", "rows": rows})
	else:
		_on_final(rows)


# ---------------------------------------------------------------------------
# Minigame flow (every machine)
# ---------------------------------------------------------------------------
func _on_start(msg: Dictionary) -> void:
	var coin := int(msg.get("i", 0))
	if coin >= 0 and coin < _coins.size():
		var c: Dictionary = _coins[coin]
		c["active"] = false
		c["gen"] = int(c["gen"]) + 1
		c["timer"] = COIN_RESPAWN
		(c["node"] as Node3D).visible = false
	games_played += 1
	_game = clampi(int(msg.get("g", 0)), 0, GAMES.size() - 1)
	_seed = int(msg.get("s", 0))
	_ids = msg.get("ids", [1])
	var me: int = Net.local_id() if world.online else 1
	_slot = maxi(_ids.find(me), 0)
	_results.clear()
	_value = 0.0
	_done = false
	var car = world.local_car
	_return_xf = car.global_transform
	car.controls_locked = true
	car.freeze = true
	state = "announce"
	_t = 0.0
	var by := int(msg.get("by", 1))
	var who := "Du hast" if by == me else "%s hat" % _name(by)
	_b_by.text = "%s eine Minispiel-Münze eingesammelt!" % who
	_b_title.text = "MINISPIEL %d / %d" % [games_played, games_total]
	_b_desc.text = ""
	_banner.visible = true
	_table.visible = false
	_update_info()


func _name(id: int) -> String:
	if world.cars.has(id) and is_instance_valid(world.cars[id]):
		return world.cars[id].player_name
	return "Spieler"


func _physics_process(delta: float) -> void:
	if world == null or not world.is_loaded:
		return
	_process_coins(delta)
	_status_t -= delta
	if _status_t <= 0.0 and _status.text != "" and state != "play":
		_status.text = ""
	if state == "idle":
		return
	_t += delta
	var g: Dictionary = GAMES[_game]
	match state:
		"announce":
			# roulette: names flicker, slowing down, then the drawn game stays
			var k := _t / (ANNOUNCE_TIME - 1.5)
			if k < 1.0:
				var idx := int(pow(k, 0.45) * 22.0) % GAMES.size()
				_b_game.text = GAMES[(idx + _game + 1) % GAMES.size()]["name"]
				_b_game.add_theme_color_override("font_color", UiKit.TEXT_DIM)
			else:
				_b_game.text = g["name"]
				_b_game.add_theme_color_override("font_color", UiKit.GOLD)
				_b_desc.text = g["desc"]
			if _t >= ANNOUNCE_TIME:
				_begin_travel()
		"travel":
			var left := COUNTDOWN_TIME - _t
			var step := int(ceil(left))
			if step >= 1 and step <= 3:
				world.hud.set_countdown(str(step), Color(1.0, 0.3, 0.2))
			if _t >= COUNTDOWN_TIME:
				world.hud.set_countdown("GO!", UiKit.GOOD)
				_banner.visible = false
				state = "play"
				_t = 0.0
				world.local_car.freeze = false
				world.local_car.controls_locked = false
		"play":
			_play(delta, g)
			if _t >= float(g["time"]) and not _done:
				_finish_local()
			if _done and not world.online:
				_results[1] = _value
				_host_check_final(true)
			elif world.online and Net.is_host() and _t >= float(g["time"]) + 8.0:
				_host_check_final(true)
		"results":
			if _t >= RESULTS_TIME:
				_begin_back()
		"back":
			var left2 := COUNTDOWN_TIME - _t
			var step2 := int(ceil(left2))
			if step2 >= 1 and step2 <= 3:
				world.hud.set_countdown(str(step2), Color(1.0, 0.3, 0.2))
			if _t >= COUNTDOWN_TIME:
				world.hud.set_countdown("GO!", UiKit.GOOD)
				world.local_car.freeze = false
				world.local_car.controls_locked = false
				state = "idle"
				_update_info()


func _begin_travel() -> void:
	var g: Dictionary = GAMES[_game]
	var id: String = g["id"]
	var car = world.local_car
	# the props of this minigame go up on its stretch of the track (and come down afterwards)
	sites.build_course(id)
	car.place(sites.start_xf(id, _slot, _ids.size()))
	car.freeze = true
	car.controls_locked = true
	car.gear = 1
	car.nitro = 1.0
	car.arena_kill_y = float(world.track.kill_y)
	car.respawn_fn = _respawn
	var grip := 0.9 if id == "parkour" else 1.0
	var sname := "dirt" if id == "parkour" else "asphalt"
	car.surface_override = func(_p: Vector3) -> Array: return [grip, sname]
	_checkpoint = 0.0
	_penalty = 0.0
	_yaw_acc = 0.0
	_last_yaw = car.global_rotation.y
	_red_since = -1.0
	_hint = -1
	if id == "rlgl":
		_make_rl_phases()
		sites.set_rlgl_light(0)
	if id == "koth":
		_zone = sites.koth_spot(_seed, 0)
		sites.place_zone(_zone)
	_b_desc.text = g["desc"]
	state = "travel"
	_t = 0.0
	world.hud.show_message(g["name"], "", UiKit.GOLD, 3.0)


func _respawn() -> Transform3D:
	var id: String = GAMES[_game]["id"]
	match id:
		"parkour":
			return sites.checkpoint_xf(_checkpoint)
		"koth":
			_penalty = 2.0
			var r := RandomNumberGenerator.new()
			r.randomize()
			return sites.start_xf("koth", r.randi() % 8, 8)
	return sites.start_xf(id, _slot, _ids.size())


func _finish_local() -> void:
	if _done:
		return
	_done = true
	var car = world.local_car
	var id: String = GAMES[_game]["id"]
	if id == "rlgl" or id == "parkour":
		# park at the finish until everybody is done
		car.controls_locked = true
	if world.online:
		Net.party_to_host({"t": "res", "v": _value})
	_status.text = "FERTIG – warte auf die anderen" if world.online else ""
	_status.add_theme_color_override("font_color", UiKit.TEXT)
	_status_t = 0.0


func _play(delta: float, g: Dictionary) -> void:
	var car = world.local_car
	var id: String = g["id"]
	var left := maxf(float(g["time"]) - _t, 0.0)
	var proj: Array = world.track.project(car.global_position, _hint)
	_hint = proj[0]
	# metres along this minigame's stretch of track
	var along := wrapf(float(proj[1]) - float(sites.sites[id]["p0"]), -float(world.track.length) * 0.5, float(world.track.length) * 0.5)
	var lateral := float(proj[2])
	_penalty = maxf(_penalty - delta, 0.0)
	match id:
		"rlgl":
			var green := _rl_green(_t)
			sites.set_rlgl_light(1 if green else 0)
			if not _done:
				_value = along - PartySites.RLGL_START
				if green:
					_red_since = -1.0
					_show_status("GRÜN – FAHR!", UiKit.GOOD)
				else:
					if _red_since < 0.0:
						_red_since = _t
					_show_status("ROT – STOPP!", UiKit.BAD)
					# a short reaction time, then any movement is caught
					if _t - _red_since > 0.45 and car.speed > 0.9:
						car.reset_to_track()
						car.freeze = true
						_hint = -1
						_penalty = 1.5
						_status_t = 1.5
						world.hud.show_message("ERWISCHT!", "Zurück zum Start", UiKit.BAD, 1.8)
				if _penalty <= 0.0 and car.freeze:
					car.freeze = false
				if along > sites.rlgl_finish():
					_value = 10000.0 - _t
					_finish_t = _t
					_finish_local()
					world.hud.show_message("IM ZIEL!", Game.format_time(_t), UiKit.GOLD, 2.5)
			_line.text = "%s   ·   %s" % [_clock(left), ("Ziel in %.2f s" % _finish_t) if _done else "%d m bis zum Ziel" % int(maxf(sites.rlgl_finish() - along, 0.0))]
		"parkour":
			if not _done:
				for cz in sites.pk_checkpoints():
					if along > float(cz) + 2.0 and float(cz) > _checkpoint:
						_checkpoint = cz
						world.hud.show_message("CHECKPOINT", "", UiKit.GOOD, 1.0)
				_value = along - PartySites.PK_START
				if along > sites.pk_finish():
					_value = 10000.0 - _t
					_finish_t = _t
					_finish_local()
					world.hud.show_message("IM ZIEL!", Game.format_time(_t), UiKit.GOLD, 2.5)
			_line.text = "%s   ·   %s" % [_clock(left), ("Ziel in %.2f s" % _finish_t) if _done else "%d m bis zum Ziel" % int(maxf(sites.pk_finish() - along, 0.0))]
		"koth":
			var step := int(_t / KOTH_STEP)
			_zone = _zone.lerp(sites.koth_spot(_seed, step), 1.0 - exp(-delta * 2.5))
			sites.place_zone(_zone)
			var inside := Vector2(along - _zone.x, lateral - _zone.y).length() < PartySites.KOTH_ZONE_R
			if inside and _penalty <= 0.0 and not _done:
				_value += delta
			_show_status("IN DER ZONE" if inside else "", UiKit.GOLD)
			_line.text = "%s   ·   %.1f s in der Zone" % [_clock(left), _value]
		"donut":
			var yaw: float = car.global_rotation.y
			var dy := wrapf(yaw - _last_yaw, -PI, PI)
			_last_yaw = yaw
			var spot: Transform3D = sites.start_xf("donut", _slot, _ids.size())
			if car.speed > 1.5 and car.global_position.distance_to(spot.origin) < PartySites.DONUT_R and not _done:
				_yaw_acc += dy
			_value = floorf(absf(_yaw_acc) / TAU)
			_line.text = "%s   ·   %d Donuts" % [_clock(left), int(_value)]


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _make_rl_phases() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = _seed
	_rl_phases.clear()
	var t := 0.0
	var green := true
	while t < 200.0:
		t += r.randf_range(2.0, 5.0) if green else r.randf_range(1.6, 3.4)
		_rl_phases.append([t, green])
		green = not green


func _rl_green(t: float) -> bool:
	for ph in _rl_phases:
		if t < float(ph[0]):
			return bool(ph[1])
	return true


func _on_final(rows: Array) -> void:
	if state == "results" or state == "back" or state == "idle":
		return
	if not _done:
		_finish_local()
	var g: Dictionary = GAMES[_game]
	var me: int = Net.local_id() if world.online else 1
	var my_rank := -1
	var list: Array = []
	for i in rows.size():
		var r: Array = rows[i]
		var id := int(r[0])
		var v := float(r[1])
		if id == me:
			my_rank = i
		list.append([i, _name(id), _fmt(g, v), id == me])
	if list.is_empty():
		list.append([0, world.local_car.player_name, _fmt(g, _value), true])
		my_rank = 0
	var credits: int = REWARDS[mini(maxi(my_rank, 0), REWARDS.size() - 1)]
	if not world.online:
		credits = 1500 if _value > 0.0 else 300
	Game.add_credits(credits)
	for c in _table.get_children():
		c.queue_free()
	_table.add_child(UiKit.label("ERGEBNIS – " + str(g["name"]).to_upper(), 26, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	for e in list:
		var col: Color = UiKit.GOLD if e[3] else UiKit.TEXT
		_table.add_child(UiKit.label("%d.   %s   –   %s" % [int(e[0]) + 1, e[1], e[2]], 22, col, HORIZONTAL_ALIGNMENT_CENTER))
	_table.add_child(UiKit.label("+%s Credits" % Game.format_points(credits), 20, UiKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	_table.visible = true
	_banner.visible = true
	_b_title.text = "MINISPIEL %d / %d" % [games_played, games_total]
	_b_game.text = g["name"]
	_b_desc.text = ""
	_b_by.text = "Gewonnen!" if my_rank == 0 and rows.size() > 1 else ""
	_status.text = ""
	_line.text = ""
	sites.set_rlgl_light(-1)
	world.local_car.controls_locked = true
	world.local_car.freeze = true
	state = "results"
	_t = 0.0


func _fmt(g: Dictionary, v: float) -> String:
	match str(g["id"]):
		"rlgl", "parkour":
			if v >= 5000.0:
				return "Ziel in %s" % Game.format_time(10000.0 - v)
			return "%d m weit" % int(v)
		"koth":
			return "%.1f s in der Zone" % v
	return "%d Donuts" % int(v)


func _begin_back() -> void:
	var car = world.local_car
	car.surface_override = Callable()
	car.respawn_fn = Callable()
	car.arena_kill_y = -1e9
	sites.clear_course()
	car.place(_return_xf)
	car.freeze = true
	car.controls_locked = true
	_banner.visible = false
	_table.visible = false
	world.hud.show_message("WEITER GEHT'S", "", Color.WHITE, 2.0)
	state = "back"
	_t = 0.0


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	_layer.add_child(root)
	_info = UiKit.label("", 16, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_info.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_info.position = Vector2(-200, 76)
	_info.size = Vector2(400, 24)
	root.add_child(_info)
	_line = UiKit.label("", 24, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_line.position = Vector2(-300, 104)
	_line.size = Vector2(600, 32)
	_line.add_theme_constant_override("outline_size", 8)
	_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(_line)
	_status = UiKit.label("", 64, UiKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_status.set_anchors_preset(Control.PRESET_CENTER)
	_status.position = Vector2(-400, -190)
	_status.size = Vector2(800, 80)
	_status.add_theme_font_override("font", UiKit.title_font())
	_status.add_theme_constant_override("outline_size", 14)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	root.add_child(_status)
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-330, -150)
	_banner.size = Vector2(660, 300)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_b_title = UiKit.label("", 18, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_b_game = UiKit.label("", 44, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_b_game.add_theme_font_override("font", UiKit.title_font())
	_b_desc = UiKit.label("", 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_b_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_desc.custom_minimum_size = Vector2(620, 0)
	_b_by = UiKit.label("", 17, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_table = VBoxContainer.new()
	_table.add_theme_constant_override("separation", 4)
	for c in [_b_title, _b_game, _b_desc, _b_by, _table]:
		box.add_child(c)
	_banner.add_child(box)
	_banner.visible = false
	root.add_child(_banner)


func _update_info() -> void:
	var left := games_total - games_played
	_info.text = ("★ PARTY: noch %d Minispiel%s – fahr durch eine Münze!" % [left, "" if left == 1 else "e"]) if left > 0 else "★ PARTY: alle Minispiele gespielt"
