extends Node
## Global game state: settings, car/paint catalogue, input map and the local leaderboard.

signal settings_changed

const VERSION := "1.0.0"
const SETTINGS_PATH := "user://settings.json"
const LEADERBOARD_PATH := "user://leaderboard.json"
const LEADERBOARD_SIZE := 10

const TRACKS := [
	{"id": "ridge", "name": "Kurohana Ridge", "desc": "Fließende Bergstrecke im Wald – lange Sweeper, eine Haarnadel, perfekt für Übergänge."},
	{"id": "harbor", "name": "Harbor Drift Yard", "desc": "Breiter Industriekurs am Hafen – enge Kehren zwischen Containern und Lagerhallen."},
]

const MODES := [
	{"id": "free", "name": "Freies Driften", "desc": "Kein Zeitlimit – sammle Driftpunkte und jage Rundenzeiten."},
	{"id": "race", "name": "Rennen", "desc": "Wer zuerst alle Runden fährt, gewinnt."},
	{"id": "drift", "name": "Drift-Battle", "desc": "Alle Runden fahren – die meisten Driftpunkte gewinnen."},
]

const TIMES_OF_DAY := [
	{"id": "day", "name": "Mittag"},
	{"id": "dusk", "name": "Sonnenuntergang"},
	{"id": "night", "name": "Nacht"},
	{"id": "morning", "name": "Morgennebel"},
]

## Midnight Purple II is a colour-shifting paint: base colour head-on, flip colour at an angle, edge at grazing angles.
const PAINTS := [
	{"id": "mp2", "name": "Midnight Purple II", "base": Color(0.17, 0.04, 0.30), "flip": Color(0.05, 0.28, 0.20), "edge": Color(0.45, 0.22, 0.06), "flake": 0.45},
	{"id": "mp3", "name": "Midnight Purple III", "base": Color(0.26, 0.09, 0.38), "flip": Color(0.45, 0.34, 0.10), "edge": Color(0.10, 0.30, 0.32), "flake": 0.40},
	{"id": "bayside", "name": "Bayside Blue", "base": Color(0.02, 0.16, 0.55), "flip": Color(0.05, 0.28, 0.66), "edge": Color(0.00, 0.06, 0.24), "flake": 0.30},
	{"id": "jade", "name": "Millennium Jade", "base": Color(0.40, 0.45, 0.41), "flip": Color(0.28, 0.40, 0.37), "edge": Color(0.18, 0.24, 0.24), "flake": 0.35},
	{"id": "pearl", "name": "White Pearl", "base": Color(0.84, 0.84, 0.81), "flip": Color(0.92, 0.88, 0.80), "edge": Color(0.70, 0.72, 0.82), "flake": 0.20},
	{"id": "black", "name": "Black Pearl", "base": Color(0.015, 0.015, 0.02), "flip": Color(0.05, 0.03, 0.07), "edge": Color(0.10, 0.08, 0.12), "flake": 0.50},
	{"id": "red", "name": "Active Red", "base": Color(0.55, 0.02, 0.02), "flip": Color(0.60, 0.08, 0.02), "edge": Color(0.25, 0.00, 0.02), "flake": 0.30},
	{"id": "yellow", "name": "Lightning Yellow", "base": Color(0.90, 0.68, 0.02), "flip": Color(0.95, 0.52, 0.00), "edge": Color(0.50, 0.34, 0.00), "flake": 0.25},
]

## Car catalogue. Torque in Nm, masses in kg. All cars start with automatic gearboxes – manual can be
## switched on in the garage or while driving with [M].
const CARS := {
	"r34": {
		"name": "Skyline GT-R R34 (Verschnitt)", "body": "r34", "mass": 1450.0, "torque": 470.0,
		"redline": 8000.0, "idle": 950.0, "gears": [3.30, 2.10, 1.52, 1.16, 0.93, 0.77], "reverse": 3.3,
		"final": 4.1, "rear_split": 0.8, "turbo": 0.45, "grip": 1.08, "steer_lock": 44.0,
		"transmission": "auto", "desc": "RB26-Reihensechser mit Twin-Turbo, ATTESA auf Drift getrimmt (80 % hinten).",
	},
	"s15": {
		"name": "Silvia S15 (Verschnitt)", "body": "s15", "mass": 1240.0, "torque": 330.0,
		"redline": 7800.0, "idle": 900.0, "gears": [3.32, 1.90, 1.36, 1.06, 0.86, 0.73], "reverse": 3.3,
		"final": 4.3, "rear_split": 1.0, "turbo": 0.4, "grip": 1.02, "steer_lock": 48.0,
		"transmission": "auto", "desc": "Leichter Hecktriebler mit SR20-Turbo – der Drift-Klassiker.",
	},
	"ae86": {
		"name": "Trueno AE86 (Verschnitt)", "body": "ae86", "mass": 960.0, "torque": 190.0,
		"redline": 8200.0, "idle": 1000.0, "gears": [3.59, 2.02, 1.38, 1.00, 0.86], "reverse": 3.5,
		"final": 4.3, "rear_split": 1.0, "turbo": 0.0, "grip": 1.0, "steer_lock": 46.0,
		"transmission": "auto", "desc": "Hochdrehender Sauger, federleicht – Technik schlägt Leistung.",
	},
	"a80": {
		"name": "Supra A80 (Verschnitt)", "body": "a80", "mass": 1500.0, "torque": 560.0,
		"redline": 7200.0, "idle": 850.0, "gears": [3.83, 2.36, 1.69, 1.31, 1.00, 0.79], "reverse": 3.5,
		"final": 3.6, "rear_split": 1.0, "turbo": 0.55, "grip": 1.1, "steer_lock": 42.0,
		"transmission": "auto", "desc": "2JZ-Monster mit riesigem Turbo – viel Leistung, viel Rauch.",
	},
}
const CAR_ORDER := ["r34", "s15", "ae86", "a80"]

var settings := {
	"player_name": "Driver",
	"car": "r34",
	"paint": "mp2",
	"custom_color": "",
	"transmission": "auto",
	"track": "ridge",
	"mode": "free",
	"laps": 3,
	"time_of_day": "dusk",
	"master_volume": 0.8,
	"engine_volume": 1.0,
	"fullscreen": false,
	"quality": 2,
	"fov": 75.0,
	"mouse_sensitivity": 0.25,
	"steer_assist": 0.55,
	"camera_mode": 0,
	"units_kmh": true,
	"last_ip": "127.0.0.1",
	"port": 24570,
	"lobby_name": "",
	"max_players": 8,
	"use_upnp": true,
	"show_hints": true,
}

## leaderboard[track_id][category] = Array of entries (sorted best first)
## categories: "drift" (points per session), "combo" (best single drift), "lap" (best lap seconds), "race" (race time)
var leaderboard := {}

## Set by the menu before loading the world.
var pending_config := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	load_leaderboard()
	apply_settings()


# ---------------------------------------------------------------------------
# Input map (built in code so it is independent of keyboard layout – physical keys)
# ---------------------------------------------------------------------------
func _setup_input() -> void:
	_add_action("accelerate", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add_action("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_add_action("steer_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_action("steer_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_action("handbrake", [KEY_SPACE], [JOY_BUTTON_A], [])
	_add_action("shift_up", [KEY_E, KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_add_action("shift_down", [KEY_Q, KEY_CTRL], [JOY_BUTTON_LEFT_SHOULDER], [])
	_add_action("toggle_transmission", [KEY_M], [], [])
	_add_action("camera_next", [KEY_C], [JOY_BUTTON_Y], [])
	_add_action("camera_free", [KEY_V], [JOY_BUTTON_RIGHT_STICK], [])
	_add_action("look_back", [KEY_B], [JOY_BUTTON_X], [])
	_add_action("reset_car", [KEY_R], [JOY_BUTTON_BACK], [])
	_add_action("lights", [KEY_L], [JOY_BUTTON_DPAD_UP], [])
	_add_action("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_add_action("scoreboard", [KEY_TAB], [JOY_BUTTON_DPAD_DOWN], [])
	_add_action("toggle_hints", [KEY_F1], [], [])
	_add_action("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_add_action("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_add_action("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_add_action("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])


func _add_action(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.15)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(action, jm)


const CONTROLS_HELP := [
	["W / ↑ / RT", "Gas"],
	["S / ↓ / LT", "Bremse / Rückwärts"],
	["A D / ← → / Stick", "Lenken"],
	["Leertaste / (A)", "Handbremse – Drift einleiten"],
	["E / Shift / RB", "Hochschalten (manuell)"],
	["Q / Strg / LB", "Runterschalten (manuell)"],
	["M", "Automatik ⇄ Manuell"],
	["C / (Y)", "Kamera wechseln"],
	["V / R-Stick-Klick", "Kamera-Lock lösen (freie Kamera, Maus)"],
	["Rechte Maustaste halten", "Kurz umsehen"],
	["B / (X)", "Nach hinten schauen"],
	["R / Back", "Auto auf Strecke zurücksetzen"],
	["L", "Licht an/aus"],
	["Tab", "Leaderboard / Spielerliste"],
	["F1", "Hilfe ein/aus"],
	["Esc / Start", "Pause"],
]


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
func load_settings() -> void:
	var data = _read_json(SETTINGS_PATH)
	if data is Dictionary:
		for k in data.keys():
			if settings.has(k):
				settings[k] = data[k]
	if not CARS.has(settings["car"]):
		settings["car"] = "r34"
	settings["laps"] = int(settings["laps"])
	settings["quality"] = int(settings["quality"])
	settings["port"] = int(settings["port"])
	settings["max_players"] = int(settings["max_players"])
	settings["camera_mode"] = int(settings["camera_mode"])


func save_settings() -> void:
	_write_json(SETTINGS_PATH, settings)
	settings_changed.emit()


func set_setting(key: String, value) -> void:
	settings[key] = value
	save_settings()
	apply_settings()


func apply_settings() -> void:
	var vol := clampf(float(settings["master_volume"]), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(0, vol <= 0.001)
	if DisplayServer.get_name() != "headless":
		var want_fs := bool(settings["fullscreen"])
		var mode := DisplayServer.window_get_mode()
		var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_fs and not is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not want_fs and is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var q := int(settings["quality"])
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][clampi(q, 0, 3)]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q >= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.scaling_3d_scale = 0.75 if q == 0 else 1.0
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][clampi(q, 0, 3)], true)


func quality() -> int:
	return int(settings["quality"])


# ---------------------------------------------------------------------------
# Catalogue helpers
# ---------------------------------------------------------------------------
func get_car(car_id: String) -> Dictionary:
	if CARS.has(car_id):
		return CARS[car_id]
	return CARS["r34"]


func get_paint(paint_id: String, custom_html: String = "") -> Dictionary:
	if paint_id == "custom" and custom_html != "":
		var c := Color.from_string(custom_html, Color(0.2, 0.05, 0.3))
		return {"id": "custom", "name": "Eigene Farbe", "base": c, "flip": c.lightened(0.15).lerp(Color(c.b, c.r, c.g), 0.25), "edge": c.darkened(0.4), "flake": 0.35}
	for p in PAINTS:
		if p["id"] == paint_id:
			return p
	return PAINTS[0]


func track_name(track_id: String) -> String:
	for t in TRACKS:
		if t["id"] == track_id:
			return t["name"]
	return track_id


func mode_name(mode_id: String) -> String:
	for m in MODES:
		if m["id"] == mode_id:
			return m["name"]
	return mode_id


func time_name(tod_id: String) -> String:
	for t in TIMES_OF_DAY:
		if t["id"] == tod_id:
			return t["name"]
	return tod_id


func local_player_info() -> Dictionary:
	return {
		"name": str(settings["player_name"]).substr(0, 20),
		"car": settings["car"],
		"paint": settings["paint"],
		"custom_color": settings["custom_color"],
		"transmission": settings["transmission"],
		"ready": false,
		"version": VERSION,
	}


# ---------------------------------------------------------------------------
# Leaderboard (local, persisted in user://leaderboard.json)
# ---------------------------------------------------------------------------
func load_leaderboard() -> void:
	var data = _read_json(LEADERBOARD_PATH)
	leaderboard = data if data is Dictionary else {}


func save_leaderboard() -> void:
	_write_json(LEADERBOARD_PATH, leaderboard)


## Returns the 1-based rank the entry landed on, or 0 if it did not make the list.
func submit_score(track_id: String, category: String, player: String, value: float, car_id: String, extra: String = "") -> int:
	if value <= 0.0:
		return 0
	if not leaderboard.has(track_id):
		leaderboard[track_id] = {}
	var board: Dictionary = leaderboard[track_id]
	if not board.has(category):
		board[category] = []
	var entries: Array = board[category]
	var entry := {"name": player, "value": value, "car": car_id, "date": Time.get_date_string_from_system(), "extra": extra}
	entries.append(entry)
	var lower_is_better := category == "lap" or category == "race"
	if lower_is_better:
		entries.sort_custom(func(a, b): return float(a["value"]) < float(b["value"]))
	else:
		entries.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
	while entries.size() > LEADERBOARD_SIZE:
		entries.pop_back()
	board[category] = entries
	save_leaderboard()
	var idx := entries.find(entry)
	return idx + 1 if idx >= 0 else 0


func get_scores(track_id: String, category: String) -> Array:
	if leaderboard.has(track_id) and leaderboard[track_id].has(category):
		return leaderboard[track_id][category]
	return []


func clear_leaderboard() -> void:
	leaderboard = {}
	save_leaderboard()


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------
static func format_time(seconds: float) -> String:
	if seconds <= 0.0 or seconds >= 1e8:
		return "--:--.---"
	var m := int(seconds / 60.0)
	var s := fmod(seconds, 60.0)
	return "%d:%06.3f" % [m, s]


static func format_points(points: float) -> String:
	var n := int(points)
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if n < 0 else "") + out


# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------
func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Konnte %s nicht schreiben" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
