extends Node
## Scene manager: menu + showroom <-> race world. Also runs the headless smoke test (--smoke-test).

const World = preload("res://scripts/world/world.gd")
const Menu = preload("res://scripts/ui/menu.gd")
const Showroom = preload("res://scripts/world/showroom.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const CarBodyScript = preload("res://scripts/car/car_body.gd")

var world: World
var menu: Menu
var showroom: Showroom
var last_config := {}
var _loading: CanvasLayer


func _ready() -> void:
	Net.race_start_requested.connect(_on_race_start)
	Net.return_to_lobby_requested.connect(_on_return_lobby)
	Net.disconnected.connect(_on_disconnected)
	if "--smoke-test" in OS.get_cmdline_user_args():
		_smoke_test()
		return
	show_menu("main")


func show_menu(screen: String, message := "", color := UiKit.GOLD) -> void:
	_clear_world()
	if showroom == null:
		showroom = Showroom.new()
		showroom.name = "Showroom"
		add_child(showroom)
	if menu == null:
		menu = Menu.new()
		menu.name = "Menu"
		menu.main = self
		add_child(menu)
	menu.show_screen(screen)
	if message != "":
		menu.show_status(message, color)


func refresh_showroom(full: bool) -> void:
	if showroom == null:
		return
	if full:
		showroom.rebuild_car()
	else:
		showroom.refresh_paint()


func start_offline() -> void:
	var cfg := {
		"track": Game.settings["track"],
		"mode": Game.settings["mode"],
		"laps": int(Game.settings["laps"]),
		"time_of_day": Game.settings["time_of_day"],
		"weather": Game.settings["weather"],
		"day_cycle": int(Game.settings["day_cycle"]),
		"weather_seed": randi() % 100000,
		"online": false,
		"collisions": true,
	}
	_start_world(cfg)


func _start_world(cfg: Dictionary) -> void:
	last_config = cfg
	_clear_world()
	if menu:
		menu.queue_free()
		menu = null
	if showroom:
		showroom.queue_free()
		showroom = null
	_show_loading(cfg)
	# let the loading screen render before the (blocking) world generation
	await get_tree().process_frame
	await get_tree().process_frame
	world = World.new()
	world.name = "World"
	world.setup(cfg)
	world.exit_requested.connect(_on_world_exit)
	add_child(world)
	_hide_loading()


func _show_loading(cfg: Dictionary) -> void:
	_hide_loading()
	_loading = CanvasLayer.new()
	_loading.layer = 50
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = UiKit.theme()
	_loading.add_child(center)
	var box := UiKit.col([
		UiKit.title("MIDNIGHT DRIFT", 60),
		UiKit.label("Lade %s …" % Game.track_name(str(cfg.get("track", ""))), 24, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER),
		UiKit.label("%s · %s" % [Game.mode_name(str(cfg.get("mode", ""))), Game.time_name(str(cfg.get("time_of_day", "")))], 18, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER),
	])
	center.add_child(box)
	add_child(_loading)


func _hide_loading() -> void:
	if _loading:
		_loading.queue_free()
		_loading = null


func _clear_world() -> void:
	if world:
		remove_child(world)
		world.queue_free()
		world = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_world_exit(target: String) -> void:
	_handle_exit.call_deferred(target)


func _handle_exit(target: String) -> void:
	match target:
		"restart":
			_start_world(last_config)
		"leave":
			Net.leave()
			show_menu("online", "Lobby verlassen.")
		_:
			if Net.is_online:
				show_menu("lobby")
			else:
				show_menu("main")


func _on_race_start(cfg: Dictionary) -> void:
	_start_world(cfg)


func _on_return_lobby() -> void:
	show_menu("lobby")


func _on_disconnected(reason: String) -> void:
	show_menu("online", reason, UiKit.BAD)


# ---------------------------------------------------------------------------
# Smoke test used by CI: builds every screen, both tracks, drives a few seconds, tests hosting.
# ---------------------------------------------------------------------------
func _smoke_test() -> void:
	Game.persist = false
	var shot_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			shot_dir = a.substr(11)
	if "--quick" in OS.get_cmdline_user_args():
		# software rendering in CI is slow: lowest settings (not saved)
		Game.settings["quality"] = 0
		Game.settings["grass_quality"] = 1
		Game.settings["shadow_quality"] = 0
		Game.apply_video()
	var watchdog := get_tree().create_timer(420.0, true, false, true)
	watchdog.timeout.connect(func():
		print("SMOKE TIMEOUT")
		get_tree().quit(1))
	for cid in Game.CAR_ORDER:
		var mp: String = CarBodyScript.MODELS[cid]["path"]
		print("SMOKE: model %s loaded=%s" % [cid, str(load(mp) != null)])
	print("SMOKE: menu")
	show_menu("main")
	for s in ["single", "garage", "online", "leaderboard", "options", "main"]:
		menu.show_screen(s)
		await get_tree().process_frame
	await _shot(shot_dir, "menu")
	var i := 0
	var quick := "--quick" in OS.get_cmdline_user_args()
	var runs: Array = [["ridge", "race"], ["ridge", "free"], ["harbor", "race"], ["harbor", "free"], ["playground", "free"], ["ridge", "graffiti"]]
	if quick:
		runs = [["ridge", "free"], ["harbor", "race"], ["playground", "free"]]
	for run in runs:
		var tr: String = run[0]
		var md: String = run[1]
		print("SMOKE: world %s/%s" % [tr, md])
		var tod: String = ["dusk", "night", "day", "morning"][i % 4]
		i += 1
		Game.settings["car"] = Game.CAR_ORDER[i % Game.CAR_ORDER.size()]
		var weather: String = ["dry", "rain", "changing", "dry"][i % 4]
		_start_world({"track": tr, "mode": md, "laps": 2, "time_of_day": tod, "weather": weather, "day_cycle": 8, "weather_seed": 5, "online": false})
		while world == null:
			await get_tree().process_frame
		for f in 120:
			if f == 40:
				Input.action_press("accelerate")
			if f == 70:
				Input.action_press("steer_left")
				Input.action_press("handbrake")
			await get_tree().physics_frame
		Input.action_release("accelerate")
		Input.action_release("steer_left")
		Input.action_release("handbrake")
		print("SMOKE: car speed %.1f km/h, gear %d, rpm %d, drift %.0f" % [world.local_car.speed_kmh(), world.local_car.gear, int(world.local_car.rpm), world.scorer.total + world.scorer.chain])
		if world.graffiti:
			world.graffiti.spray(world.progress)
			print("SMOKE: graffiti %d cells, held %.0f m" % [world.graffiti.count, world.graffiti_metres(world.local_car)])
		await _shot(shot_dir, "%s_%s" % [tr, md])
		if md == "free":
			world.end_free_session()
		else:
			world._finish()
		await get_tree().process_frame
	print("SMOKE: online host")
	var err := Net.host_lobby("Smoke", 24599, 4, false)
	print("SMOKE: host result '%s'" % err)
	show_menu("lobby")
	await get_tree().process_frame
	Net.send_chat("hallo")
	Net.leave()
	show_menu("main")
	await get_tree().process_frame
	print("SMOKE TEST OK")
	get_tree().quit(0)


func _shot(dir: String, label: String) -> void:
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	for k in 3:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(dir.path_join("%s.png" % label))
