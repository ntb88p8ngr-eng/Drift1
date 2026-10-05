extends Node3D
## Party mode: glowing minigame coins lie on the track. Whoever drives through one stops the race for
## everybody and a minigame is drawn: all cars are taken to its stretch of the track, where its props
## are put up for the time of the game (party_sites.gd), play it, get credits by rank and are put
## back where they were. Offline the local player plays
## alone; online the host referees (who got the coin first, which game, the final ranking).
## Flow per minigame: announce (roulette) -> travel (countdown on the stretch) -> play -> results -> back.

const PartySites = preload("res://scripts/world/party_sites.gd")
const Sfx = preload("res://scripts/util/sfx_kit.gd")
const PartyArena = preload("res://scripts/world/party_arena.gd")
const PartyBots = preload("res://scripts/world/party_bots.gd")
const Car = preload("res://scripts/car/car.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const GAMES := [
	{"id": "rlgl", "name": "Rotes Licht, Grünes Licht", "time": 90.0, "unit": "m",
		"desc": "Fahr ins Ziel – aber bei ROT musst du stillstehen! Wer sich bei Rot bewegt, muss zurück zum Start."},
	{"id": "parkour", "name": "Offroad-Parkour", "time": 120.0, "unit": "m",
		"desc": "Hochgelegt durch Schlamm, Reifenstapel, kreuz und quer liegende Baumstämme, Planken-Schanzen und eine Stamm-Schikane: zuerst im Ziel gewinnt. [R] = zurück zum letzten Checkpoint."},
	{"id": "koth", "name": "König der Zone", "time": 60.0, "unit": "s",
		"desc": "Bleib in der leuchtenden Zone – sie wandert alle 10 Sekunden über die Straße. Schubs die anderen raus!"},
	{"id": "donut", "name": "Donut-Duell", "time": 30.0, "unit": "x",
		"desc": "Dreh so viele Donuts wie möglich – jede volle Drehung zählt. 30 Sekunden!"},
	{"id": "bowling", "name": "Auto-Bowling", "time": 32.0, "unit": "x",
		"desc": "Zwei Würfe auf zehn Riesen-Kegel: Nimm Anlauf und ziel gut – ab der roten Linie rollst du ohne Gas und Lenkung weiter!"},
	{"id": "arena", "name": "Arena-Shootout", "time": 75.0, "unit": "x",
		"desc": "Schieß die anderen ab! [F] / Linksklick / (X) = Feuer, 3 Treffer = raus. Münzen geben Dreifach-Schuss oder Schnellfeuer. Allein kämpfst du gegen Bots."},
	{"id": "balloon", "name": "Ballon-Schlacht", "time": 120.0, "unit": "x",
		"desc": "Jedes Auto hat 3 Ballons – schieß sie den anderen ab! [F] / Linksklick / (X) = Feuer. Ohne Ballons bist du raus, wer am längsten durchhält, gewinnt. Münzen: Dreifach-Schuss / Schnellfeuer."},
]
const ANNOUNCE_TIME := 4.5
const COUNTDOWN_TIME := 3.5
const RESULTS_TIME := 6.0
const COIN_RESPAWN := 20.0
const REWARDS := [2500, 1200, 600, 300]
const KOTH_STEP := 10.0
const CHOOSE_TIME := 12.0
const PARKOUR_LIFT := 0.32
const THROW_TIME := 10.0

var world: Node3D
var sites: PartySites
var games_total := 3
var games_played := 0
var coin_count := 5
## Neo Tokyo: coins on all the city's streets (setting), otherwise only on the race route
var spread_city := false
var seed_base := 0

var state := "idle"          # idle, announce, travel, play, wait, results, back
var _t := 0.0
var _game := -1              # index into GAMES
var _seed := 0
var _slot := 0
var _ids: Array = []         # participants (peer ids) of the current minigame
var _return_xf := Transform3D.IDENTITY
var _coin := -1
var _chooser := 1            # peer who took the coin (picks the minigame online)
var _picked := false
var _skip_roulette := false
var _choices: VBoxContainer
var _pin := false
var _pin_xf := Transform3D.IDENTITY
var _coins: Array = []       # {node, gen, active, timer}
var _value := 0.0            # local score of the current minigame (higher is better)
var _done := false
var _finish_t := 0.0
var _results := {}           # host: peer id -> value
var _checkpoint := -104.0
var _rl_phases: Array = []   # red light green light: [end time, green?]
var _red_since := -1.0
var _rl_last := -1
const RL_YELLOW := 0.9      # seconds of yellow at the end of every green phase
const RL_SAFE := 12.0       # metres before the finish line where moving on red is not caught
var _penalty := 0.0
var _yaw_acc := 0.0
var _last_yaw := 0.0
var _hint := -1              # track sample near the car (for projecting)
var _zone := Vector2.ZERO     # king of the zone: current spot (along, lateral)
var _coin_mat: StandardMaterial3D
var _pins: Array = []        # bowling
var _throw := 0
var _throw_t := 0.0
var _bowl_phase := ""        # roll, settle, reset
var _arena: PartyArena
var _pbots: PartyBots          # offline: the race's bots playing along
var _mask_before := 0

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
	spread_city = bool(cfg.get("party_coins_city", false))
	seed_base = int(cfg.get("weather_seed", 1)) * 7919 + 17


func _ready() -> void:
	_build_ui()
	_make_coins()
	if world.online:
		Net.party_msg.connect(_on_msg)
	_update_info()


## True while a minigame holds up the race (the world stops its clock and lap counting).
## The race's bots are out on a minigame course (the world does not park them then).
func bots_on_course() -> bool:
	return _pbots != null and _pbots.on_course()


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
	return root


## Deterministic coin spot (the same on every machine): coin i, generation gen.
func _place_coin(i: int) -> void:
	var c: Dictionary = _coins[i]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_base, i, int(c["gen"])])
	var tr = world.track
	var n: int = tr.sample_count()
	var net = _city_net()
	if net != null and not net.streets.is_empty() and r.randf() < 0.75:
		# out in the city: somewhere along a random street (the same street net on every machine)
		var s: Dictionary = net.streets[r.randi() % net.streets.size()]
		var pts: PackedVector2Array = s["pts"]
		if pts.size() >= 2:
			var j := r.randi() % (pts.size() - 1)
			var q := pts[j].lerp(pts[j + 1], r.randf())
			var t := (pts[j + 1] - pts[j]).normalized()
			q += Vector2(-t.y, t.x) * r.randf_range(-0.25, 0.25) * float(s["w"])
			(c["node"] as Node3D).global_position = Vector3(q.x, 1.3, q.y)
			(c["node"] as Node3D).visible = bool(c["active"])
			return
	# spread the coins around the lap, away from the start line
	var base := (float(i) + r.randf_range(0.15, 0.85)) / float(coin_count)
	var idx := int(base * n) % n
	var lat := r.randf_range(-1.0, 1.0) * (float(tr.half_w) - 2.5)
	var xf: Transform3D = tr.transform_at(idx, lat, 1.3)
	(c["node"] as Node3D).global_position = xf.origin
	(c["node"] as Node3D).visible = bool(c["active"])


## The city's street net when the coins may go all over Neo Tokyo, else null.
func _city_net():
	if not spread_city or not Game.is_city(str(world.track.track_id)):
		return null
	var sc = world.get("scenery")
	if sc == null or sc.city == null:
		return null
	return sc.city.net


## The HUD's mission compass points at the nearest coin while one can be taken.
func _coin_compass(can_take: bool) -> void:
	if world.hud == null:
		return
	var best = null
	var bd := 1e18
	if can_take:
		var p: Vector3 = world.local_car.global_position
		for c in _coins:
			if bool(c["active"]):
				var q: Vector3 = (c["node"] as Node3D).global_position
				var d := p.distance_squared_to(q)
				if d < bd:
					bd = d
					best = q
	if best == null:
		world.hud.clear_mission()
	else:
		world.hud.set_mission(best, "MÜNZE")


func _process_coins(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_coin_mat.emission_energy_multiplier = 1.3 + 0.6 * sin(t * 3.0)
	var can_take: bool = state == "idle" and games_played < games_total and world.state == "running" and not world.finished
	_coin_compass(can_take)
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
	if world.online:
		# multiplayer: whoever took the coin picks the minigame (random if they don't within the time)
		Net.party_broadcast({"t": "choose", "i": coin, "by": by, "ids": ids})
		return
	_on_start({"t": "start", "i": coin, "g": g, "s": r.randi() % 1000000, "by": by, "ids": ids})


## Host: the minigame is decided (picked by the collector, or at random when the time is up).
func _host_decide(g: int) -> void:
	if state != "choose" or not sites.sites.has(GAMES[clampi(g, 0, GAMES.size() - 1)]["id"]):
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_base, games_played, Time.get_ticks_usec()])
	Net.party_broadcast({"t": "start", "i": _coin, "g": clampi(g, 0, GAMES.size() - 1), "s": r.randi() % 1000000, "by": _chooser, "ids": _ids})


func _available_games() -> Array:
	var out: Array = []
	for k in GAMES.size():
		if sites.sites.has(GAMES[k]["id"]):
			out.append(k)
	return out


func _on_msg(from_id: int, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"claim":
			if Net.is_host():
				_host_start(int(msg.get("i", -1)), from_id)
		"res":
			if Net.is_host() and state != "idle" and _ids.has(from_id):
				_results[from_id] = float(msg.get("v", 0.0))
				_host_check_final(false)
		"choose":
			_on_choose(msg)
		"pick":
			if Net.is_host() and from_id == _chooser:
				_host_decide(int(msg.get("g", -1)))
		"start":
			_on_start(msg)
		"final":
			_on_final(msg.get("rows", []))
		"ar":
			# arena events: every machine sends them to the host, the host passes them on to all
			if Net.is_host() and not msg.has("p"):
				msg["p"] = from_id
				Net.party_broadcast(msg)
			elif msg.has("p") and _arena:
				_arena.on_msg(int(msg["p"]), msg)


func _host_check_final(force: bool) -> void:
	if state == "results" or state == "back" or state == "idle":
		return
	var all_in := true
	for id in _ids:
		if not _results.has(id) and world.cars.has(id) and is_instance_valid(world.cars[id]):
			all_in = false
	if not all_in and not force:
		return
	if _arena:
		for bid in _arena.bot_ids():
			_results[bid] = _arena.score(bid)
	if _pbots:
		var br := _pbots.results()
		for bid in br:
			_results[bid] = br[bid]
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
## The race stops for everybody: coin bookkeeping, cars held, where to come back to.
func _stop_race(msg: Dictionary) -> void:
	var coin := int(msg.get("i", 0))
	_coin = coin
	if coin >= 0 and coin < _coins.size():
		var c: Dictionary = _coins[coin]
		c["active"] = false
		c["gen"] = int(c["gen"]) + 1
		c["timer"] = COIN_RESPAWN
		(c["node"] as Node3D).visible = false
	games_played += 1
	_ids = msg.get("ids", [1])
	var me: int = Net.local_id() if world.online else 1
	_slot = maxi(_ids.find(me), 0)
	_results.clear()
	_value = 0.0
	_done = false
	var car = world.local_car
	# back to the track later: level, on the road where the coin was, facing the race direction
	var proj: Array = world.track.project(car.global_position, car.track_hint)
	var lat := clampf(float(proj[2]), -float(world.track.half_w) + 2.5, float(world.track.half_w) - 2.5)
	_return_xf = world.track.transform_at(int(proj[0]), lat, 0.6)
	car.controls_locked = true
	_hold(car.global_transform)
	_t = 0.0
	var by := int(msg.get("by", 1))
	_chooser = by
	var who := "Du hast" if by == me else Game.t("%s hat") % _name(by)
	_b_by.text = Game.t("%s eine Minispiel-Münze eingesammelt!") % who
	_b_title.text = Game.t("MINISPIEL %d / %d") % [games_played, games_total]
	_b_desc.text = ""
	_banner.visible = true
	_table.visible = false
	_update_info()


## Multiplayer: the race stops and the collector picks the minigame.
func _on_choose(msg: Dictionary) -> void:
	if state != "idle":
		return
	_stop_race(msg)
	state = "choose"
	var me: int = Net.local_id()
	_b_game.add_theme_color_override("font_color", UiKit.GOLD)
	for c in _choices.get_children():
		c.queue_free()
	if _chooser == me:
		_b_game.text = "Wähle ein Minispiel!"
		_b_desc.text = Game.t("Klicken, Taste 1–%d oder Steuerkreuz + (A)") % _available_games().size()
		var n := 1
		for k in _available_games():
			var gk: int = k
			var b := UiKit.button("%d  %s" % [n, GAMES[gk]["name"]], func(): _pick(gk), 300)
			b.tooltip_text = GAMES[gk]["desc"]
			_choices.add_child(b)
			n += 1
		_choices.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# gamepad / keyboard: the first game is selected, d-pad / stick moves, (A) / Enter picks
		var first: Button = _choices.get_child(0) if _choices.get_child_count() > 0 else null
		if first:
			first.grab_focus.call_deferred()
	else:
		_b_game.text = Game.t("%s wählt ein Minispiel …") % _name(_chooser)
		_b_desc.text = ""
		_choices.visible = false


func _pick(g: int) -> void:
	if state != "choose" or _picked:
		return
	_picked = true
	_choices.visible = false
	_b_game.text = GAMES[g]["name"]
	_b_desc.text = "Warte auf den Start …"
	Net.party_to_host({"t": "pick", "g": g})


func _unhandled_input(event: InputEvent) -> void:
	# number keys pick the minigame (for the collector)
	if state != "choose" or _picked or not (event is InputEventKey) or not event.pressed:
		return
	if _chooser != Net.local_id():
		return
	var k: int = (event as InputEventKey).keycode - KEY_1
	var avail := _available_games()
	if k >= 0 and k < avail.size():
		_pick(avail[k])
		get_viewport().set_input_as_handled()


func _on_start(msg: Dictionary) -> void:
	if state == "idle":
		_stop_race(msg)
	elif state != "choose":
		return
	_game = clampi(int(msg.get("g", 0)), 0, GAMES.size() - 1)
	_seed = int(msg.get("s", 0))
	# a picked game is shown straight away, the offline draw spins the roulette
	_skip_roulette = state == "choose"
	_choices.visible = false
	_picked = false
	state = "announce"
	_t = 0.0


## Holds the car still at xf (placed again every physics step, so it neither rolls nor keeps any
## speed – freezing the body brought the old velocity back when released and flung the car).
func _hold(xf: Transform3D) -> void:
	_pin = true
	_pin_xf = xf
	world.local_car.place(xf)


func _release() -> void:
	if _pin:
		world.local_car.place(_pin_xf)
	_pin = false


func _name(id: int) -> String:
	if id < 0 and _arena:
		return _arena.bot_name(id)
	if world.cars.has(id) and is_instance_valid(world.cars[id]):
		return world.cars[id].player_name
	return "Spieler"


func _physics_process(delta: float) -> void:
	if world == null or not world.is_loaded:
		return
	_process_coins(delta)
	if _pin:
		world.local_car.place(_pin_xf)
	_status_t -= delta
	if _status_t <= 0.0 and _status.text != "" and state != "play":
		_status.text = ""
	if state == "idle":
		return
	_t += delta
	var g: Dictionary = GAMES[_game]
	match state:
		"choose":
			# host: nobody picked in time -> random
			if Net.is_host() and _t >= CHOOSE_TIME:
				var avail := _available_games()
				_host_decide(avail[randi() % avail.size()])
			elif _chooser != Net.local_id():
				_b_desc.text = Game.t("noch %d s") % int(ceil(maxf(CHOOSE_TIME - _t, 0.0)))
		"announce":
			# roulette: names flicker, slowing down, then the drawn game stays
			var k := _t / (ANNOUNCE_TIME - 1.5)
			if _skip_roulette:
				k = 1.0
			if k < 1.0:
				var idx := int(pow(k, 0.45) * 22.0) % GAMES.size()
				_b_game.text = GAMES[(idx + _game + 1) % GAMES.size()]["name"]
				_b_game.add_theme_color_override("font_color", UiKit.TEXT_DIM)
			else:
				_b_game.text = g["name"]
				_b_game.add_theme_color_override("font_color", UiKit.GOLD)
				_b_desc.text = g["desc"]
			if _t >= (2.5 if _skip_roulette else ANNOUNCE_TIME):
				_begin_travel()
		"travel":
			if _pbots:
				_pbots.step(delta, _t)       # (held on the grid)
			var left := COUNTDOWN_TIME - _t
			var step := int(ceil(left))
			if step >= 1 and step <= 3:
				world.hud.set_countdown(str(step), Color(1.0, 0.3, 0.2))
			if _t >= COUNTDOWN_TIME:
				world.hud.set_countdown("GO!", UiKit.GOOD)
				_banner.visible = false
				state = "play"
				_t = 0.0
				_release()
				world.local_car.controls_locked = false
				if _pbots:
					_pbots.go()
		"play":
			_play(delta, g)
			if _pbots:
				_pbots.step(delta, _t)
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
				_release()
				world.local_car.controls_locked = false
				state = "idle"
				_update_info()


func _begin_travel() -> void:
	var g: Dictionary = GAMES[_game]
	var id: String = g["id"]
	var car = world.local_car
	# the props of this minigame go up on its stretch of the track (and come down afterwards);
	# the parkour: one of its five courses, the same everywhere (from the shared seed)
	if id == "parkour":
		sites.pk_variant = posmod(_seed, sites.PK_VARIANTS.size())
	# the shoot-out alone with the race's bots: they all come along – with more than four cars it is
	# fought on the long stretch (the balloon battle's) instead of the short arena
	var site := id
	var arena_bots: Array = []
	if (id == "arena" or id == "balloon") and not world.online:
		for bid in world._bot_ids:
			if world.cars.has(bid) and is_instance_valid(world.cars[bid]):
				arena_bots.append(world.cars[bid])
		if id == "arena" and arena_bots.size() + 1 > 4 and sites.sites.has("balloon"):
			site = "balloon"
	sites.build_course(site)
	_hold(sites.start_xf(site, _slot, _ids.size()))
	car.controls_locked = true
	car.gear = 1
	car.nitro = 1.0
	car.arena_kill_y = float(world.track.kill_y)
	car.respawn_fn = _respawn
	if id == "parkour":
		# offroad: lifted, loose dirt, less grip still in the mud patches
		car.set_lift(PARKOUR_LIFT)
		car.surface_override = func(p: Vector3) -> Array: return [0.6, "dirt"] if sites.in_mud(p) else [0.84, "dirt"]
	else:
		car.surface_override = func(_p: Vector3) -> Array: return [1.0, "asphalt"]
	_mask_before = car.collision_mask
	if id == "bowling":
		# everybody bowls from the same spot on their own pins: the others are ghosts here
		car.collision_mask &= ~Car.LAYER_REMOTE
		_pins = sites.make_pins()
		_throw = 0
		_throw_t = 0.0
		_bowl_phase = "roll"
	if id == "arena" or id == "balloon":
		car.collision_mask |= Car.LAYER_REMOTE
		_arena = PartyArena.new()
		_arena.name = "Arena"
		_arena.mode = "balloon" if id == "balloon" else "shoot"
		for b in arena_bots.slice(0, 7):
			_arena.bot_names.append(str(b.player_name))
			_arena.bot_cars.append(str(b.car_id))
		add_child(_arena)
		var me: int = Net.local_id() if world.online else 1
		# offline the race's bots fight as the arena's own bots (copies of them), not parked
		_arena.setup(self, world, sites, _seed, _ids if world.online else [me], me)
	# offline: the race's bots play along (rlgl, parkour, koth, donut: on the course; bowling: counted)
	if not world.online and world.race_ai and PartyBots.plays(id):
		_pbots = PartyBots.new()
		_pbots.name = "PartyBots"
		add_child(_pbots)
		_pbots.setup(self, world, sites, id, _ids, _seed)
	_checkpoint = 0.0
	_penalty = 0.0
	_yaw_acc = 0.0
	_last_yaw = car.global_rotation.y
	_red_since = -1.0
	_rl_last = -1
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
		"arena", "balloon":
			if _arena:
				return _arena._spawn_xf()
	return sites.start_xf(id, _slot, _ids.size())


func _finish_local() -> void:
	if _done:
		return
	_done = true
	_pin = false      # a finisher is never held back at the start again
	_penalty = 0.0
	var car = world.local_car
	var id: String = GAMES[_game]["id"]
	if id == "rlgl" or id == "parkour" or id == "bowling":
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
			# the traffic lights say it all (no text): green, yellow for the last second, red –
			# with soft chimes: rising on green, one note on yellow, falling on red
			var light := _rl_light(_t)
			sites.set_rlgl_light(light)
			if light != _rl_last:
				if light == 1:
					Sfx.play(self, "light_go", -15.0)
				elif light == 2:
					Sfx.play(self, "light_warn", -19.0)
				elif light == 0:
					Sfx.play(self, "light_stop", -15.0)
				_rl_last = light
			if not _done:
				_value = along - PartySites.RLGL_START
				# over the line counts first – also when the light turns red at that moment
				if along > sites.rlgl_finish():
					_value = 10000.0 - _t
					_finish_t = _t
					_finish_local()
					Sfx.play(self, "light_go", -12.0, null, 1.25)
					world.hud.show_message("IM ZIEL!", Game.format_time(_t), UiKit.GOLD, 2.5)
				elif light == 0:
					if _red_since < 0.0:
						_red_since = _t
					# a short reaction time, then any movement is caught
					# … except right before the line: nobody stops from speed in a few metres
					if _t - _red_since > 0.45 and car.speed > 0.9 and along < sites.rlgl_finish() - RL_SAFE:
						_hold(sites.start_xf(id, _slot, _ids.size()))
						_hint = -1
						_penalty = 1.5
						Sfx.play(self, "whistle", -10.0)
						world.hud.show_message("ERWISCHT!", "Zurück zum Start", UiKit.BAD, 1.8)
				else:
					_red_since = -1.0
				if not _done and _penalty <= 0.0 and _pin:
					_release()
			_line.text = "%s   ·   %s" % [_clock(left), (Game.t("Ziel in %.2f s") % _finish_t) if _done else Game.t("%d m bis zum Ziel") % int(maxf(sites.rlgl_finish() - along, 0.0))]
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
			_line.text = "%s   ·   %s" % [_clock(left), (Game.t("Ziel in %.2f s") % _finish_t) if _done else Game.t("%d m bis zum Ziel") % int(maxf(sites.pk_finish() - along, 0.0))]
		"koth":
			var step := int(_t / KOTH_STEP)
			_zone = _zone.lerp(sites.koth_spot(_seed, step), 1.0 - exp(-delta * 2.5))
			sites.place_zone(_zone)
			var inside := Vector2(along - _zone.x, lateral - _zone.y).length() < PartySites.KOTH_ZONE_R
			if inside and _penalty <= 0.0 and not _done:
				_value += delta
			_show_status("IN DER ZONE" if inside else "", UiKit.GOLD)
			_line.text = Game.t("%s   ·   %.1f s in der Zone") % [_clock(left), _value]
		"bowling":
			_play_bowling(delta, car, along, left)
		"balloon":
			if _arena:
				_arena.step(delta)
				var fb: Dictionary = _arena.fighters.get(_arena.me, {})
				if not _done and not fb.is_empty():
					_value = _arena.score(_arena.me)
					if _arena.balloon_over():
						_finish_local()
				var alive := 0
				for fid in _arena.fighters:
					if not bool(_arena.fighters[fid]["out"]):
						alive += 1
				var n := int(fb.get("hp", 0))
				var bal := ("● ".repeat(n).strip_edges() if n > 0 else "RAUS")
				var pw2 := ""
				if str(fb.get("power", "")) != "":
					pw2 = "   ·   %s %d s" % ["3× SCHUSS" if fb["power"] == "triple" else "⚡ SCHNELLFEUER", int(ceil(float(fb["power_t"])))]
				_line.text = Game.t("%s   ·   %s   ·   %d geplatzt   ·   noch %d im Spiel%s") % [_clock(left), bal, int(fb.get("kills", 0)), alive, pw2]
				_show_status(_arena.feed if _arena.feed_t > 0.0 else "", UiKit.TEXT)
				_status.add_theme_font_size_override("font_size", 30)
		"arena":
			if _arena:
				_arena.step(delta)
				var f: Dictionary = _arena.fighters.get(_arena.me, {})
				if not _done and not f.is_empty():
					_value = _arena.score(_arena.me)
				var hp := int(f.get("hp", 0))
				var hearts := "♥".repeat(maxi(hp, 0)) + "♡".repeat(maxi(PartyArena.MAX_HP - hp, 0))
				var pw := ""
				if str(f.get("power", "")) != "":
					pw = "   ·   %s %d s" % ["3× SCHUSS" if f["power"] == "triple" else "⚡ SCHNELLFEUER", int(ceil(float(f["power_t"])))]
				_line.text = Game.t("%s   ·   %s   ·   %d Abschüsse%s") % [_clock(left), hearts, int(_value), pw]
				_show_status(_arena.feed if _arena.feed_t > 0.0 else "", UiKit.TEXT)
				_status.add_theme_font_size_override("font_size", 30)
		"donut":
			var yaw: float = car.global_rotation.y
			var dy := wrapf(yaw - _last_yaw, -PI, PI)
			_last_yaw = yaw
			var spot: Transform3D = sites.start_xf("donut", _slot, _ids.size())
			if car.speed > 1.5 and car.global_position.distance_to(spot.origin) < PartySites.DONUT_R and not _done:
				_yaw_acc += dy
			_value = floorf(absf(_yaw_acc) / TAU)
			_line.text = Game.t("%s   ·   %d Donuts") % [_clock(left), int(_value)]


## Bowling: two throws. Take a run-up; past the red foul line the car only rolls (no gas, no steering).
func _play_bowling(delta: float, car, along: float, left: float) -> void:
	_throw_t += delta
	var down := PartySites.pins_down(_pins)
	match _bowl_phase:
		"roll":
			if along > sites.bowl_foul() and car.input_enabled:
				car.input_enabled = false
			var past := along > sites.bowl_pins_along() + 20.0
			var stopped: bool = along > sites.bowl_foul() and car.speed < 0.8 and _throw_t > 2.0
			if (_throw_t > THROW_TIME or past or stopped or down == _pins.size()) and not _done:
				_bowl_phase = "settle"
				_throw_t = 0.0
		"settle":
			# let the pins finish falling, then count
			if _throw_t > 1.8 and not _done:
				_value += down
				var strike := down == _pins.size()
				world.hud.show_message("STRIKE!" if strike else "%d KEGEL" % down, Game.t("Wurf %d / 2") % (_throw + 1), UiKit.GOLD, 1.8)
				car.input_enabled = true
				_throw += 1
				if _throw >= 2:
					_finish_local()
				else:
					_bowl_phase = "reset"
					_throw_t = 0.0
					PartySites.reset_pins(_pins)
					_hold(sites.start_xf("bowling", _slot, _ids.size()))
					car.controls_locked = true
		"reset":
			if _throw_t > 1.5:
				_release()
				car.controls_locked = false
				_bowl_phase = "roll"
				_throw_t = 0.0
	var now := down if _bowl_phase != "reset" else 0
	_line.text = Game.t("%s   ·   Wurf %d / 2   ·   %d Kegel (gesamt %d)") % [_clock(left), mini(_throw + 1, 2), now, int(_value)]


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


## 1 green, 2 yellow (the last second of a green phase), 0 red.
func _rl_light(t: float) -> int:
	for ph in _rl_phases:
		if t < float(ph[0]):
			if not bool(ph[1]):
				return 0
			return 2 if float(ph[0]) - t < RL_YELLOW else 1
	return 1


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
	if not world.online and rows.size() <= 1:
		credits = 1500 if _value > 0.0 else 300
	Game.add_credits(credits)
	for c in _table.get_children():
		c.queue_free()
	_table.add_child(UiKit.label(Game.t("ERGEBNIS – ") + str(g["name"]).to_upper(), 26, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	for e in list:
		var col: Color = UiKit.GOLD if e[3] else UiKit.TEXT
		_table.add_child(UiKit.label("%d.   %s   –   %s" % [int(e[0]) + 1, e[1], e[2]], 22, col, HORIZONTAL_ALIGNMENT_CENTER))
	_table.add_child(UiKit.label(Game.t("+%s Credits") % Game.format_points(credits), 20, UiKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	_table.visible = true
	_banner.visible = true
	_b_title.text = Game.t("MINISPIEL %d / %d") % [games_played, games_total]
	_b_game.text = g["name"]
	_b_desc.text = ""
	_b_by.text = "Gewonnen!" if my_rank == 0 and rows.size() > 1 else ""
	_status.text = ""
	_line.text = ""
	sites.set_rlgl_light(-1)
	if _arena:
		_arena.frozen = true
	if _pbots:
		_pbots.stop()
	world.local_car.input_enabled = true
	world.local_car.controls_locked = true
	_hold(world.local_car.global_transform)
	state = "results"
	_t = 0.0


func _fmt(g: Dictionary, v: float) -> String:
	match str(g["id"]):
		"rlgl", "parkour":
			if v >= 5000.0:
				return Game.t("Ziel in %s") % Game.format_time(10000.0 - v)
			return Game.t("%d m weit") % int(v)
		"koth":
			return Game.t("%.1f s in der Zone") % v
		"bowling":
			return Game.t("%d Kegel") % int(v)
		"arena":
			return Game.t("%d Abschüsse (%d Treffer)") % [int(v), int(round(fmod(v, 1.0) * 100.0))]
		"balloon":
			var pops := int(round(fmod(v, 1.0) * 10.0))
			if v >= 1000.0:
				var left_b := int((v - 1000.0) / 100.0)
				return Game.t("überlebt mit %d Ballon%s · %d geplatzt") % [left_b, "" if left_b == 1 else "s", pops]
			return Game.t("raus nach %d s · %d geplatzt") % [int(v), pops]
	return Game.t("%d Donuts") % int(v)


func _begin_back() -> void:
	var car = world.local_car
	car.surface_override = Callable()
	car.respawn_fn = Callable()
	car.arena_kill_y = -1e9
	car.set_lift(0.0)
	car.input_enabled = true
	car.collision_mask = _mask_before if _mask_before != 0 else car.collision_mask
	_mask_before = 0
	if _arena:
		_arena.cleanup()
		_arena.queue_free()
		_arena = null
	_pins = []
	if _pbots:
		_pbots.finish()
		_pbots.queue_free()
		_pbots = null
	_status.remove_theme_font_size_override("font_size")
	sites.clear_course()
	_hold(_return_xf)
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
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	_choices.alignment = BoxContainer.ALIGNMENT_CENTER
	_choices.visible = false
	for c in [_b_title, _b_game, _b_desc, _b_by, _choices, _table]:
		box.add_child(c)
	_banner.add_child(box)
	_banner.visible = false
	root.add_child(_banner)


func _update_info() -> void:
	var left := games_total - games_played
	_info.text = (Game.t("★ PARTY: noch %d Minispiel%s – fahr durch eine Münze!") % [left, "" if left == 1 else "e"]) if left > 0 else "★ PARTY: alle Minispiele gespielt"
