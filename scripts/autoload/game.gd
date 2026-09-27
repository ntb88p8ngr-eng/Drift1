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

## Solid (single colour) paints. metallic/roughness give a glossy clear-coated finish.
const PAINTS := [
	{"id": "red", "name": "Rot", "color": Color(0.62, 0.025, 0.03), "metallic": 0.08, "roughness": 0.2},
	{"id": "white", "name": "Weiß", "color": Color(0.88, 0.88, 0.86), "metallic": 0.0, "roughness": 0.18},
	{"id": "black", "name": "Schwarz", "color": Color(0.018, 0.018, 0.022), "metallic": 0.25, "roughness": 0.16},
	{"id": "silver", "name": "Silber", "color": Color(0.62, 0.63, 0.65), "metallic": 0.75, "roughness": 0.28},
	{"id": "blue", "name": "Bayside Blue", "color": Color(0.03, 0.17, 0.56), "metallic": 0.35, "roughness": 0.22},
	{"id": "yellow", "name": "Gelb", "color": Color(0.92, 0.7, 0.03), "metallic": 0.05, "roughness": 0.2},
]

## Car catalogue. Torque in Nm, masses in kg. All cars start with automatic gearboxes – manual can be
## switched on in the garage or while driving with [M]. Models: see assets/cars (Blend Swap, credits in README).
const CARS := {
	"r34": {
		"name": "Nissan Skyline GT-R R34", "mass": 1540.0, "torque": 440.0, "tach": 9000.0,
		"redline": 8000.0, "idle": 1100.0, "gears": [3.827, 2.36, 1.685, 1.312, 1.0, 0.793], "reverse": 3.28,
		"final": 3.545, "rear_split": 0.8, "turbo": 0.45, "grip": 1.08, "steer_lock": 44.0, "engine": "i6",
		"burble": 1, "transmission": "auto", "desc": "RB26DETT-Reihensechser mit Twin-Turbo, Allrad auf Drift getrimmt (80 % hinten).",
	},
	"mustang": {
		"name": "Ford Mustang GT", "mass": 1690.0, "torque": 560.0, "tach": 8000.0,
		"redline": 7500.0, "idle": 750.0, "gears": [3.66, 2.43, 1.69, 1.32, 1.0, 0.65], "reverse": 3.24,
		"final": 3.73, "rear_split": 1.0, "turbo": 0.0, "grip": 1.05, "steer_lock": 46.0, "engine": "v8",
		"burble": 0, "transmission": "auto", "desc": "5.0-Liter-V8-Sauger mit Hinterradantrieb – viel Drehmoment, lange Drifts.",
	},
	"m3gt3": {
		"name": "BMW M3 GT3", "mass": 1260.0, "torque": 470.0, "tach": 10000.0,
		"redline": 9000.0, "idle": 1100.0, "gears": [3.1, 2.25, 1.75, 1.42, 1.19, 1.02], "reverse": 3.3,
		"final": 4.1, "rear_split": 1.0, "turbo": 0.0, "grip": 1.16, "steer_lock": 43.0, "engine": "v8race",
		"burble": 2, "transmission": "auto", "desc": "Hochdrehender Renn-V8, Leichtbau und Rennfahrwerk – präzise und schnell.",
	},
}
const CAR_ORDER := ["r34", "mustang", "m3gt3"]

## Tuning shop: every category has 4 levels (0 = stock). Costs in credits per level.
const TUNING := [
	{"id": "engine", "name": "Motor", "desc": "+10 % Drehmoment und +250 U/min pro Stufe"},
	{"id": "gearbox", "name": "Getriebe", "desc": "Drift-Übersetzung: längerer 2. und 3. Gang, schnelleres Schalten, ab Stufe 2 kürzere Achse"},
	{"id": "suspension", "name": "Fahrwerk", "desc": "Mehr Grip, straffere Federn und Stabilisatoren"},
	{"id": "steering", "name": "Lenkwinkel", "desc": "Winkel-Kit: +7° / +14° / +22° Lenkeinschlag für größere Driftwinkel"},
	{"id": "turbo", "name": "Turbo", "desc": "Mehr Ladedruck, schnelleres Ansprechen – Sauger bekommen einen Turbo-Kit"},
	{"id": "nitro", "name": "Nitro", "desc": "Stärkerer und längerer Nitro-Boost (Shift)"},
]
const TUNING_LEVELS := ["Serie", "Stufe 1", "Stufe 2", "Stufe 3"]
## Burble-Tune (software map for overrun pops and backfire flames) – free to change per car.
const BURBLE_LEVELS := ["Aus", "Mild", "Sport", "Brutal"]
const BURBLE_DESC := [
	"Keine Fehlzündungen – sauberes Schiebegeräusch.",
	"Leises Blubbern beim Gaswegnehmen, selten eine Flamme.",
	"Deutliches Knallen und Blubbern im Schiebebetrieb, Flammen beim Gaswegnehmen und am Begrenzer.",
	"Dauerfeuer im Schiebebetrieb, Knaller und Flammen bei jedem Gaswegnehmen.",
]

## Video options
const WINDOW_MODES := ["Fenster", "Vollbild (randlos)", "Exklusives Vollbild"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]
const AA_MODES := ["Aus", "FXAA", "TAA", "MSAA 2x", "MSAA 4x", "MSAA 8x", "MSAA 4x + FXAA", "MSAA 4x + TAA"]
const UPSCALERS := ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2"]
const VSYNC_MODES := ["Aus", "An", "Adaptiv", "Mailbox"]
const FPS_LIMITS := [0, 30, 60, 90, 120, 144, 165, 240]
const QUALITY_NAMES := ["Niedrig", "Mittel", "Hoch", "Ultra"]
const GRASS_NAMES := ["Aus", "Niedrig", "Mittel", "Hoch", "Ultra"]
const WEATHER_MODES := [
	{"id": "dry", "name": "Trocken"},
	{"id": "rain", "name": "Regen"},
	{"id": "changing", "name": "Wechselhaft"},
]
## Length of a full in-game day in minutes (0 = time stands still)
const DAY_CYCLES := [0, 8, 15, 30, 60]
const TUNING_COST := [0, 3000, 7000, 14000]
## Gearbox stages: ratio multiplier per gear (< 1 = longer gear), final drive and shift time multipliers.
const GEARBOX_STAGES := [
	{"gears": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0], "final": 1.0, "shift": 1.0},
	{"gears": [1.0, 0.93, 0.96, 1.0, 1.0, 1.0], "final": 1.0, "shift": 0.8},
	{"gears": [1.0, 0.88, 0.93, 0.97, 1.0, 1.0], "final": 1.03, "shift": 0.65},
	{"gears": [1.0, 0.83, 0.9, 0.95, 0.98, 1.0], "final": 1.06, "shift": 0.5},
]
## Extra steering lock (degrees) per steering-kit stage.
const STEER_KIT := [0.0, 7.0, 14.0, 22.0]

var settings := {
	"player_name": "Driver",
	"car": "r34",
	"paint": "red",
	"custom_color": "",
	"transmission": "auto",
	"track": "ridge",
	"mode": "free",
	"laps": 3,
	"time_of_day": "dusk",
	"master_volume": 0.8,
	"engine_volume": 1.0,
	"fullscreen": false,
	"window_mode": 0,
	"resolution": "",
	"aa": 6,
	"upscaler": 0,
	"sharpness": 0.6,
	"vsync": 1,
	"max_fps": 0,
	"gamma": 1.0,
	"shadow_quality": 2,
	"grass_quality": 2,
	"view_distance": 1200,
	"lens_flares": true,
	"quality": 2,
	"weather": "dry",
	"day_cycle": 0,
	"fov": 75.0,
	"mouse_sensitivity": 0.25,
	"steer_assist": 0.55,
	"weather_volume": 0.6,
	"handbrake_strength": 0.75,
	"slide": 0.5,
	"camera_mode": 0,
	"camera_smoothing": 0.6,
	"units_kmh": true,
	"last_ip": "127.0.0.1",
	"port": 24570,
	"lobby_name": "",
	"max_players": 8,
	"use_upnp": true,
	"credits": 12000,
	"tuning": {},
	"burble": {},
}

## leaderboard[track_id][category] = Array of entries (sorted best first)
## categories: "drift" (points per session), "combo" (best single drift), "lap" (best lap seconds), "race" (race time)
var leaderboard := {}

## Set by the menu before loading the world.
var pending_config := {}
## False while automated tests run, so they never overwrite the player's settings file.
var persist := true


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
	_add_action("shift_up", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_add_action("nitro", [KEY_SHIFT], [JOY_BUTTON_B], [])
	_add_action("shift_down", [KEY_Q, KEY_CTRL], [JOY_BUTTON_LEFT_SHOULDER], [])
	_add_action("toggle_transmission", [KEY_M], [], [])
	_add_action("camera_next", [KEY_C], [JOY_BUTTON_Y], [])
	_add_action("camera_free", [KEY_V], [JOY_BUTTON_RIGHT_STICK], [])
	_add_action("look_back", [KEY_B], [JOY_BUTTON_X], [])
	_add_action("reset_car", [KEY_R], [JOY_BUTTON_BACK], [])
	_add_action("lights", [KEY_L], [JOY_BUTTON_DPAD_UP], [])
	_add_action("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_add_action("scoreboard", [KEY_TAB], [JOY_BUTTON_DPAD_DOWN], [])
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
	["W + S im Stand", "Launch Control / Burnout (S loslassen = Start)"],
	["A D / ← → / Stick", "Lenken"],
	["Leertaste / (A)", "Handbremse – mit Gas drehen die Hinterräder weiter"],
	["Shift / (B)", "Nitro"],
	["E / RB", "Hochschalten (manuell)"],
	["Q / Strg / LB", "Runterschalten (manuell)"],
	["M", "Automatik ⇄ Manuell"],
	["C / (Y)", "Kamera wechseln"],
	["V / R-Stick-Klick", "Kamera-Lock lösen (freie Kamera, Maus)"],
	["Rechte Maustaste halten", "Kurz umsehen"],
	["B / (X)", "Nach hinten schauen"],
	["R / Back", "Auto auf Strecke zurücksetzen"],
	["L", "Licht an/aus"],
	["Tab", "Leaderboard / Spielerliste"],
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
		if not data.has("window_mode") and bool(data.get("fullscreen", false)):
			settings["window_mode"] = 1
	if not CARS.has(settings["car"]):
		settings["car"] = "r34"
	var paint_known: bool = settings["paint"] == "custom"
	for p in PAINTS:
		if p["id"] == settings["paint"]:
			paint_known = true
	if not paint_known:
		settings["paint"] = "red"
	settings["laps"] = int(settings["laps"])
	settings["quality"] = int(settings["quality"])
	settings["port"] = int(settings["port"])
	settings["max_players"] = int(settings["max_players"])
	settings["camera_mode"] = int(settings["camera_mode"])
	settings["credits"] = int(settings["credits"])
	for key in ["window_mode", "aa", "upscaler", "vsync", "max_fps", "shadow_quality", "grass_quality", "day_cycle", "view_distance"]:
		settings[key] = int(settings[key])
	settings["resolution"] = str(settings["resolution"])
	if not (settings["tuning"] is Dictionary):
		settings["tuning"] = {}
	if not (settings["burble"] is Dictionary):
		settings["burble"] = {}


func save_settings() -> void:
	if persist:
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
	apply_video()


## Window mode, resolution, anti-aliasing, upscaling, vsync, fps limit, shadows and gamma.
func apply_video() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var mode := clampi(int(settings["window_mode"]), 0, 2)
	var res := selected_resolution()
	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		var target: DisplayServer.WindowMode = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][mode]
		if DisplayServer.window_get_mode() != target:
			DisplayServer.window_set_mode(target)
		if mode == 0 and DisplayServer.window_get_size() != res:
			DisplayServer.window_set_size(res)
			var screen := DisplayServer.window_get_current_screen()
			var origin := DisplayServer.screen_get_position(screen)
			var ss := DisplayServer.screen_get_size(screen)
			DisplayServer.window_set_position(origin + (ss - res) / 2)
		var vs: DisplayServer.VSyncMode = [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
			DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX][clampi(int(settings["vsync"]), 0, 3)]
		DisplayServer.window_set_vsync_mode(vs)
	Engine.max_fps = maxi(int(settings["max_fps"]), 0)
	# fullscreen: the chosen resolution is the 3D render resolution (the UI stays sharp)
	var scale := 1.0
	if mode != 0 and windowed:
		var win_h := maxi(DisplayServer.window_get_size().y, 1)
		scale = clampf(float(res.y) / float(win_h), 0.25, 1.0)
	var up := clampi(int(settings["upscaler"]), 0, 2)
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][up]
	vp.scaling_3d_scale = scale
	vp.fsr_sharpness = (1.0 - clampf(float(settings["sharpness"]), 0.0, 1.0)) * 2.0
	var aa := clampi(int(settings["aa"]), 0, AA_MODES.size() - 1)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X,
		Viewport.MSAA_4X, Viewport.MSAA_8X, Viewport.MSAA_4X, Viewport.MSAA_4X][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 or aa == 6 else Viewport.SCREEN_SPACE_AA_DISABLED
	# FSR 2 brings its own temporal anti-aliasing
	vp.use_taa = (aa == 2 or aa == 7) and up != 2
	var sq := clampi(int(settings["shadow_quality"]), 0, 3)
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][sq], true)
	var soft: RenderingServer.ShadowQuality = [RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sq]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	vp.positional_shadow_atlas_size = [1024, 2048, 4096, 4096][sq]
	_apply_gamma(float(settings["gamma"]))


func available_resolutions() -> Array:
	var screen := Vector2i(1920, 1080)
	if DisplayServer.get_name() != "headless":
		screen = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var out: Array = []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	if not out.has(screen):
		out.append(screen)
	out.sort_custom(func(a, b): return a.x * a.y < b.x * b.y)
	return out


static func resolution_key(r: Vector2i) -> String:
	return "%dx%d" % [r.x, r.y]


## The configured resolution, or the screen resolution when none is set / it does not fit.
func selected_resolution() -> Vector2i:
	var list := available_resolutions()
	var key := str(settings["resolution"])
	for r in list:
		if resolution_key(r) == key:
			return r
	if int(settings["window_mode"]) == 0:
		# default window: 1600x900 or the largest that fits
		var best: Vector2i = list[0]
		for r in list:
			if r.x <= 1600:
				best = r
		return best
	return list[list.size() - 1]


var _gamma_layer: CanvasLayer
var _gamma_mat: ShaderMaterial

const GAMMA_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float gamma = 1.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(pow(max(c, vec3(0.0)), vec3(1.0 / gamma)), 1.0);
}
"""


## Gamma correction as a full-screen post pass on top of everything (only active when != 1.0).
func _apply_gamma(g: float) -> void:
	var active := absf(g - 1.0) > 0.01
	if _gamma_layer == null:
		if not active:
			return
		_gamma_layer = CanvasLayer.new()
		_gamma_layer.layer = 127
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = GAMMA_SHADER
		_gamma_mat = ShaderMaterial.new()
		_gamma_mat.shader = sh
		rect.material = _gamma_mat
		_gamma_layer.add_child(rect)
		add_child(_gamma_layer)
	_gamma_layer.visible = active
	_gamma_mat.set_shader_parameter("gamma", clampf(g, 0.3, 3.0))


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
		var c := Color.from_string(custom_html, Color(0.6, 0.03, 0.03))
		return {"id": "custom", "name": "Eigene Farbe", "color": c, "metallic": 0.1, "roughness": 0.2}
	for p in PAINTS:
		if p["id"] == paint_id:
			return p
	return PAINTS[0]


# ---------------------------------------------------------------------------
# Tuning & credits
# ---------------------------------------------------------------------------
func get_tuning(car_id: String) -> Dictionary:
	var all: Dictionary = settings["tuning"]
	var t: Dictionary = all.get(car_id, {})
	var out := {}
	for c in TUNING:
		out[c["id"]] = int(t.get(c["id"], 0))
	return out


## Gear ratios, final drive, shift time factor and redline of a car including its tuning.
func tuned_gearing(car_id: String) -> Dictionary:
	var car := get_car(car_id)
	var t := get_tuning(car_id)
	var st: Dictionary = GEARBOX_STAGES[clampi(int(t["gearbox"]), 0, GEARBOX_STAGES.size() - 1)]
	var mult: Array = st["gears"]
	var src: Array = car["gears"]
	var g: Array = []
	for i in src.size():
		g.append(float(src[i]) * float(mult[mini(i, mult.size() - 1)]))
	return {"gears": g, "final": float(car["final"]) * float(st["final"]), "shift": float(st["shift"]),
		"redline": float(car["redline"]) + 250.0 * int(t["engine"])}


func tuning_cost(car_id: String, category: String) -> int:
	var lvl: int = get_tuning(car_id)[category]
	if lvl >= TUNING_LEVELS.size() - 1:
		return -1
	return TUNING_COST[lvl + 1]


## Buys the next level; returns "" on success or an error text.
func buy_tuning(car_id: String, category: String) -> String:
	var cost := tuning_cost(car_id, category)
	if cost < 0:
		return "Maximale Stufe erreicht."
	if int(settings["credits"]) < cost:
		return "Nicht genug Credits (%s benötigt)." % format_points(cost)
	settings["credits"] = int(settings["credits"]) - cost
	var all: Dictionary = settings["tuning"]
	var t: Dictionary = all.get(car_id, {})
	t[category] = int(t.get(category, 0)) + 1
	all[car_id] = t
	settings["tuning"] = all
	save_settings()
	return ""


## Sells back the last level of a category for half the price.
func downgrade_tuning(car_id: String, category: String) -> void:
	var lvl: int = get_tuning(car_id)[category]
	if lvl <= 0:
		return
	settings["credits"] = int(settings["credits"]) + TUNING_COST[lvl] / 2
	var all: Dictionary = settings["tuning"]
	var t: Dictionary = all.get(car_id, {})
	t[category] = lvl - 1
	all[car_id] = t
	settings["tuning"] = all
	save_settings()


## Burble-Tune level of a car (0 = off … 3 = brutal); the car's factory default until changed.
func get_burble(car_id: String) -> int:
	var all: Dictionary = settings["burble"]
	return clampi(int(all.get(car_id, get_car(car_id).get("burble", 1))), 0, BURBLE_LEVELS.size() - 1)


func set_burble(car_id: String, level: int) -> void:
	var all: Dictionary = settings["burble"]
	all[car_id] = clampi(level, 0, BURBLE_LEVELS.size() - 1)
	settings["burble"] = all
	save_settings()
	settings_changed.emit()


func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	settings["credits"] = int(settings["credits"]) + amount
	save_settings()


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


func weather_name(weather_id: String) -> String:
	for w in WEATHER_MODES:
		if w["id"] == weather_id:
			return w["name"]
	return weather_id


func day_cycle_name(minutes: int) -> String:
	return "Aus (feste Uhrzeit)" if minutes <= 0 else "%d Minuten pro Tag" % minutes


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
		"burble": get_burble(str(settings["car"])),
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
	if persist:
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
