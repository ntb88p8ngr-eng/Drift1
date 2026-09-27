extends Node3D
## One race session: builds environment, track and scenery, spawns cars, runs countdown, laps,
## drift scoring, results and leaderboard submission. Works offline and online.

signal exit_requested(target: String)   # "menu", "lobby", "restart", "leave"

const Track = preload("res://scripts/world/track.gd")
const Scenery = preload("res://scripts/world/scenery.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Atmosphere = preload("res://scripts/world/atmosphere.gd")
const Grass = preload("res://scripts/world/grass.gd")
const LensFlare = preload("res://scripts/world/lens_flare.gd")
const TreeFactory = preload("res://scripts/world/tree_factory.gd")
const Skidmarks = preload("res://scripts/world/skidmarks.gd")
const DriftScorer = preload("res://scripts/world/drift_scorer.gd")
const Car = preload("res://scripts/car/car.gd")
const CameraRig = preload("res://scripts/car/camera_rig.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const ShaderWarmup = preload("res://scripts/world/shader_warmup.gd")

const SECTORS := 8

var config := {}
var mode := "free"
var laps_total := 3
var online := false
var track: Track
var scenery: Scenery
var terrain: Terrain
var atmosphere: Atmosphere
var grass: Grass
var flares: LensFlare
var skidmarks: Skidmarks
var local_car: Car
var cars := {}              # peer_id -> Car
var camera: CameraRig
var hud: Hud
var pause_menu: PauseMenu
var scorer: DriftScorer

var state := "loading"      # loading, waiting, countdown, running, finished
var race_time := 0.0
var countdown := 0.0
var lap := 0
var lap_start := 0.0
var crossed_start := false
var best_lap := 0.0
var last_lap := 0.0
var lap_times: Array = []
var finished := false
var finish_time := 0.0
var progress := 0.0
var _last_prog := -1.0
var _sector_mask := 0
var _net_timer := 0.0
var _wait_timeout := 15.0
var _last_count_step := -1
var _session_saved := false
var _finish_order: Array = []
var _auto_lights := false


func setup(cfg: Dictionary) -> void:
	config = cfg


func _ready() -> void:
	mode = config.get("mode", "free")
	laps_total = int(config.get("laps", 3))
	online = bool(config.get("online", false))
	var quality := Game.quality()
	var t0 := Time.get_ticks_msec()
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	atmosphere.setup(config, quality)
	track = Track.new()
	track.name = "Track"
	add_child(track)
	track.build(config.get("track", "ridge"))
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(track)
	var t1 := Time.get_ticks_msec()
	scenery = Scenery.new()
	scenery.name = "Scenery"
	add_child(scenery)
	scenery.build(track, terrain, atmosphere.night, quality)
	var t2 := Time.get_ticks_msec()
	terrain.build_meshes()
	atmosphere.track = track
	atmosphere.materials_wet = [terrain.material]
	for key in ["leaf", "needle", "fern", "rock"]:
		atmosphere.materials_wet.append(TreeFactory._material(key))
	atmosphere.night_changed.connect(_on_night_changed)
	grass = Grass.new()
	grass.name = "Grass"
	add_child(grass)
	grass.setup(terrain, track, self)
	flares = LensFlare.new()
	flares.name = "LensFlares"
	add_child(flares)
	flares.setup(atmosphere)
	print("WORLD: terrain %d ms, scenery %d ms, meshes+grass %d ms (%s)" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2, scenery.stats_text() + (", " + scenery.details.stats_text() if scenery.details else "")])
	skidmarks = Skidmarks.new()
	skidmarks.name = "Skidmarks"
	add_child(skidmarks)
	_spawn_cars()
	camera = CameraRig.new()
	camera.name = "Camera"
	camera.car = local_car
	add_child(camera)
	_warmup.call_deferred()
	scorer = DriftScorer.new()
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.world = self
	add_child(pause_menu)
	local_car.wall_hit.connect(_on_wall_hit)

	if online:
		Net.remote_state.connect(_on_remote_state)
		Net.peer_left.connect(_on_peer_left)
		Net.countdown_requested.connect(_start_countdown)
		Net.results_updated.connect(_on_results_updated)
		Net.lobby_changed.connect(_on_lobby_changed)
		state = "waiting"
		local_car.controls_locked = true
		hud.set_countdown("…")
		hud.show_message("Warte auf andere Spieler", "", Color.WHITE, 30.0)
		Net.notify_loaded()
	elif mode == "free":
		state = "running"
		hud.show_message(Game.track_name(track.track_id), "Freies Driften – überquere die Startlinie, um die Zeitmessung zu starten", Color.WHITE, 4.0)
	else:
		_start_countdown()


func _spawn_cars() -> void:
	var night: float = atmosphere.night
	if online:
		var players: Dictionary = config.get("players", {})
		var ids: Array = players.keys()
		ids.sort()
		var me := Net.local_id()
		for slot in ids.size():
			var id: int = ids[slot]
			var info: Dictionary = players[id]
			var car := _make_car(info, id != me)
			car.peer_id = id
			cars[id] = car
			car.place(track.grid_transform(slot))
			if id == me:
				local_car = car
		if local_car == null:
			# should not happen – fall back to a local car so the game keeps working
			local_car = _make_car(Game.local_player_info(), false)
			local_car.place(track.grid_transform(ids.size()))
			cars[me] = local_car
	else:
		local_car = _make_car(Game.local_player_info(), false)
		cars[1] = local_car
		local_car.place(track.grid_transform(0))
	local_car.transmission = str(Game.settings.get("transmission", "auto"))
	local_car.headlights = night >= 0.4
	_auto_lights = local_car.headlights


func _make_car(info: Dictionary, remote: bool) -> Car:
	var car := Car.new()
	car.car_id = str(info.get("car", "r34"))
	car.paint = Game.get_paint(str(info.get("paint", "red")), str(info.get("custom_color", "")))
	car.player_name = str(info.get("name", "Driver"))
	car.is_remote = remote
	car.remote_collisions = bool(config.get("collisions", true))
	car.track = track
	car.skidmarks = skidmarks
	car.transmission = str(info.get("transmission", "auto"))
	if remote:
		car.burble = clampi(int(info.get("burble", Game.get_car(car.car_id).get("burble", 1))), 0, Game.BURBLE_LEVELS.size() - 1)
	car.name = "Car_%s" % car.player_name.validate_node_name()
	add_child(car)
	if remote:
		var tag := Label3D.new()
		tag.text = car.player_name
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.1, 0)
		tag.font_size = 48
		tag.outline_size = 12
		tag.modulate = Color(1, 0.9, 0.5)
		tag.no_depth_test = false
		car.add_child(tag)
		if not car.remote_collisions:
			# ghost mode: the others are see-through so you know you'll pass through them
			for gi in car.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).transparency = 0.55
	return car


func all_cars() -> Array:
	var out: Array = []
	for c in cars.values():
		if is_instance_valid(c):
			out.append(c)
	return out


# ---------------------------------------------------------------------------
# Race flow
# ---------------------------------------------------------------------------
func _start_countdown() -> void:
	state = "countdown"
	countdown = 4.0
	_last_count_step = -1
	local_car.controls_locked = true
	hud.show_message("", "", Color.WHITE, 0.0)
	track.set_start_lights(0)


func _physics_process(delta: float) -> void:
	match state:
		"waiting":
			_wait_timeout -= delta
			if _wait_timeout <= 0.0 and Net.is_host():
				Net.force_countdown()
				_wait_timeout = 999.0
		"countdown":
			countdown -= delta
			var step := int(ceil(countdown))
			if step != _last_count_step:
				_last_count_step = step
				if step >= 2:
					hud.set_countdown(str(step - 1), Color(1.0, 0.3, 0.2))
					track.set_start_lights(5 - step)
				elif step == 1:
					hud.set_countdown("GO!", UiKit.GOOD)
					track.set_start_lights(4)
					state = "running"
					race_time = 0.0
					local_car.controls_locked = false
		"running", "finished":
			race_time += delta
			_update_progress()
	if state == "running" and not finished:
		scorer.update(local_car, delta, get_world_3d().direct_space_state)
		for ev in scorer.events:
			hud.on_drift_event(ev)
	if local_car and Input.is_action_just_pressed("reset_car") and local_car.input_enabled and state != "countdown":
		local_car.reset_to_track()
		scorer.fail("Zurückgesetzt")
		for ev in scorer.events:
			hud.on_drift_event(ev)
	if online:
		_net_timer -= delta
		if _net_timer <= 0.0:
			_net_timer = 1.0 / 30.0
			Net.send_state(local_car.get_net_state(total_progress(), lap, scorer.total + scorer.chain, scorer.best_chain, scorer.chain))


func _update_progress() -> void:
	var proj: Array = track.project(local_car.global_position, local_car.track_hint)
	var prog: float = proj[1]
	var length: float = track.length
	progress = prog
	if _last_prog >= 0.0:
		if _last_prog > length * 0.8 and prog < length * 0.2:
			_on_cross_forward()
		elif _last_prog < length * 0.2 and prog > length * 0.8:
			_sector_mask = 0
	_sector_mask |= 1 << clampi(int(prog / length * SECTORS), 0, SECTORS - 1)
	_last_prog = prog


func _on_cross_forward() -> void:
	if finished:
		return
	var valid := _popcount(_sector_mask) >= SECTORS - 2
	if not crossed_start:
		crossed_start = true
		lap_start = race_time
		if mode == "free":
			hud.show_message("ZEITMESSUNG LÄUFT", "", Color.WHITE, 1.5)
	elif valid:
		_complete_lap()
	else:
		lap_start = race_time
		hud.show_message("RUNDE UNGÜLTIG", "Abkürzung oder falsche Richtung", UiKit.BAD, 2.0)
	_sector_mask = 1


func _popcount(v: int) -> int:
	var c := 0
	while v != 0:
		c += v & 1
		v >>= 1
	return c


func _complete_lap() -> void:
	var t := race_time - lap_start
	last_lap = t
	lap_times.append(t)
	lap += 1
	lap_start = race_time
	var is_best := best_lap <= 0.0 or t < best_lap
	if is_best:
		best_lap = t
	var rank := Game.submit_score(track.track_id, "lap", local_car.player_name, t, local_car.car_id)
	var sub := "Rundenzeit %s" % Game.format_time(t)
	if rank > 0:
		sub += "  ·  Leaderboard Platz %d" % rank
	if mode != "free" and lap >= laps_total:
		_finish()
		return
	if is_best:
		hud.show_message("NEUE BESTZEIT", sub, UiKit.GOLD, 2.5)
	else:
		hud.show_message("RUNDE %d" % (lap + 1) if mode != "free" else "RUNDE", sub, Color.WHITE, 2.0)
	if mode != "free" and lap == laps_total - 1:
		hud.show_message("LETZTE RUNDE", sub, UiKit.GOLD, 2.5)


func total_progress() -> float:
	if not crossed_start:
		return progress - track.length
	return lap * track.length + progress


func _finish() -> void:
	finished = true
	finish_time = race_time
	state = "finished"
	scorer.bank()
	scorer.enabled = false
	local_car.input_enabled = false
	var result := {"time": finish_time, "best_lap": best_lap, "drift": scorer.total, "best_chain": scorer.best_chain, "finished": true}
	var notes := _submit_leaderboard()
	if online:
		Net.report_result(result)
		_show_online_results()
	else:
		var header := ["", "Fahrer", "Auto", "Gesamtzeit", "Beste Runde", "Driftpunkte"]
		var rows := [["1.", local_car.player_name, Game.get_car(local_car.car_id)["name"], Game.format_time(finish_time), Game.format_time(best_lap), Game.format_points(scorer.total), true]]
		var lap_rows: Array = []
		for i in lap_times.size():
			lap_rows.append("Runde %d: %s" % [i + 1, Game.format_time(lap_times[i])])
		hud.show_results("ZIEL!" if mode == "race" else "DRIFT-BATTLE BEENDET", header, rows, notes + lap_rows, [
			["Nochmal", request_restart], ["Hauptmenü", request_main_menu]])


func _submit_leaderboard() -> Array:
	if _session_saved:
		return []
	_session_saved = true
	var notes: Array = []
	var tid := track.track_id
	var pname := local_car.player_name
	var cid := local_car.car_id
	if scorer.total > 0.0:
		var r := Game.submit_score(tid, "drift", pname, scorer.total, cid, Game.mode_name(mode))
		if r > 0:
			notes.append("Driftpunkte: Platz %d im Leaderboard!" % r)
	if scorer.best_chain > 0.0:
		var r2 := Game.submit_score(tid, "combo", pname, scorer.best_chain, cid, Game.mode_name(mode))
		if r2 > 0:
			notes.append("Bester Einzeldrift: Platz %d im Leaderboard!" % r2)
	if mode == "race" and finished:
		var r3 := Game.submit_score(tid, "race", pname, finish_time, cid, "%d Runden" % laps_total)
		if r3 > 0:
			notes.append("Rennzeit: Platz %d im Leaderboard!" % r3)
	# credits for the tuning shop
	var credits := int(scorer.total / 40.0)
	if finished and mode != "free":
		credits += 600 * laps_total
		if online and position_text().begins_with("1 "):
			credits += 2500
	if credits > 0:
		Game.add_credits(credits)
		notes.append("+%s Credits (Tuning in der Garage)" % Game.format_points(credits))
	return notes


func end_free_session() -> void:
	scorer.bank()
	scorer.enabled = false
	local_car.input_enabled = false
	finished = true
	var notes := _submit_leaderboard()
	var header := ["Fahrer", "Driftpunkte", "Bester Drift", "Beste Runde", "Runden"]
	var rows := [[local_car.player_name, Game.format_points(scorer.total), Game.format_points(scorer.best_chain), Game.format_time(best_lap), str(lap), true]]
	hud.show_results("SESSION BEENDET", header, rows, notes, [["Weiterfahren", _resume_free], ["Hauptmenü", request_main_menu]])


func _resume_free() -> void:
	hud.hide_results()
	finished = false
	_session_saved = false
	scorer = DriftScorer.new()
	local_car.input_enabled = true


# ---------------------------------------------------------------------------
# Online
# ---------------------------------------------------------------------------
func _on_remote_state(peer_id: int, s: Array) -> void:
	if cars.has(peer_id) and is_instance_valid(cars[peer_id]) and cars[peer_id] != local_car:
		(cars[peer_id] as Car).apply_net_state(s)


func _on_peer_left(peer_id: int) -> void:
	if cars.has(peer_id) and cars[peer_id] != local_car:
		var c: Car = cars[peer_id]
		hud.show_message("%s hat das Spiel verlassen" % c.player_name, "", UiKit.TEXT_DIM, 2.0)
		c.queue_free()
		cars.erase(peer_id)


## Player info changed (e.g. someone switched their Burble-Tune in the pause menu).
func _on_lobby_changed() -> void:
	for id in cars.keys():
		var c: Car = cars[id]
		if c != local_car and Net.players.has(id):
			var info: Dictionary = Net.players[id]
			c.burble = clampi(int(info.get("burble", c.burble)), 0, Game.BURBLE_LEVELS.size() - 1)


func _on_results_updated(_arr: Array) -> void:
	if finished:
		_show_online_results()


func _show_online_results() -> void:
	var arr: Array = Net.result_list.duplicate()
	if mode == "drift":
		arr.sort_custom(func(a, b): return float(a["drift"]) > float(b["drift"]))
	else:
		arr.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	var header := ["", "Fahrer", "Auto", "Zeit", "Beste Runde", "Driftpunkte"]
	var rows: Array = []
	var me := Net.local_id()
	var done := {}
	for i in arr.size():
		var r: Dictionary = arr[i]
		done[int(r.get("id", 0))] = true
		rows.append(["%d." % (i + 1), str(r.get("name", "?")), Game.get_car(str(r.get("car", "r34")))["name"],
			Game.format_time(float(r.get("time", 0.0))), Game.format_time(float(r.get("best_lap", 0.0))),
			Game.format_points(float(r.get("drift", 0.0))), int(r.get("id", 0)) == me])
	for id in cars.keys():
		if not done.has(id) and is_instance_valid(cars[id]):
			var c: Car = cars[id]
			rows.append(["–", c.player_name, Game.get_car(c.car_id)["name"], "fährt noch (Runde %d)" % (c.remote_lap + 1), "", Game.format_points(c.remote_drift), false])
	var buttons: Array = []
	if Net.is_host():
		buttons.append(["Zurück zur Lobby", func(): Net.host_return_to_lobby()])
	buttons.append(["Lobby verlassen", request_leave_online])
	var title_text := "ERGEBNIS – " + Game.mode_name(mode).to_upper()
	hud.show_results(title_text, header, rows, [], buttons)


func position_text() -> String:
	if not online or mode == "free":
		return ""
	var entries: Array = []
	for id in cars.keys():
		var c = cars[id]
		if not is_instance_valid(c):
			continue
		var value := 0.0
		if c == local_car:
			value = scorer.total + scorer.chain if mode == "drift" else total_progress()
		else:
			value = (c as Car).remote_drift if mode == "drift" else (c as Car).remote_progress
		entries.append([value, c == local_car])
	entries.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for i in entries.size():
		if entries[i][1]:
			return "%d / %d" % [i + 1, entries.size()]
	return ""


func scoreboard_data() -> Dictionary:
	if online:
		var rows: Array = []
		for id in cars.keys():
			var c = cars[id]
			if not is_instance_valid(c):
				continue
			var is_me: bool = c == local_car
			var lp: int = lap if is_me else (c as Car).remote_lap
			var dr: float = (scorer.total + scorer.chain) if is_me else (c as Car).remote_drift
			var pr: float = total_progress() if is_me else (c as Car).remote_progress
			rows.append([c.player_name, Game.get_car(c.car_id)["name"], str(lp + 1), Game.format_points(dr), pr, dr, is_me])
		if mode == "drift":
			rows.sort_custom(func(a, b): return float(a[5]) > float(b[5]))
		else:
			rows.sort_custom(func(a, b): return float(a[4]) > float(b[4]))
		var out: Array = []
		for i in rows.size():
			var r: Array = rows[i]
			out.append(["%d." % (i + 1), r[0], r[1], r[2], r[3], r[6]])
		return {"header": ["Pos", "Fahrer", "Auto", "Runde", "Driftpunkte"], "rows": out}
	var tid := track.track_id
	var out2: Array = []
	var drift: Array = Game.get_scores(tid, "drift")
	var laps: Array = Game.get_scores(tid, "lap")
	for i in 8:
		var d := ""
		var l := ""
		if i < drift.size():
			d = "%s  %s" % [Game.format_points(float(drift[i]["value"])), drift[i]["name"]]
		if i < laps.size():
			l = "%s  %s" % [Game.format_time(float(laps[i]["value"])), laps[i]["name"]]
		if d == "" and l == "":
			break
		out2.append(["%d." % (i + 1), d, l, false])
	if out2.is_empty():
		out2.append(["–", "Noch keine Einträge", "", false])
	return {"header": ["#", "Beste Driftsessions", "Beste Runden"], "rows": out2}


# ---------------------------------------------------------------------------
# Events / exits
# ---------------------------------------------------------------------------
## Time of day / weather changed the light level: lamps, windows and (automatic) headlights.
func _on_night_changed(n: float) -> void:
	if scenery:
		scenery.set_night(n)
	if local_car == null:
		return
	if n > 0.45 and not _auto_lights:
		_auto_lights = true
		local_car.headlights = true
	elif n < 0.3 and _auto_lights:
		_auto_lights = false
		local_car.headlights = false
func _on_wall_hit(strength: float) -> void:
	if strength > 5.0 and scorer.chain > 0.0:
		scorer.fail("Wand berührt")
		for ev in scorer.events:
			hud.on_drift_event(ev)


func request_restart() -> void:
	if mode == "free" and not _session_saved:
		_submit_leaderboard()
	exit_requested.emit("restart")


func request_main_menu() -> void:
	if mode == "free" and not _session_saved:
		scorer.bank()
		_submit_leaderboard()
	exit_requested.emit("menu")


func request_leave_online() -> void:
	exit_requested.emit("leave")


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false


## Compile every render pipeline right after loading (no freezes later, see shader_warmup.gd).
func _warmup() -> void:
	for f in 2:
		await get_tree().process_frame
	if not is_inside_tree() or camera == null:
		return
	var extra: Array = []
	var pg := scenery.get_node_or_null("Playground") if scenery else null
	if pg:
		extra = pg._meshes.values()
	# make the car's flames and smoke part of it
	if local_car and local_car.fx:
		local_car.fx._on_backfire(1.0)
	var w := ShaderWarmup.new()
	w.name = "ShaderWarmup"
	add_child(w)
	w.run(self, camera, extra)

