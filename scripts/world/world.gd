extends Node3D
## One race session: builds environment, track and scenery, spawns cars, runs countdown, laps,
## drift scoring, results and leaderboard submission. Works offline and online.

signal exit_requested(target: String)   # "menu", "lobby", "restart", "leave"

const Traffic = preload("res://scripts/world/traffic.gd")
const TrafficCars = preload("res://scripts/world/traffic_cars.gd")
const CityTraffic = preload("res://scripts/world/city/city_traffic.gd")
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
const Graffiti = preload("res://scripts/world/graffiti.gd")
const Party = preload("res://scripts/world/party.gd")
const PartySites = preload("res://scripts/world/party_sites.gd")
const TutorialSite = preload("res://scripts/world/tutorial_site.gd")
const Tutorial = preload("res://scripts/world/tutorial.gd")
const RaceAI = preload("res://scripts/world/race_ai.gd")
const MapData = preload("res://scripts/editor/map_data.gd")
const WorldEditor = preload("res://scripts/editor/world_editor.gd")
const Replay = preload("res://scripts/replay/replay.gd")
const ReplayPlayer = preload("res://scripts/replay/replay_player.gd")
const AdminPanel = preload("res://scripts/admin/admin_panel.gd")

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
var traffic: Node3D          # optional NPC traffic on the race route (traffic.gd)
var city_traffic: Node3D     # Neo Tokyo: traffic on all the city streets (city/city_traffic.gd)
var traffic_cars: Node3D     # draws all the traffic cars (traffic_cars.gd)
var cars := {}              # peer_id -> Car
var camera: CameraRig
var hud: Hud
var pause_menu: PauseMenu
var scorer: DriftScorer
var graffiti: Graffiti      # graffiti mode only
var time_limit := 0.0       # graffiti mode: seconds
var party: Party            # party mode (minigame coins) or null
var _bots_parked := false
var _bot_ids := {}           # ids of the race bots (from the roster)
var party_sites: PartySites
var tutorial_site: TutorialSite   # tutorial mode (Grüne Hölle)
var tutorial: Tutorial
var race_ai: RaceAI           # AI opponents (race mode), or null
var custom_map                # map_data.gd: a map from the world editor (config "map"), or null
var map_content: Node3D       # what that map placed
var editor: Node3D            # world_editor.gd (mode "editor")
var recorder: Node            # replay.gd: records the session (saved on request)
var replay_player: Node       # replay_player.gd (mode "replay")
var _replay: Array = []       # [header, data] being played

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
## Driving the wrong way: metres covered backwards along the lap (a spin's wiggle doesn't count),
## and whether that has spoilt this lap (only past 25 % of it, or within 10 % of start/finish).
var _rev_m := 0.0
var _rev_t := 0.0               # ... and for how long (s): the lap is spoilt only after 10 s of it
var _lap_spoilt := false
var _net_timer := 0.0
var _wait_timeout := 15.0
var _last_count_step := -1
var _session_saved := false
var _finish_order: Array = []
var _auto_lights := false


func setup(cfg: Dictionary) -> void:
	config = cfg


## Emitted once the world is fully built (it builds in slices when config "async_load" is set).
signal loaded
var is_loaded := false


func _ready() -> void:
	Game.async_loading = bool(config.get("async_load", false))
	Game.load_progress = 0.0
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
	if mode == "tutorial":
		track.wall_gaps = TutorialSite.wall_gaps()
	add_child(track)
	Game.load_begin("Strecke", 0.0, 0.06)
	await track.build(config.get("track", "ridge"))
	await Game.load_tick(1.0)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	Game.load_begin("Gelände", 0.06, 0.34)
	await terrain.generate(track)
	var t1 := Time.get_ticks_msec()
	scenery = Scenery.new()
	scenery.name = "Scenery"
	if mode == "tutorial":
		tutorial_site = TutorialSite.new()
		tutorial_site.name = "TutorialSite"
		scenery.tutorial_site = tutorial_site
	add_child(scenery)
	Game.load_begin("Streckenrand", 0.34, 0.36)
	await scenery.build(track, terrain, atmosphere.night, quality)
	# party mode: the minigames are played on stretches of the track (not on the long data tracks)
	if bool(config.get("party", false)) and not track.elevated:
		party_sites = PartySites.new()
		party_sites.name = "PartySites"
		if party_sites.plan(track):
			add_child(party_sites)
		else:
			party_sites.free()
			party_sites = null
	var t2 := Time.get_ticks_msec()
	Game.load_begin("Gelände-Modell", 0.82, 0.94)
	await terrain.build_meshes()
	atmosphere.track = track
	atmosphere.materials_wet = [terrain.material]
	for key in ["leaf", "needle", "fern", "rock"]:
		atmosphere.materials_wet.append(TreeFactory._material(key))
	for m in scenery.lod_materials:
		if m.shader and "wetness" in m.shader.code:
			atmosphere.materials_wet.append(m)
	atmosphere.night_changed.connect(_on_night_changed)
	if track.road_material:
		track.road_material.set_shader_parameter("night", atmosphere.night)
	terrain.material.set_shader_parameter("night", atmosphere.night)
	grass = Grass.new()
	grass.name = "Grass"
	add_child(grass)
	Game.load_begin("Gras", 0.94, 1.0)
	await grass.setup(terrain, track, self)
	terrain.paint.attach([terrain.material], grass)
	# a map from the world editor: its ground, scenery changes, objects, roads and water
	var base_heights := PackedFloat32Array()
	if mode == "editor":
		base_heights = terrain.heights.duplicate()
	if str(config.get("map", "")) != "":
		custom_map = MapData.load_file(str(config["map"]))
	if custom_map == null and mode == "editor":
		custom_map = MapData.new()
		custom_map.base_track = track.track_id
		custom_map.map_name = "%s (Kopie)" % Game.track_name(track.track_id)
	if custom_map:
		map_content = custom_map.apply(self)
	flares = LensFlare.new()
	flares.name = "LensFlares"
	add_child(flares)
	flares.setup(atmosphere)
	print("WORLD: terrain %d ms, scenery %d ms, meshes+grass %d ms (%s)" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2, scenery.stats_text() + (", " + scenery.details.stats_text() if scenery.details else "")])
	skidmarks = Skidmarks.new()
	skidmarks.name = "Skidmarks"
	if track.elevated:
		skidmarks.y_lift = 0.017
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
	local_car.assist_toggled.connect(func(n: String, on: bool) -> void:
		if hud:
			hud.show_message("%s %s" % [n, "AN" if on else "AUS"], "", Color(0.5, 1.0, 0.6) if on else Color(1.0, 0.6, 0.4), 1.4))
	if mode == "graffiti":
		_setup_graffiti()
	if party_sites:
		party = Party.new()
		party.name = "Party"
		party.setup(self, party_sites, config)
		add_child(party)

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
		if Net.countdown_t0 >= 0:
			# the host started while this machine was still loading
			_start_countdown()
	elif mode == "graffiti" and not online:
		hud.show_message("GRAFFITI", "Drifte über die Strecke, um sie in deiner Farbe zu markieren", Color.WHITE, 4.0)
		_start_countdown()
	elif mode == "tutorial":
		state = "running"
		tutorial = Tutorial.new()
		tutorial.name = "Tutorial"
		tutorial.setup(self, tutorial_site)
		add_child(tutorial)
	elif mode == "replay":
		state = "replay"
		hud.visible = false
		hud.process_mode = Node.PROCESS_MODE_DISABLED
		pause_menu.process_mode = Node.PROCESS_MODE_DISABLED
		camera.process_mode = Node.PROCESS_MODE_DISABLED
		replay_player = ReplayPlayer.new()
		replay_player.name = "ReplayPlayer"
		replay_player.setup(self, _replay[0] if not _replay.is_empty() else {}, _replay[1] if not _replay.is_empty() else PackedFloat32Array())
		add_child(replay_player)
	elif mode == "editor":
		state = "editor"
		_enter_editor(str(config.get("map", "")), base_heights)
	elif mode == "free":
		state = "running"
		hud.show_message(Game.track_name(track.track_id), "Freies Driften – überquere die Startlinie, um die Zeitmessung zu starten", Color.WHITE, 4.0)
	else:
		_start_countdown()
	_collect_view_ranges()
	Game.settings_changed.connect(_apply_view_ranges)
	# admin mode (offline or the host): F10 panel
	if bool(Game.settings.get("admin_mode", false)) and (not online or Net.is_host()) and not (mode in ["editor", "replay"]):
		var ap := AdminPanel.new()
		ap.name = "AdminPanel"
		ap.world = self
		add_child(ap)
	# every driven session is recorded (saved as a replay when asked)
	if not (mode in ["editor", "replay", "tutorial"]):
		recorder = Replay.new()
		recorder.name = "Recorder"
		add_child(recorder)
		recorder.setup(self)
	Game.async_loading = false
	Game.load_progress = 1.0
	is_loaded = true
	loaded.emit()


## World editor: the car parked out of sight, no HUD, the editor's own camera and tools.
func _enter_editor(path: String, base_heights: PackedFloat32Array) -> void:
	local_car.freeze = true
	local_car.visible = false
	local_car.process_mode = Node.PROCESS_MODE_DISABLED
	local_car.collision_layer = 0
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	pause_menu.process_mode = Node.PROCESS_MODE_DISABLED
	editor = WorldEditor.new()
	editor.name = "WorldEditor"
	editor.setup(self, custom_map, path, map_content, base_heights)
	add_child(editor)


func _spawn_cars() -> void:
	var night: float = atmosphere.night
	if mode == "replay":
		_replay = Replay.read_file(str(config.get("replay", "")))
		var infos: Array = _replay[0].get("cars", []) if not _replay.is_empty() else []
		for k in infos.size():
			var ci: Dictionary = infos[k]
			var info := {"name": ci.get("name", "?"), "car": ci.get("car", "r34"), "paint_dict": ci.get("paint", {}),
				"rims": ci.get("rims", {}), "underglow": ci.get("underglow", {}), "burble": ci.get("burble", 1)}
			var car := _make_car(info, true)
			cars[k] = car
			car.place(track.grid_transform(k))
		if cars.is_empty():
			cars[0] = _make_car(Game.local_player_info(), true)
		local_car = cars.get(int(_replay[0].get("local", 0)) if not _replay.is_empty() else 0, cars.values()[0])
		return
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
		var info := Game.local_player_info()
		if mode == "tutorial":
			info["car"] = "r34"
			info["paint"] = str(Game.settings.get("paint", "blue")) if str(Game.settings.get("car", "")) == "r34" else "blue"
		local_car = _make_car(info, false)
		cars[1] = local_car
		local_car.place(track.grid_transform(0))
	_spawn_bots(night)
	# optional NPC traffic (offline; not in party mode, on the open playground pad or the 20 km
	# Nordschleife): on the race route, and in Neo Tokyo on every street of the city
	var dens := clampi(int(config.get("traffic", 0)), 0, Traffic.DENSITY.size() - 1)
	var partying := bool(config.get("party", false))
	if dens > 0 and not online and not partying and track.track_id != "playground" and not track.elevated:
		traffic_cars = TrafficCars.new()
		traffic_cars.name = "TrafficCars"
		add_child(traffic_cars)
		traffic_cars.setup(self)
		traffic = Traffic.new()
		traffic.name = "Traffic"
		add_child(traffic)
		var spd_level := clampi(int(config.get("traffic_speed", 1)), 0, Traffic.SPEEDS.size() - 1)
		traffic.setup(self, maxi(int(track.length / 1000.0 * float(Traffic.DENSITY[dens])), 4), traffic_cars, spd_level)
		if scenery.city != null:
			city_traffic = CityTraffic.new()
			city_traffic.name = "CityTraffic"
			add_child(city_traffic)
			city_traffic.setup(self, scenery.city.net, dens, traffic_cars, float(Traffic.SPEEDS[spd_level]))
	local_car.transmission = str(Game.settings.get("transmission", "auto"))
	local_car.headlights = night >= 0.4
	_auto_lights = local_car.headlights


## Party minigame: the race bots stop where they are, invisible and without collision (on every machine);
## afterwards they carry on from the same spot. Only the machine that drives them freezes the physics.
func _park_bots(on: bool) -> void:
	for id in cars:
		# only the race bots (online the players have big random peer ids – they must stay visible)
		if not _bot_ids.has(int(id)) or not is_instance_valid(cars[id]):
			continue
		var c: Car = cars[id]
		c.visible = not on
		if on:
			c.set_meta("park_layer", c.collision_layer)
			c.set_meta("park_mask", c.collision_mask)
			c.collision_layer = 0
			c.collision_mask = 0
			if c.is_bot:
				c.set_meta("park_xf", c.global_transform)
				c.freeze = true
		else:
			c.collision_layer = int(c.get_meta("park_layer", c.collision_layer))
			c.collision_mask = int(c.get_meta("park_mask", c.collision_mask))
			if c.is_bot:
				c.freeze = false
				c.place(c.get_meta("park_xf", c.global_transform))


## AI opponents: on the grid in front of the player (offline) / behind the players (online). Offline
## and on the host they are driven here, the others get them as remote cars.
func _spawn_bots(night: float) -> void:
	var roster: Array = config.get("bots", [])
	if roster.is_empty() or mode != "race":
		return
	var driving: bool = not online or Net.is_host()
	if driving:
		race_ai = RaceAI.new()
		race_ai.name = "RaceAI"
		race_ai.world = self
		race_ai.level = clampi(int(config.get("bot_level", 1)), 0, 3)
		add_child(race_ai)
	var first: int = cars.size() if online else 0
	for k in roster.size():
		var e: Dictionary = roster[k]
		var id := int(e.get("id", RaceAI.BOT_ID0 + k))
		_bot_ids[id] = true
		var info := {"car": str(e.get("car", "r34")), "paint": str(e.get("paint", "red")), "name": str(e.get("name", "KI")), "transmission": "auto"}
		var tun = e.get("tuning", {})
		info["tuning"] = tun if tun is Dictionary else {}
		var car := _make_car(info, not driving, driving)
		car.peer_id = id
		car.headlights = night >= 0.4
		cars[id] = car
		car.place(track.grid_transform(first + k))
		if driving:
			race_ai.add_bot(id, car, str(e.get("personality", "Ausgeglichen")))
	if not online:
		# the player starts behind the field
		local_car.place(track.grid_transform(roster.size()))


func _make_car(info: Dictionary, remote: bool, bot := false) -> Car:
	var car := Car.new()
	car.car_id = str(info.get("car", "r34"))
	car.paint = Game.get_paint(str(info.get("paint", "red")), str(info.get("custom_color", "")), str(info.get("paint_finish", "gloss")))
	if info.get("paint_dict") is Dictionary:
		# a replay: the paint exactly as recorded
		var pd: Dictionary = info["paint_dict"]
		car.paint = {"id": "custom", "name": "", "color": Color.from_string(str(pd.get("color", "aa0000")), Color.RED),
			"metallic": float(pd.get("metallic", 0.1)), "roughness": float(pd.get("roughness", 0.2)), "finish": str(pd.get("finish", "gloss"))}
	if info.get("rims") is Dictionary:
		car.rims_cfg = info["rims"]
	car.player_name = str(info.get("name", "Driver"))
	car.is_remote = remote
	car.is_bot = bot
	if bot:
		car.input_enabled = false
		var tun = info.get("tuning", {})
		if tun is Dictionary and not tun.is_empty():
			car.tuning_override = tun
	car.remote_collisions = bool(config.get("collisions", true))
	car.track = track
	car.skidmarks = skidmarks
	car.transmission = str(info.get("transmission", "auto"))
	if remote:
		car.burble = clampi(int(info.get("burble", Game.get_car(car.car_id).get("burble", 1))), 0, Game.BURBLE_LEVELS.size() - 1)
		var ug = info.get("underglow", {})
		car.underglow_cfg = ug if ug is Dictionary else {}
	car.name = "Car_%s" % car.player_name.validate_node_name()
	add_child(car)
	if remote or bot:
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
	if state == "countdown" or state == "running" or state == "finished":
		return
	var elapsed := 0.0
	if online and Net.countdown_t0 >= 0:
		# online the countdown runs from when the host started it – a machine that loaded late joins
		# it where it is, or (already over) starts right away without showing a timer
		elapsed = (Time.get_ticks_msec() - Net.countdown_t0) / 1000.0
	hud.show_message("", "", Color.WHITE, 0.0)
	if elapsed >= 3.0:
		state = "running"
		race_time = elapsed - 3.0
		local_car.controls_locked = false
		hud.set_countdown("")
		track.set_start_lights(4)
		return
	state = "countdown"
	countdown = 4.0 - elapsed
	_last_count_step = -1
	local_car.controls_locked = true
	track.set_start_lights(0)


func _physics_process(delta: float) -> void:
	if not is_loaded or state == "editor" or state == "replay":
		return
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
			# a party minigame stops the race clock and the lap counting
			if party == null or not party.active():
				race_time += delta
				_update_progress()
	# race bots wait out a party minigame where they are (hidden, no collision)
	var park := party != null and party.active()
	if park != _bots_parked:
		_bots_parked = park
		_park_bots(park)
	if state == "running" and not finished and (party == null or not party.active()):
		scorer.update(local_car, delta, get_world_3d().direct_space_state)
		local_car.trail_active = scorer.chain >= Car.DRIFT_TRAIL_POINTS
		for ev in scorer.events:
			hud.on_drift_event(ev)
		if graffiti:
			if scorer.drifting:
				graffiti.spray(progress)
			if race_time >= time_limit:
				_finish()
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
			# backwards over the line: that's within 10 % of it (once it's been 10 s of it)
			if _rev_t >= 10.0:
				_spoil_lap()
		var dp := wrapf(prog - _last_prog, -length * 0.5, length * 0.5)
		if dp < 0.0:
			_rev_m -= dp
			if float(local_car.speed) > 2.0:
				_rev_t += get_physics_process_delta_time()
		elif dp > 0.3:
			_rev_m = maxf(_rev_m - dp, 0.0)
			if _rev_m <= 0.0:
				_rev_t = 0.0
		# backwards for real: the lap only counts as spoilt once a quarter of it is done, or near
		# start/finish (turning round early in the lap after a spin costs nothing)
		var frac := prog / length
		if _rev_m > 15.0 and _rev_t >= 10.0 and (frac > 0.25 or frac < 0.1):
			_spoil_lap()
	_sector_mask |= 1 << clampi(int(prog / length * SECTORS), 0, SECTORS - 1)
	_last_prog = prog


func _spoil_lap() -> void:
	if _lap_spoilt or not crossed_start or finished:
		return
	_lap_spoilt = true
	hud.show_message("RUNDE UNGÜLTIG", "Falsche Richtung gefahren", UiKit.BAD, 2.0)


func _on_cross_forward() -> void:
	if finished:
		return
	var valid := _popcount(_sector_mask) >= SECTORS - 2 and not _lap_spoilt
	if not crossed_start:
		crossed_start = true
		lap_start = race_time
		if mode == "free":
			hud.show_message("ZEITMESSUNG LÄUFT", "", Color.WHITE, 1.5)
	elif valid:
		_complete_lap()
	else:
		lap_start = race_time
		hud.show_message("RUNDE UNGÜLTIG", "Falsche Richtung gefahren" if _lap_spoilt else "Abkürzung", UiKit.BAD, 2.0)
	_sector_mask = 1
	_lap_spoilt = false
	_rev_m = 0.0
	_rev_t = 0.0


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
	if _lap_race() and lap >= laps_total:
		_finish()
		return
	if is_best:
		hud.show_message("NEUE BESTZEIT", sub, UiKit.GOLD, 2.5)
	else:
		hud.show_message("RUNDE %d" % (lap + 1) if _lap_race() else "RUNDE", sub, Color.WHITE, 2.0)
	if _lap_race() and lap == laps_total - 1:
		hud.show_message("LETZTE RUNDE", sub, UiKit.GOLD, 2.5)


## Modes that end after a number of laps.
func _lap_race() -> bool:
	return mode == "race" or mode == "drift"


func _setup_graffiti() -> void:
	time_limit = clampf(float(config.get("graffiti_minutes", 5)), 1.0, 60.0) * 60.0
	var players := {}
	for id in cars.keys():
		var c: Car = cars[id]
		players[id] = {"color": (c.paint as Dictionary).get("color", Color(0.8, 0.1, 0.1)), "name": c.player_name}
	graffiti = Graffiti.new()
	graffiti.name = "Graffiti"
	add_child(graffiti)
	graffiti.setup(track, players, Net.local_id() if online else 1, online)


## Graffiti: metres of track the player holds (local or remote car).
func graffiti_metres(c) -> float:
	if graffiti == null:
		return 0.0
	for id in cars.keys():
		if cars[id] == c:
			return graffiti.metres(id)
	return 0.0


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
	if graffiti:
		result["graffiti"] = graffiti_metres(local_car)
	var notes := _submit_leaderboard()
	if online:
		Net.report_result(result)
		_show_online_results()
	elif graffiti:
		var held := graffiti_metres(local_car)
		var header := ["Fahrer", "Auto", "Revier", "Anteil", "Driftpunkte"]
		var rows := [[local_car.player_name, Game.get_car(local_car.car_id)["name"], "%d m" % int(held),
			"%d %%" % int(round(held / maxf(track.length, 1.0) * 100.0)), Game.format_points(scorer.total), true]]
		hud.show_results("GRAFFITI – ZEIT ABGELAUFEN", header, rows, notes, [["Nochmal", request_restart], ["Replay speichern", save_replay], ["Hauptmenü", request_main_menu]])
	else:
		var header := ["", "Fahrer", "Auto", "Gesamtzeit", "Beste Runde", "Driftpunkte"]
		var rows := [["1.", local_car.player_name, Game.get_car(local_car.car_id)["name"], Game.format_time(finish_time), Game.format_time(best_lap), Game.format_points(scorer.total), true]]
		if race_ai:
			rows = _results_with_bots()
		var lap_rows: Array = []
		for i in lap_times.size():
			lap_rows.append("Runde %d: %s" % [i + 1, Game.format_time(lap_times[i])])
		hud.show_results("ZIEL!" if mode == "race" else "DRIFT-BATTLE BEENDET", header, rows, notes + lap_rows, [
			["Nochmal", request_restart], ["Replay speichern", save_replay], ["Hauptmenü", request_main_menu]])


## Offline race against the AI: everybody who finished by time, then the others by distance.
func _results_with_bots() -> Array:
	var entries: Array = [[finish_time, 1e9, local_car.player_name, local_car.car_id, best_lap, scorer.total, true, true]]
	for b in race_ai.bots:
		var c = b["car"]
		if not is_instance_valid(c):
			continue
		entries.append([float(b["time"]), race_ai.total_progress(b), c.player_name, c.car_id, float(b["best"]), 0.0, bool(b["finished"]), false])
	entries.sort_custom(func(a, b):
		if bool(a[6]) != bool(b[6]):
			return bool(a[6])
		if bool(a[6]):
			return float(a[0]) < float(b[0])
		return float(a[1]) > float(b[1]))
	var rows: Array = []
	for i in entries.size():
		var e: Array = entries[i]
		var t := Game.format_time(float(e[0])) if bool(e[6]) else "fährt noch"
		rows.append(["%d." % (i + 1), e[2], Game.get_car(str(e[3]))["name"], t, Game.format_time(float(e[4])) if float(e[4]) > 0.0 else "–",
			Game.format_points(float(e[5])) if bool(e[7]) else "–", bool(e[7])])
	return rows


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
		if graffiti:
			credits += int(graffiti_metres(local_car) * 2.0)
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
	hud.show_results("SESSION BEENDET", header, rows, notes, [["Weiterfahren", _resume_free], ["Replay speichern", save_replay], ["Hauptmenü", request_main_menu]])


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
	if graffiti:
		# everybody's territory from the shared (host-refereed) map, not from the reports
		for r in arr:
			r["graffiti"] = graffiti.metres(int(r.get("id", 0)))
		arr.sort_custom(func(a, b): return float(a["graffiti"]) > float(b["graffiti"]))
	elif mode == "drift":
		arr.sort_custom(func(a, b): return float(a["drift"]) > float(b["drift"]))
	else:
		arr.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	var header := ["", "Fahrer", "Auto", "Zeit", "Beste Runde", "Driftpunkte"]
	if graffiti:
		header = ["", "Fahrer", "Auto", "Revier", "Anteil", "Driftpunkte"]
	var rows: Array = []
	var me := Net.local_id()
	var done := {}
	for i in arr.size():
		var r: Dictionary = arr[i]
		done[int(r.get("id", 0))] = true
		if graffiti:
			var m := float(r.get("graffiti", 0.0))
			rows.append(["%d." % (i + 1), str(r.get("name", "?")), Game.get_car(str(r.get("car", "r34")))["name"],
				"%d m" % int(m), "%d %%" % int(round(m / maxf(track.length, 1.0) * 100.0)),
				Game.format_points(float(r.get("drift", 0.0))), int(r.get("id", 0)) == me])
			continue
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
	buttons.append(["Replay speichern", save_replay])
	buttons.append(["Lobby verlassen", request_leave_online])
	var title_text := "ERGEBNIS – " + Game.mode_name(mode).to_upper()
	hud.show_results(title_text, header, rows, [], buttons)


func position_text() -> String:
	if (not online and race_ai == null) or mode == "free":
		return ""
	var entries: Array = []
	for id in cars.keys():
		var c = cars[id]
		if not is_instance_valid(c):
			continue
		var value := 0.0
		if graffiti:
			value = graffiti_metres(c)
		elif c == local_car:
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
	if online or race_ai:
		var rows: Array = []
		for id in cars.keys():
			var c = cars[id]
			if not is_instance_valid(c):
				continue
			var is_me: bool = c == local_car
			var lp: int = lap if is_me else (c as Car).remote_lap
			var dr: float = (scorer.total + scorer.chain) if is_me else (c as Car).remote_drift
			var pr: float = total_progress() if is_me else (c as Car).remote_progress
			if graffiti:
				# ranking by territory; the "Runde" column shows the metres held
				pr = graffiti.metres(id)
				rows.append([c.player_name, Game.get_car(c.car_id)["name"], "%d m" % int(pr), Game.format_points(dr), pr, dr, is_me])
				continue
			rows.append([c.player_name, Game.get_car(c.car_id)["name"], str(lp + 1), Game.format_points(dr), pr, dr, is_me])
		if mode == "drift":
			rows.sort_custom(func(a, b): return float(a[5]) > float(b[5]))
		else:
			rows.sort_custom(func(a, b): return float(a[4]) > float(b[4]))
		var out: Array = []
		for i in rows.size():
			var r: Array = rows[i]
			out.append(["%d." % (i + 1), r[0], r[1], r[2], r[3], r[6]])
		return {"header": ["Pos", "Fahrer", "Auto", "Revier" if graffiti else "Runde", "Driftpunkte"], "rows": out}
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
	if track and track.road_material:
		track.road_material.set_shader_parameter("night", n)
	if terrain and terrain.material:
		terrain.material.set_shader_parameter("night", n)
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


# ---------------------------------------------------------------------------
# View distance for everything (buildings, traffic lights, lamps, people …): the setting scales the
# distances they are drawn to (1200 m = as built). Trees and props: scenery.apply_view_distance().
# ---------------------------------------------------------------------------
var _view_ranges: Array = []     # [GeometryInstance3D, begin, end]
var _view_k := -1.0


func _collect_view_ranges() -> void:
	var skip := {}
	if scenery:
		for r in scenery._ranged:
			skip[r[0]] = true
	for n in find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.visibility_range_end <= 0.0 or skip.has(gi) or (terrain and terrain.is_ancestor_of(gi)):
			continue
		_view_ranges.append([gi, gi.visibility_range_begin, gi.visibility_range_end])
	_apply_view_ranges()


func _apply_view_ranges() -> void:
	var k := clampf(float(Game.settings.get("view_distance", 1200)) / 1200.0, 0.3, 2.5)
	if is_equal_approx(k, _view_k):
		return      # (settings_changed fires for every setting)
	_view_k = k
	for r in _view_ranges:
		var gi: GeometryInstance3D = r[0]
		if not is_instance_valid(gi):
			continue
		# near and far versions scale together: no gaps between them
		gi.visibility_range_begin = float(r[1]) * k
		gi.visibility_range_end = float(r[2]) * k


## Saves what was recorded so far as a replay (watch it from the main menu: Replays).
func save_replay() -> void:
	if recorder == null:
		return
	var path: String = recorder.save()
	if hud:
		if path != "":
			hud.show_message("REPLAY GESPEICHERT", "%s – im Hauptmenü unter „Replays“" % Game.format_time(recorder.duration()), UiKit.GOOD, 3.0)
		else:
			hud.show_message("REPLAY", "Nichts aufgenommen", UiKit.BAD, 2.0)


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
	if pg == null and scenery:
		pg = scenery.get_node_or_null("TracksideProps")
	if pg:
		extra = pg._meshes.values()
	# make the car's flames and smoke part of it
	if local_car and local_car.fx:
		local_car.fx._on_backfire(1.0)
	var w := ShaderWarmup.new()
	w.name = "ShaderWarmup"
	add_child(w)
	w.run(self, camera, extra)
