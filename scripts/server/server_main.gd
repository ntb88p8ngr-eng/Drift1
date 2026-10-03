extends Node
## Dedicated server (MidnightDriftServer.exe, or the game started with --server): a lobby without a
## player of its own, run from server.cfg and a console. It starts races when everyone is ready,
## waits for everybody to load, collects the results, goes back to the lobby and on to the next
## track of the rotation. Public servers appear in the in-game server list (joined by short code).
## Console commands: help, status, players, say, kick, start, lobby, track, mode, laps, weather,
## time, code add/del/list, reload, quit.

const CFG_NAME := "server.cfg"
const LOAD_TIMEOUT := 25.0
const RESULTS_WAIT := 20.0
const RACE_MAX := 1800.0

var cfg := ConfigFile.new()
var cfg_path := ""
var rotation: Array = []
var rot_i := 0
var _start_t := -1.0          # auto start countdown (s), -1 = off
var _load_t := -1.0
var _results_t := -1.0
var _race_t := 0.0
var _stdin_thread: Thread
var _lines: Array = []
var _lines_mx := Mutex.new()
var _quit := false


func _ready() -> void:
	Engine.max_fps = 60
	Game.persist = true
	_log("Midnight Drift Server %s" % Game.VERSION)
	cfg_path = _find_cfg()
	_load_cfg()
	var err := Net.host_lobby(_s("name", "Midnight Drift Server"), int(_s("port", Net.DEFAULT_PORT)), int(_s("max_players", 8)),
		bool(_s("upnp", true)), str(_s("password", "")), true, bool(_s("public", true)))
	if err != "":
		_log("FEHLER: " + err)
		get_tree().quit(1)
		return
	Net.motd = str(_s("motd", ""))
	_apply_race_settings()
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.race_start_requested.connect(_on_race_started)
	Net.results_updated.connect(_on_results)
	Net.return_to_lobby_requested.connect(_on_back_in_lobby)
	Net.chat_received.connect(func(who, text): _log("[Chat] %s: %s" % [who, text]))
	_log("Port %d (UDP), max. %d Spieler, %s, %s" % [int(_s("port", Net.DEFAULT_PORT)), int(_s("max_players", 8)),
		"mit Passwort" if str(_s("password", "")) != "" else "ohne Passwort", "öffentlich gelistet" if Net.public_list else "nicht gelistet"])
	_log("Konfiguration: " + ProjectSettings.globalize_path(cfg_path))
	_log("Tippe 'help' für Befehle.")
	_stdin_thread = Thread.new()
	_stdin_thread.start(_read_stdin)


## server.cfg next to the program (if it can be written there), else in the user folder; --config=… wins.
func _find_cfg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--config="):
			return a.substr(9)
	var exe_dir := OS.get_executable_path().get_base_dir()
	if not OS.has_feature("editor"):
		var p := exe_dir.path_join(CFG_NAME)
		if FileAccess.file_exists(p):
			return p
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.close()
			DirAccess.remove_absolute(p)
			return p
	return "user://" + CFG_NAME


func _load_cfg() -> void:
	cfg = ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		_write_default_cfg()
		cfg.load(cfg_path)
		_log("Neue %s mit Standardwerten angelegt." % CFG_NAME)
	rotation = []
	for t in str(cfg.get_value("race", "tracks", "ridge, harbor, tokyo")).split(",", false):
		var id := t.strip_edges()
		for tr in Game.TRACKS:
			if tr["id"] == id:
				rotation.append(id)
	if rotation.is_empty():
		rotation = ["ridge"]
	Net.server_codes = {}
	if cfg.has_section("codes"):
		for k in cfg.get_section_keys("codes"):
			var v = cfg.get_value("codes", k)
			if v is Dictionary:
				Net.server_codes[k.to_upper()] = v


func _write_default_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("server", "name", "Midnight Drift Server")
	c.set_value("server", "port", Net.DEFAULT_PORT)
	c.set_value("server", "max_players", 8)
	c.set_value("server", "password", "")
	c.set_value("server", "public", true)
	c.set_value("server", "upnp", true)
	c.set_value("server", "motd", "Willkommen! Viel Spaß beim Driften.")
	c.set_value("race", "tracks", "ridge, harbor, tokyo, playground, gruene_hoelle")
	c.set_value("race", "mode", "race")
	c.set_value("race", "laps", 3)
	c.set_value("race", "time_of_day", "night")
	c.set_value("race", "weather", "dry")
	c.set_value("race", "day_cycle", 0)
	c.set_value("race", "collisions", true)
	c.set_value("race", "min_players", 1)
	c.set_value("race", "auto_start", 10)
	c.set_value("codes", "WILLKOMMEN", {"credits": 5000})
	c.save(cfg_path)


func _s(key: String, def):
	return cfg.get_value("server", key, def)


func _r(key: String, def):
	return cfg.get_value("race", key, def)


func _apply_race_settings() -> void:
	var mode := str(_r("mode", "race"))
	if not (mode in ["race", "drift", "graffiti"]):
		mode = "race"
	Net.lobby["mode"] = mode
	Net.lobby["track"] = rotation[rot_i % rotation.size()]
	Net.lobby["laps"] = clampi(int(_r("laps", 3)), 1, 50)
	Net.lobby["time_of_day"] = str(_r("time_of_day", "night"))
	Net.lobby["weather"] = str(_r("weather", "dry"))
	Net.lobby["day_cycle"] = int(_r("day_cycle", 0))
	Net.lobby["collisions"] = bool(_r("collisions", true))
	Net.lobby["bots"] = 0
	Net._broadcast_lobby()


# ---------------------------------------------------------------------------
# Race flow
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_run_console()
	if _start_t >= 0.0:
		_start_t -= delta
		if _start_t < 0.0:
			_start_t = -1.0
			_start_race()
	if Net.in_race:
		_race_t += delta
		if _load_t >= 0.0:
			_load_t -= delta
			if _load_t < 0.0 and Net.countdown_t0 < 0:
				_log("Nicht alle haben geladen – Start trotzdem.")
				Net.force_countdown()
		if _results_t >= 0.0:
			_results_t -= delta
			if _results_t < 0.0:
				_back_to_lobby()
		elif _race_t > RACE_MAX:
			_log("Rennzeit abgelaufen.")
			_back_to_lobby()


func _on_lobby_changed() -> void:
	if Net.in_race:
		return
	var n := Net.players.size()
	var ready := n >= int(_r("min_players", 1)) and Net.all_ready()
	if ready and _start_t < 0.0:
		_start_t = float(_r("auto_start", 10))
		Net._chat_all("Server", "Alle bereit – Start in %d Sekunden (%s)." % [int(_start_t), Game.track_name(str(Net.lobby.get("track", "")))])
		_log("Alle bereit – Start in %d s." % int(_start_t))
	elif not ready and _start_t >= 0.0:
		_start_t = -1.0
		Net._chat_all("Server", "Start abgebrochen – nicht alle bereit.")


func _start_race() -> void:
	if Net.players.is_empty():
		_log("Keine Spieler – kein Rennen.")
		return
	var err := Net.host_start_race()
	if err != "":
		_log("Start nicht möglich: " + err)


func _on_race_started(_config: Dictionary) -> void:
	_load_t = LOAD_TIMEOUT
	_results_t = -1.0
	_race_t = 0.0
	_log("Rennen gestartet: %s, %s, %d Spieler." % [Game.track_name(str(Net.lobby.get("track", ""))), Game.mode_name(str(Net.lobby.get("mode", ""))), Net.players.size()])


func _on_results(arr: Array) -> void:
	var done := 0
	for r in arr:
		if bool((r as Dictionary).get("finished", false)):
			done += 1
	if done >= Net.players.size() and _results_t < 0.0:
		_results_t = RESULTS_WAIT
		_log("Alle im Ziel – zurück in die Lobby in %d s." % int(RESULTS_WAIT))
		for r in arr:
			_log("  %s: %s" % [r.get("name", "?"), Game.format_time(float(r.get("time", 0.0)))])


func _back_to_lobby() -> void:
	_results_t = -1.0
	_load_t = -1.0
	Net.host_return_to_lobby()


func _on_back_in_lobby() -> void:
	rot_i += 1
	_apply_race_settings()
	_log("Zurück in der Lobby. Nächste Strecke: %s" % Game.track_name(str(Net.lobby["track"])))
	if Net.motd != "":
		Net._chat_all("Server", Net.motd)


# ---------------------------------------------------------------------------
# Console
# ---------------------------------------------------------------------------
func _read_stdin() -> void:
	while not _quit:
		var line := OS.read_string_from_stdin()
		if line == "":
			OS.delay_msec(100)
			continue
		_lines_mx.lock()
		_lines.append(line.strip_edges())
		_lines_mx.unlock()


func _run_console() -> void:
	_lines_mx.lock()
	var todo := _lines.duplicate()
	_lines.clear()
	_lines_mx.unlock()
	for l in todo:
		if str(l) != "":
			command(str(l))


func command(line: String) -> void:
	var parts := line.split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	var rest := line.substr(parts[0].length()).strip_edges()
	match cmd:
		"help":
			_log("status | players | say <text> | kick <name> | start | lobby | track <id> | mode <race|drift|graffiti> | laps <n>")
			_log("weather <dry|rain|changing> | time <day|dusk|night|morning> | code add <CODE> <credits> [auto] | code del <CODE> | code list | reload | quit")
		"status":
			_log("%s – %s, %d/%d Spieler, %s, Code %s" % [Net.lobby.get("name", ""), "Rennen läuft" if Net.in_race else "Lobby",
				Net.players.size(), int(Net.lobby.get("max_players", 8)), Game.track_name(str(Net.lobby.get("track", ""))), Net.Rendezvous.pretty(Net.host_code)])
		"players":
			for id in Net.players:
				var p: Dictionary = Net.players[id]
				_log("  #%d %s (%s)%s" % [id, p.get("name", "?"), Game.get_car(str(p.get("car", "r34")))["name"], " bereit" if bool(p.get("ready", false)) else ""])
		"say":
			Net._chat_all("Server", rest)
		"kick":
			for id in Net.players.keys():
				if str(Net.players[id].get("name", "")).to_lower() == rest.to_lower():
					Net._kicked.rpc_id(id, "Vom Server entfernt.")
					Net._disconnect_later(id)
					_log("%s entfernt." % rest)
		"start":
			_start_race()
		"lobby":
			if Net.in_race:
				_back_to_lobby()
		"track":
			for tr in Game.TRACKS:
				if tr["id"] == rest:
					Net.lobby["track"] = rest
					Net._broadcast_lobby()
					_log("Strecke: " + str(tr["name"]))
		"mode":
			if rest in ["race", "drift", "graffiti"]:
				Net.lobby["mode"] = rest
				Net._broadcast_lobby()
		"laps":
			Net.lobby["laps"] = clampi(int(rest), 1, 50)
			Net._broadcast_lobby()
		"weather":
			Net.lobby["weather"] = rest
			Net._broadcast_lobby()
		"time":
			Net.lobby["time_of_day"] = rest
			Net._broadcast_lobby()
		"code":
			_code_cmd(parts)
		"reload":
			_load_cfg()
			Net.motd = str(_s("motd", ""))
			_apply_race_settings()
			_log("Konfiguration neu geladen.")
		"quit", "exit", "stop":
			_log("Server wird beendet.")
			Net._chat_all("Server", "Der Server wird beendet.")
			_quit = true
			await get_tree().create_timer(0.5).timeout
			get_tree().quit()
		_:
			_log("Unbekannter Befehl – 'help'")


func _code_cmd(parts: PackedStringArray) -> void:
	var sub := parts[1].to_lower() if parts.size() > 1 else "list"
	match sub:
		"add":
			if parts.size() < 4:
				_log("code add <CODE> <credits> [auto-id]")
				return
			var e := {"credits": int(parts[3])}
			if parts.size() > 4 and Game.CARS.has(parts[4]):
				e["car"] = parts[4]
			Net.server_codes[parts[2].to_upper()] = e
			cfg.set_value("codes", parts[2].to_upper(), e)
			cfg.save(cfg_path)
			_log("Code %s angelegt." % parts[2].to_upper())
		"del":
			if parts.size() > 2:
				Net.server_codes.erase(parts[2].to_upper())
				if cfg.has_section_key("codes", parts[2].to_upper()):
					cfg.erase_section_key("codes", parts[2].to_upper())
				cfg.save(cfg_path)
		_:
			for k in Net.server_codes:
				_log("  %s -> %s" % [k, str(Net.server_codes[k])])


func _log(text: String) -> void:
	print("[%s] %s" % [Time.get_time_string_from_system(), text])


func _exit_tree() -> void:
	_quit = true
	if _stdin_thread and _stdin_thread.is_started():
		# the read blocks until a line comes; the process ends anyway
		pass
