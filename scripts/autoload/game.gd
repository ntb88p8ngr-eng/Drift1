extends Node
## Global game state: settings, car/paint catalogue, input map and the local leaderboard.

signal settings_changed
signal language_changed

const VERSION := "0.0.7"
const EnTexts = preload("res://scripts/i18n/en.gd")
## Languages: [locale, name in that language]
const LANGUAGES := [["de", "Deutsch"], ["en", "English"]]
const SETTINGS_PATH := "user://settings.json"
const LEADERBOARD_PATH := "user://leaderboard.json"
const LEADERBOARD_SIZE := 10

const TRACKS := [
	{"id": "ridge", "name": "Kurohana Ridge", "desc": "Fließende Bergstrecke im Wald – lange Sweeper, eine Haarnadel, perfekt für Übergänge."},
	{"id": "harbor", "name": "Harbor Drift Yard", "desc": "Breiter Industriekurs am Hafen – enge Kehren zwischen Containern und Lagerhallen."},
	{"id": "playground", "name": "Playground", "desc": "Riesige Asphaltfläche zum Driften üben – eine Achter-Strecke, Pylonen-Slaloms, Donut-Kreise und überall Fässer, Kisten und Reifen zum Wegschubsen."},
	{"id": "tokyo", "name": "Neo Tokyo", "desc": "Japanische Großstadt: Scramble-Kreuzung mit Riesen-Bildschirmen, enge 90°-Ecken zwischen Hochhäusern, eine Stadtautobahn-Schleife auf Stelzen, Kirschblüten, Neonschilder – nachts am schönsten."},
	{"id": "utah", "name": "Utah Desert", "desc": "Hügelige Wüste in Utah: eine verwinkelte Strecke voller Haarnadeln und S-Kurven über Kuppen und durch Senken, mal Asphalt, mal loser Sand. In der Mitte ein See mit Ringstraße, Motel, Diner und Tankstelle, ein Fluss mit Staudamm und Brücken, Kakteen, Felsformationen und Tafelberge."},
	{"id": "gruene_hoelle", "name": "Grüne Hölle", "desc": "Nachbau der Nordschleife aus echten Karten- und Höhendaten – 20,5 km durch die Eifel, fast 300 m Höhenunterschied, von Hatzenbach über Karussell bis Döttinger Höhe."},
]

## The city maps: flat paved ground, no forest, their own street furniture and lights.
const CITY_TRACKS := ["tokyo"]


static func is_city(id: String) -> bool:
	return CITY_TRACKS.has(id)


## The desert maps: sand instead of grass, cacti and boulders instead of forest, a fog bank round them.
const DESERT_TRACKS := ["utah"]


static func is_desert(id: String) -> bool:
	return DESERT_TRACKS.has(id)


const MODES := [
	{"id": "free", "name": "Freies Driften", "desc": "Kein Zeitlimit – sammle Driftpunkte und jage Rundenzeiten."},
	{"id": "race", "name": "Rennen", "desc": "Wer zuerst alle Runden fährt, gewinnt."},
	{"id": "drift", "name": "Drift-Battle", "desc": "Alle Runden fahren – die meisten Driftpunkte gewinnen."},
	{"id": "graffiti", "name": "Graffiti", "desc": "Drifte über die Strecke, um sie in deiner Autofarbe zu markieren – bis jemand drüberdriftet. Nach Ablauf der eingestellten Zeit gewinnt, wer die meiste Strecke hält."},
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
## switched on in the garage or while driving with [T]. Models: see assets/cars (Blend Swap, credits in README).
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
		"redline": 9000.0, "idle": 900.0, "gears": [3.1, 2.25, 1.75, 1.42, 1.19, 1.02], "reverse": 3.3,
		"final": 4.1, "rear_split": 1.0, "turbo": 0.0, "grip": 1.16, "steer_lock": 43.0, "engine": "v8deep",
		"spin_hold": 0.88, "yaw_damp": 1.6,
		"burble": 2, "transmission": "auto", "desc": "Hochdrehender Renn-V8, Leichtbau und Rennfahrwerk – präzise und schnell.",
	},
	"m3e46": {
		"name": "BMW M3 E46", "mass": 1570.0, "torque": 365.0, "tach": 9000.0,
		"redline": 8000.0, "idle": 850.0, "gears": [4.23, 2.53, 1.67, 1.23, 1.0, 0.83], "reverse": 3.75,
		"final": 3.62, "rear_split": 1.0, "turbo": 0.0, "grip": 1.04, "steer_lock": 45.0, "engine": "i6na",
		"burble": 1, "transmission": "auto", "desc": "S54-Reihensechser-Sauger bis 8000 U/min, Hinterradantrieb – der Klassiker unter den Drift-BMWs.",
	},
	"m4f82": {
		"name": "BMW M4 F82", "mass": 1570.0, "torque": 550.0, "tach": 8000.0,
		"redline": 7300.0, "idle": 750.0, "gears": [4.11, 2.32, 1.54, 1.18, 1.0, 0.85], "reverse": 3.68,
		"final": 3.46, "rear_split": 1.0, "turbo": 0.4, "grip": 1.06, "steer_lock": 45.0, "engine": "i6tt",
		"burble": 2, "transmission": "auto", "desc": "S55-Biturbo-Reihensechser mit brachialem Drehmoment – das Heck will immer quer.",
	},
	"gt3rsr": {
		"name": "Porsche 911 GT3 RSR", "mass": 1225.0, "torque": 440.0, "tach": 10000.0,
		"redline": 9400.0, "idle": 1100.0, "gears": [3.15, 2.18, 1.71, 1.39, 1.16, 1.0], "reverse": 3.0,
		"final": 3.44, "rear_split": 1.0, "turbo": 0.0, "grip": 1.18, "steer_lock": 42.0, "engine": "flat6",
		"spin_hold": 0.98, "yaw_damp": 1.5,
		"burble": 2, "transmission": "auto", "desc": "Boxer-Rennmotor im Heck, Leichtbau und Slicks – kreischt bis 9400 U/min.",
	},
	"gallardo": {
		"name": "Lamborghini Gallardo", "mass": 1430.0, "torque": 510.0, "tach": 9000.0,
		"redline": 8000.0, "idle": 950.0, "gears": [3.91, 2.44, 1.81, 1.46, 1.19, 0.97], "reverse": 2.69,
		"final": 3.54, "rear_split": 0.75, "turbo": 0.0, "grip": 1.12, "steer_lock": 42.0, "engine": "v10",
		"burble": 2, "transmission": "auto", "desc": "5.0-Liter-V10-Sauger, Allrad mit Hecklastigkeit – heller, heiserer Sound.",
	},
	"aventador": {
		"name": "Lamborghini Aventador", "mass": 1575.0, "torque": 690.0, "tach": 9500.0,
		"redline": 8500.0, "idle": 1000.0, "gears": [3.91, 2.44, 1.81, 1.46, 1.19, 0.97], "reverse": 2.9,
		"final": 2.87, "rear_split": 0.72, "turbo": 0.0, "grip": 1.14, "steer_lock": 40.0, "engine": "v12",
		"burble": 3, "transmission": "auto", "desc": "6.5-Liter-V12 mit 700 PS und Allrad – brutal schnell, Flammen beim Gaswegnehmen.",
	},
	"supra": {
		"name": "Toyota Supra A80", "mass": 1460.0, "torque": 650.0, "tach": 9000.0,
		"redline": 8000.0, "idle": 850.0, "gears": [3.83, 2.36, 1.69, 1.31, 1.0, 0.79], "reverse": 3.28,
		"final": 3.27, "rear_split": 1.0, "turbo": 0.6, "grip": 1.06, "steer_lock": 46.0, "engine": "i6tt",
		"burble": 2, "transmission": "auto", "desc": "2JZ-Biturbo-Reihensechser, auf 600 PS gebracht – gebaut für leere Autobahnen bei Nacht.",
	},
	# easter eggs: only through an action code (see EGG_CODES), never in the shop
	"yaris": {
		"name": "Toyota Yaris (Bouncing)", "mass": 960.0, "torque": 124.0, "tach": 8000.0,
		"redline": 6500.0, "idle": 800.0, "gears": [3.55, 1.9, 1.31, 1.03, 0.82], "reverse": 3.25,
		"final": 4.31, "rear_split": 0.0, "turbo": 0.0, "grip": 1.0, "steer_lock": 42.0, "engine": "i6na",
		"burble": 0, "transmission": "auto", "egg": true,
		# the suspension never settles and the body wobbles like jelly (the "Bouncing Yaris" meme)
		"bounce": 1.0, "jelly": 1.0,
		"desc": "1.3 VVT-i, 87 PS – und eine Federung, die nie zur Ruhe kommt.",
	},
	"m6gt3": {
		"name": "BMW M6 GT3", "mass": 1300.0, "torque": 700.0, "tach": 8000.0,
		"redline": 7200.0, "idle": 950.0, "gears": [3.0, 2.2, 1.73, 1.42, 1.2, 1.03], "reverse": 3.2,
		"final": 3.4, "rear_split": 1.0, "turbo": 0.5, "grip": 1.17, "steer_lock": 42.0, "engine": "v8deep",
		"spin_hold": 0.9, "yaw_damp": 1.5, "burble": 3, "transmission": "auto", "egg": true, "fixed_livery": true,
		"desc": "4.4-Liter-Biturbo-V8 im Motorsport-Trimm – nur in der originalen Lackierung.",
	},
}
const CAR_ORDER := ["r34", "mustang", "m3gt3", "m3e46", "m4f82", "supra", "gt3rsr", "gallardo", "aventador", "yaris", "m6gt3"]

## Tuning shop: every category has 4 levels (0 = stock). Costs in credits per level.
const TUNING := [
	{"id": "engine", "name": "Motor", "desc": "+20 % Drehmoment und +250 U/min pro Stufe – die Hinterräder drehen deutlich leichter durch"},
	{"id": "gearbox", "name": "Getriebe", "desc": "Drift-Übersetzung: längerer 2. und 3. Gang, schnelleres Schalten, ab Stufe 2 kürzere Achse"},
	{"id": "suspension", "name": "Fahrwerk", "desc": "Mehr Grip, straffere Federn und Stabilisatoren"},
	{"id": "tyres", "name": "Reifen", "desc": "Weichere Mischung für mehr Grip: Sport / Semi-Slick / Slick (+6 % pro Stufe)"},
	{"id": "steering", "name": "Lenkwinkel", "desc": "Winkel-Kit: +7° / +14° / +22° Lenkeinschlag für größere Driftwinkel"},
	{"id": "turbo", "name": "Turbo", "desc": "Mehr Ladedruck, schnelleres Ansprechen – Sauger bekommen einen Turbo-Kit"},
	{"id": "nitro", "name": "Nitro", "desc": "Stärkerer und längerer Nitro-Boost (Shift)"},
	{"id": "brakes", "name": "Bremsen", "desc": "Sportbremsanlage: +15 % Bremskraft und besser dosierbar pro Stufe – bis zu 13 % kürzerer Bremsweg"},
]
## Underglow (free cosmetic): modes for the sides that are set to "Flasher".
const UNDERGLOW_MODES := ["Dauerlicht", "Pulsieren", "Blinken", "Stroboskop", "Doppelblitz", "Schnellblinken", "Atmen", "Regenbogen"]
const UNDERGLOW_SIDES := [["front", "Vorne"], ["rear", "Hinten"], ["left", "Links"], ["right", "Rechts"]]
## Graffiti mode: selectable match length in minutes.
const GRAFFITI_MINUTES := [2, 5, 10, 15]
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
## Motion blur (camera post effect, see camera_rig.gd): off / strength levels
const MOTION_BLUR_NAMES := ["Aus", "Leicht", "Mittel", "Stark"]
const ART_STYLE_NAMES := ["Aus", "Retro 90er", "Comic"]
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
	"language": "de",          # de (the source texts) / en (scripts/i18n/en.gd)
	"car": "r34",
	"paint": "red",
	"custom_color": "",
	"transmission": "auto",
	"track": "ridge",
	"mode": "free",
	"laps": 3,
	"graffiti_minutes": 5,
	"motion_blur": 0,
	"art_style": 0,
	"bots": 0,
	"bot_level": 1,
	"party": false,
	"traffic": 0,       # NPC traffic density 0 (off) .. 4 (rush hour), see traffic.gd
	"traffic_speed": 1, # NPC traffic speed: traffic.gd SPEEDS index (30 .. 120 km/h)
	"custom_map": "",     # world editor map to race on (user://maps/*.dmap), "" = the original track
	"party_games": 3,
	"party_coins": 5,
	"party_coins_city": false,      # Neo Tokyo: coins spread over the whole city (not just the route)
	"time_of_day": "dusk",
	"master_volume": 0.8,
	"audio_output": "Default",
	"audio_input": "Default",
	"mic_volume": 1.0,
	"engine_volume": 1.0,
	"fullscreen": false,
	"window_mode": 0,
	"resolution": "",
	"aa": 7,
	"aa_rev": 1,
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
	"abs": true,
	"esp": false,
	"weather_volume": 0.6,
	"menu_sfx_volume": 0.35,       # the main menu's storm (rain, thunder): quiet unless turned up
	# car radio (see radio.gd): on / volume 0..1 / band FM1|FM2 / preset per band / radio|tape / inserted tape
	"radio": {"on": false, "volume": 0.5, "band": 0, "preset": [0, 0], "mode": "radio", "tape": "", "api": true},
	"radio_slots": [],            # the presets' stations by address [[6 x FM1], [6 x FM2]], [] = built-in
	"radio_custom": [],           # own stations: {ps, name, url, freq}
	"radio_menu": true,
	"radio_hud": true,             # the small radio in a race (bottom left) shown            # the floating radio in the main menu shown
	"cassettes": ["garage_mix"],   # tapes found so far (in the garage's cabinet), see radio.gd TAPES
	"menu_lights": {"ceiling": 1.0, "platform": 1.0, "platform_color": "#ff0505"},
	"handbrake_strength": 0.75,
	"slide": 0.5,
	"camera_mode": 0,
	"camera_smoothing": 0.6,
	"camera_zoom": 1.2,
	"camera_tilt": 0.0,
	"show_fps": false,
	"nav_arrow": true,
	"show_perf": false,
	"units_kmh": true,
	"last_ip": "127.0.0.1",
	"lobby_password": "",
	"port": 24570,
	"lobby_name": "",
	"max_players": 8,
	"use_upnp": true,
	"credits": 12000,
	"owned_cars": [],      # bought (and unlocked) cars; the first FREE_CARS of CAR_ORDER are always owned
	"redeemed_codes": [],  # action codes used already (each only once)
	"admin_codes": {},     # action codes made in the admin menu: CODE -> {credits, car}
	"admin_mode": false,   # admin menu (main menu) and in-game admin panel (F10)
	"bot_personalities": {},
	"bot_slots": [],
	"tuning": {},
	"burble": {},
	"response": {},
	"underglow": {},
	"rims": {},
	"paint_finish": "gloss",
	"bindings": {},     # action -> {"key": physical keycode, "pad": [kind 0 button / 1 axis, index, axis sign]}
}

## leaderboard[track_id][category] = Array of entries (sorted best first)
## categories: "drift" (points per session), "combo" (best single drift), "lap" (best lap seconds), "race" (race time)
var leaderboard := {}

## Set by the menu before loading the world.
var pending_config := {}
## False while automated tests run, so they never overwrite the player's settings file.
var persist := true

# --- loading a world in slices ------------------------------------------------------------------
# World generation calls load_tick() in its long loops. While async_loading is on, a tick hands a
# frame back to the engine every ~30 ms, so the loading screen keeps animating and the window stays
# responsive; otherwise (tests) it returns at once and the world builds in one go.
var async_loading := false
## A shooting minigame is on: the fire button (X on the gamepad) does not look back
var fire_mode := false
var load_progress := 0.0        # 0..1 over the whole world
var load_stage := ""
var _load_range := Vector2(0.0, 1.0)
var _load_last := 0


func load_begin(stage: String, from: float, to: float) -> void:
	load_stage = stage
	_load_range = Vector2(from, to)
	load_progress = maxf(load_progress, from)


## `frac` = progress within the current stage (0..1), negative = unchanged.
func load_tick(frac := -1.0) -> void:
	Net.keepalive()
	if frac >= 0.0:
		load_progress = maxf(load_progress, lerpf(_load_range.x, _load_range.y, clampf(frac, 0.0, 1.0)))
	if async_loading and Time.get_ticks_msec() - _load_last > 30:
		await get_tree().process_frame
		_load_last = Time.get_ticks_msec()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_setup_translations()
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
	_add_action("toggle_transmission", [KEY_T], [], [])
	_add_action("map_zoom", [KEY_M], [], [])
	_add_action("camera_next", [KEY_C], [JOY_BUTTON_Y], [])
	# (Y) held = free camera, see camera_rig.gd – the right stick click switches the ABS
	_add_action("camera_free", [KEY_V], [], [])
	_add_action("toggle_abs", [KEY_K], [JOY_BUTTON_RIGHT_STICK], [])
	_add_action("toggle_esp", [KEY_J], [JOY_BUTTON_LEFT_STICK], [])
	_add_action("look_back", [KEY_B], [JOY_BUTTON_X], [])
	_add_action("reset_car", [KEY_R], [JOY_BUTTON_BACK], [])
	_add_action("lights", [KEY_L], [JOY_BUTTON_DPAD_UP], [])
	_add_action("neon_flash", [KEY_N], [JOY_BUTTON_DPAD_RIGHT], [])
	_add_action("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_add_action("scoreboard", [KEY_TAB], [JOY_BUTTON_DPAD_DOWN], [])
	# (X) fires in the shooting minigames (there it does not look back, see camera_rig.gd)
	_add_action("radio", [KEY_P], [], [])
	_add_action("fire", [KEY_F], [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_X], [])
	if InputMap.action_get_events("fire").filter(func(e): return e is InputEventMouseButton).is_empty():
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)
	_add_action("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_add_action("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_add_action("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_add_action("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	# menus on the gamepad: (A) confirms, (B) goes back
	_add_action("ui_accept", [], [JOY_BUTTON_A], [])
	_add_action("ui_cancel", [], [JOY_BUTTON_B], [])


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


## Actions the player can rebind in Optionen → Steuerung: [action, label].
const REBINDABLE := [
	["accelerate", "Gas"], ["brake", "Bremse / Rückwärts"], ["steer_left", "Lenken links"],
	["steer_right", "Lenken rechts"], ["handbrake", "Handbremse"], ["nitro", "Nitro"],
	["shift_up", "Hochschalten"], ["shift_down", "Runterschalten"], ["toggle_transmission", "Automatik ⇄ Manuell"],
	["fire", "Feuer (Party)"], ["camera_next", "Kamera wechseln"], ["camera_free", "Freie Kamera"],
	["look_back", "Nach hinten schauen"], ["reset_car", "Auto zurücksetzen"], ["lights", "Licht"],
	["neon_flash", "Neon blitzen"], ["toggle_abs", "ABS an/aus"], ["toggle_esp", "ESP an/aus"],
	["scoreboard", "Leaderboard"], ["map_zoom", "Karte vergrößern (halten)"], ["radio", "Autoradio"], ["pause", "Pause"],
]


## Puts the player's own keys / gamepad inputs over the defaults: a rebound device replaces all of
## that action's events of the same kind (keyboard or gamepad); the mouse button for "fire" stays.
func apply_bindings() -> void:
	var b: Dictionary = settings.get("bindings", {})
	for action in b:
		if not InputMap.has_action(action):
			continue
		var e: Dictionary = b[action] if b[action] is Dictionary else {}
		if e.has("key"):
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey:
					InputMap.action_erase_event(action, ev)
			var k := InputEventKey.new()
			k.physical_keycode = int(e["key"])
			InputMap.action_add_event(action, k)
		if e.has("pad") and e["pad"] is Array and (e["pad"] as Array).size() == 3:
			for ev in InputMap.action_get_events(action):
				if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
					InputMap.action_erase_event(action, ev)
			InputMap.action_add_event(action, pad_event(e["pad"]))


static func pad_event(p: Array) -> InputEvent:
	if int(p[0]) == 0:
		var jb := InputEventJoypadButton.new()
		jb.button_index = int(p[1]) as JoyButton
		return jb
	var jm := InputEventJoypadMotion.new()
	jm.axis = int(p[1]) as JoyAxis
	jm.axis_value = 1.0 if float(p[2]) > 0.0 else -1.0
	return jm


## Stores one new binding (`key` >= 0 for the keyboard, else `pad`) and applies it right away.
func rebind(action: String, key: int, pad: Array = []) -> void:
	var b: Dictionary = settings["bindings"]
	var e: Dictionary = b.get(action, {}) if b.get(action) is Dictionary else {}
	if key >= 0:
		e["key"] = key
	if not pad.is_empty():
		e["pad"] = pad
	b[action] = e
	apply_bindings()
	save_settings()


## Back to the default layout.
func reset_bindings() -> void:
	settings["bindings"] = {}
	for pair in REBINDABLE:
		InputMap.action_erase_events(pair[0])
	_setup_input()
	save_settings()


const PAD_BUTTONS := {JOY_BUTTON_A: "(A)", JOY_BUTTON_B: "(B)", JOY_BUTTON_X: "(X)", JOY_BUTTON_Y: "(Y)",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "Steuerkreuz ↑", JOY_BUTTON_DPAD_DOWN: "Steuerkreuz ↓",
	JOY_BUTTON_DPAD_LEFT: "Steuerkreuz ←", JOY_BUTTON_DPAD_RIGHT: "Steuerkreuz →", JOY_BUTTON_GUIDE: "Home"}


## Readable name of the action's current keyboard (pad = false) or gamepad binding.
func binding_text(action: String, pad: bool) -> String:
	var names: Array = []
	for ev in InputMap.action_get_events(action):
		if not pad and ev is InputEventKey:
			var kc: Key = (ev as InputEventKey).physical_keycode
			if DisplayServer.get_name() != "headless":
				kc = DisplayServer.keyboard_get_keycode_from_physical(kc)   # the label on the player's layout
			names.append(OS.get_keycode_string(kc))
		elif pad and ev is InputEventJoypadButton:
			var bi: int = (ev as InputEventJoypadButton).button_index
			names.append(PAD_BUTTONS.get(bi, t("Taste %d") % bi))
		elif pad and ev is InputEventJoypadMotion:
			names.append(axis_name((ev as InputEventJoypadMotion).axis, (ev as InputEventJoypadMotion).axis_value))
	return " / ".join(names) if not names.is_empty() else "–"


static func axis_name(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
		JOY_AXIS_LEFT_X: return "Linker Stick ←" if value < 0.0 else "Linker Stick →"
		JOY_AXIS_LEFT_Y: return "Linker Stick ↑" if value < 0.0 else "Linker Stick ↓"
		JOY_AXIS_RIGHT_X: return "Rechter Stick ←" if value < 0.0 else "Rechter Stick →"
		JOY_AXIS_RIGHT_Y: return "Rechter Stick ↑" if value < 0.0 else "Rechter Stick ↓"
	return t("Achse %d") % axis


const CONTROLS_HELP := [
	["W / ↑ / RT", "Gas"],
	["S / ↓ / LT", "Bremse / Rückwärts"],
	["W + S im Stand", "Launch Control / Burnout (S loslassen = Start)"],
	["A D / ← → / Stick", "Lenken"],
	["Leertaste / (A)", "Handbremse – blockiert die Hinterräder, auch mit Gas"],
	["Shift / (B)", "Nitro"],
	["E / RB", "Hochschalten (in Automatik als Schaltwippe)"],
	["Q / Strg / LB", "Runterschalten (in Automatik als Schaltwippe)"],
	["M", "Automatik ⇄ Manuell"],
	["F / Linksklick / (X)", "Feuer (Party: Arena-Shootout, Ballon-Schlacht)"],
	["C / (Y)", "Kamera wechseln"],
	["V / (Y) halten", "Kamera-Lock lösen (freie Kamera, Maus / rechter Stick)"],
	["Rechte Maustaste halten", "Kurz umsehen"],
	["B / (X)", "Nach hinten schauen"],
	["R / Back", "Auto auf Strecke zurücksetzen"],
	["L", "Licht an/aus"],
	["N / Steuerkreuz →", "Neon blitzen (halten, bei eingebautem Underglow)"],
	["Tab", "Leaderboard / Spielerliste"],
	["K / rechter Stick drücken", "ABS an/aus"],
	["J / linker Stick drücken", "ESP an/aus"],
	["Esc / Start", "Pause"],
	["Enter / (A)", "Menü: bestätigen"],
	["Esc / (B)", "Menü: zurück"],
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
		# rev 1: the old default MSAA 4x + FXAA flickered on thin objects in motion -> MSAA 4x + TAA
		if int(data.get("aa_rev", 0)) < 1:
			if int(data.get("aa", 6)) == 6:
				settings["aa"] = 7
			settings["aa_rev"] = 1
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
	if not (settings.get("owned_cars") is Array):
		settings["owned_cars"] = []
	if not (settings.get("redeemed_codes") is Array):
		settings["redeemed_codes"] = []
	if not (settings.get("admin_codes") is Dictionary):
		settings["admin_codes"] = {}
	# from before cars cost money: the car in use stays owned
	if CARS.has(str(settings["car"])) and not bool(CARS[str(settings["car"])].get("egg", false)) and not settings["owned_cars"].has(settings["car"]):
		settings["owned_cars"].append(settings["car"])
	for key in ["window_mode", "aa", "upscaler", "vsync", "max_fps", "shadow_quality", "grass_quality", "day_cycle", "view_distance"]:
		settings[key] = int(settings[key])
	settings["resolution"] = str(settings["resolution"])
	if not (settings["tuning"] is Dictionary):
		settings["tuning"] = {}
	if not (settings["burble"] is Dictionary):
		settings["burble"] = {}
	if not (settings.get("response") is Dictionary):
		settings["response"] = {}
	settings["traffic"] = (2 if settings["traffic"] else 0) if settings["traffic"] is bool else clampi(int(settings["traffic"]), 0, 4)
	settings["traffic_speed"] = clampi(int(settings.get("traffic_speed", 1)), 0, 4)
	if not (settings.get("menu_lights") is Dictionary):
		settings["menu_lights"] = {"ceiling": 1.0, "platform": 1.0, "platform_color": "#ff0505"}
	if not (settings.get("bindings") is Dictionary):
		settings["bindings"] = {}
	apply_bindings()


func save_settings() -> void:
	if persist:
		_write_json(SETTINGS_PATH, settings)
	settings_changed.emit()


func set_setting(key: String, value) -> void:
	settings[key] = value
	save_settings()
	apply_settings()


func apply_settings() -> void:
	if TranslationServer.get_locale() != str(settings.get("language", "de")):
		TranslationServer.set_locale(str(settings.get("language", "de")))
		language_changed.emit()
	var vol := clampf(float(settings["master_volume"]), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(0, vol <= 0.001)
	apply_audio_devices()
	apply_video()


## Speakers / headphones and microphone chosen in Optionen → Audio ("Default" = system default).
func apply_audio_devices() -> void:
	var out := str(settings.get("audio_output", "Default"))
	if AudioServer.get_output_device_list().has(out) and AudioServer.output_device != out:
		AudioServer.output_device = out
	var inp := str(settings.get("audio_input", "Default"))
	if AudioServer.get_input_device_list().has(inp) and AudioServer.input_device != inp:
		AudioServer.input_device = inp


# --- microphone test (level meter in the audio options; the signal is never played back) ---
var _mic_player: AudioStreamPlayer
var _mic_capture: AudioEffectCapture
var _mic_bus := -1
var _mic_level := 0.0


func start_mic_test() -> void:
	if _mic_player:
		return
	_mic_bus = AudioServer.get_bus_index("MicTest")
	if _mic_bus < 0:
		AudioServer.add_bus()
		_mic_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_mic_bus, "MicTest")
		_mic_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_mic_bus, _mic_capture, 0)
		# silenced after the capture: the microphone is never played back (no feedback)
		var mute := AudioEffectAmplify.new()
		mute.volume_db = -80.0
		AudioServer.add_bus_effect(_mic_bus, mute, 1)
		AudioServer.set_bus_volume_db(_mic_bus, -80.0)
	else:
		_mic_capture = AudioServer.get_bus_effect(_mic_bus, 0) as AudioEffectCapture
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "MicTest"
	add_child(_mic_player)
	_mic_player.play()


func stop_mic_test() -> void:
	if _mic_player:
		_mic_player.stop()
		_mic_player.queue_free()
	_mic_player = null
	_mic_level = 0.0


## Microphone level 0..1 while the test runs.
func mic_level() -> float:
	if _mic_capture == null or _mic_player == null:
		return 0.0
	var n := _mic_capture.get_frames_available()
	if n > 0:
		var buf := _mic_capture.get_buffer(n)
		var peak := 0.0
		for f in buf:
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		var gain := float(settings.get("mic_volume", 1.0))
		_mic_level = maxf(clampf(peak * gain, 0.0, 1.0), _mic_level * 0.85)
	else:
		_mic_level *= 0.9
	return _mic_level


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


func get_paint(paint_id: String, custom_html: String = "", finish: String = "gloss") -> Dictionary:
	var out: Dictionary = PAINTS[0]
	if paint_id == "custom" and custom_html != "":
		var c := Color.from_string(custom_html, Color(0.6, 0.03, 0.03))
		out = {"id": "custom", "name": "Eigene Farbe", "color": c, "metallic": 0.1, "roughness": 0.2}
	else:
		for p in PAINTS:
			if p["id"] == paint_id:
				out = p
	out = out.duplicate()
	out["finish"] = finish
	return out


## Rims per car: {style: car_body.gd RIM_STYLES index (0 = the car's own), color: RIM_COLORS index}
## The car's stickers (livery.gd layers).
## Sticker designs: several per car, one of them on the car ("livery_designs": {car: {"active",
## "list": [{"name", "layers"}]}}). An older single livery becomes "Design 1".
func livery_designs(car_id: String) -> Dictionary:
	if not (settings.get("livery_designs") is Dictionary):
		settings["livery_designs"] = {}
	var all: Dictionary = settings["livery_designs"]
	if not all.has(car_id):
		var old: Array = (settings.get("liveries", {}) as Dictionary).get(car_id, [])
		all[car_id] = {"active": 0, "list": [{"name": "Design 1", "layers": old.duplicate(true)}]}
	var d: Dictionary = all[car_id]
	if (d.get("list", []) as Array).is_empty():
		d["list"] = [{"name": "Design 1", "layers": []}]
	d["active"] = clampi(int(d.get("active", 0)), 0, (d["list"] as Array).size() - 1)
	return d


func get_livery(car_id: String) -> Array:
	var d := livery_designs(car_id)
	return ((d["list"] as Array)[int(d["active"])]["layers"] as Array).duplicate(true)


func set_livery(car_id: String, layers: Array) -> void:
	var d := livery_designs(car_id)
	(d["list"] as Array)[int(d["active"])]["layers"] = layers.duplicate(true)
	save_settings()


func select_design(car_id: String, i: int) -> void:
	var d := livery_designs(car_id)
	d["active"] = clampi(i, 0, (d["list"] as Array).size() - 1)
	save_settings()


## A new design (empty, or a copy of the given layers) – it becomes the active one; its index.
func add_design(car_id: String, design_name: String, layers: Array = []) -> int:
	var d := livery_designs(car_id)
	(d["list"] as Array).append({"name": design_name, "layers": layers.duplicate(true)})
	d["active"] = (d["list"] as Array).size() - 1
	save_settings()
	return int(d["active"])


func rename_design(car_id: String, i: int, design_name: String) -> void:
	var d := livery_designs(car_id)
	if i >= 0 and i < (d["list"] as Array).size() and design_name.strip_edges() != "":
		(d["list"] as Array)[i]["name"] = design_name.strip_edges()
		save_settings()


func delete_design(car_id: String, i: int) -> void:
	var d := livery_designs(car_id)
	var l: Array = d["list"]
	if i >= 0 and i < l.size():
		l.remove_at(i)
	if l.is_empty():
		l.append({"name": "Design 1", "layers": []})
	d["active"] = clampi(int(d["active"]) - (1 if int(d["active"]) >= i and int(d["active"]) > 0 else 0), 0, l.size() - 1)
	save_settings()


func get_rims(car_id: String) -> Dictionary:
	var all: Dictionary = settings.get("rims", {})
	var r: Dictionary = all.get(car_id, {})
	return {"style": int(r.get("style", 0)), "color": int(r.get("color", 0))}


func set_rims(car_id: String, cfg: Dictionary) -> void:
	var all: Dictionary = settings.get("rims", {})
	all[car_id] = cfg
	settings["rims"] = all
	save_settings()
	settings_changed.emit()


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
func tuned_gearing(car_id: String, tuning: Dictionary = {}) -> Dictionary:
	var car := get_car(car_id)
	var t := get_tuning(car_id)
	for k in tuning:
		t[k] = int(tuning[k])
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
	if not owns_car(car_id):
		return "Erst das Auto kaufen."
	var cost := tuning_cost(car_id, category)
	if cost < 0:
		return "Maximale Stufe erreicht."
	if int(settings["credits"]) < cost:
		return t("Nicht genug Credits (%s benötigt).") % format_points(cost)
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


## Throttle response per car (tuning menu, free): 1.0 = the stock profile, down to 0.2 = the pedal
## and the revs build up more gently.
const RESPONSE_MIN := 0.2


func get_response(car_id: String) -> float:
	var all: Dictionary = settings.get("response", {})
	return clampf(float(all.get(car_id, 1.0)), RESPONSE_MIN, 1.0)


func set_response(car_id: String, value: float) -> void:
	var all: Dictionary = settings.get("response", {})
	all[car_id] = clampf(value, RESPONSE_MIN, 1.0)
	settings["response"] = all
	save_settings()
	settings_changed.emit()


func get_underglow(car_id: String) -> Dictionary:
	var all: Dictionary = settings.get("underglow", {})
	var c: Dictionary = (all.get(car_id, {}) as Dictionary).duplicate(true)
	var out := {"on": bool(c.get("on", false)), "mode": clampi(int(c.get("mode", 0)), 0, UNDERGLOW_MODES.size() - 1),
		"speed": clampf(float(c.get("speed", 1.0)), 0.25, 3.0), "sides": {}}
	var sides: Dictionary = c.get("sides", {})
	for s in UNDERGLOW_SIDES:
		var sd: Dictionary = sides.get(s[0], {})
		out["sides"][s[0]] = {"on": bool(sd.get("on", true)), "color": str(sd.get("color", "#8a3dff")), "flash": bool(sd.get("flash", false)),
			"bright": clampf(float(sd.get("bright", 1.0)), 0.1, 2.0)}
	return out


func set_underglow(car_id: String, cfg: Dictionary) -> void:
	var all: Dictionary = settings.get("underglow", {})
	all[car_id] = cfg.duplicate(true)
	settings["underglow"] = all
	save_settings()
	settings_changed.emit()


# ---------------------------------------------------------------------------
# Buying cars, action codes
# ---------------------------------------------------------------------------
const FREE_CARS := 3
## Price of the n-th car after the free ones (rising slowly).
const CAR_PRICES := [15000, 25000, 40000, 60000, 85000, 120000, 160000, 210000]
## Built-in codes (the easter eggs). Admin codes come on top (settings "admin_codes", or the server's).
const BUILTIN_CODES := {
	"M6": {"car": "m6gt3"},
	"BOUNCY": {"car": "yaris"},       # the bouncy Toyota
}


func car_price(car_id: String) -> int:
	var n := 0
	for id in CAR_ORDER:
		if bool(CARS[id].get("egg", false)):
			continue
		if id == car_id:
			return 0 if n < FREE_CARS else int(CAR_PRICES[mini(n - FREE_CARS, CAR_PRICES.size() - 1)])
		n += 1
	return -1        # not for sale (easter egg)


func owns_car(car_id: String) -> bool:
	return car_price(car_id) == 0 or (settings["owned_cars"] as Array).has(car_id)


## Cars shown in the garage: everything for sale plus the unlocked easter eggs.
func garage_cars() -> Array:
	var out: Array = []
	for id in CAR_ORDER:
		if not bool(CARS[id].get("egg", false)) or owns_car(id):
			out.append(id)
	return out


## Buys a car: "" when done, else why not.
func buy_car(car_id: String) -> String:
	if owns_car(car_id):
		return ""
	var price := car_price(car_id)
	if price < 0:
		return "Nicht käuflich"
	if int(settings["credits"]) < price:
		return t("Nicht genug Credits (%s fehlen)") % format_points(price - int(settings["credits"]))
	settings["credits"] = int(settings["credits"]) - price
	settings["owned_cars"].append(car_id)
	save_settings()
	return ""


## The car to drive: the chosen one if owned, else the first owned one.
func driven_car() -> String:
	var c := str(settings["car"])
	if CARS.has(c) and owns_car(c):
		return c
	for id in CAR_ORDER:
		if owns_car(id):
			return id
	return "r34"


## Redeems an action code: [ok, message].
func redeem_code(raw: String) -> Array:
	var code := raw.strip_edges().to_upper().replace(" ", "")
	if code == "":
		return [false, "Bitte einen Code eingeben"]
	var e = BUILTIN_CODES.get(code, (settings["admin_codes"] as Dictionary).get(code))
	if (settings["redeemed_codes"] as Array).has(code):
		return [false, "Code wurde schon eingelöst"]
	if not (e is Dictionary):
		if Net.is_online and not Net.is_host():
			# maybe one of the server's codes: it checks it and sends the reward (Net.code_result)
			Net.request_code(code)
			return [true, "Code wird beim Server geprüft …"]
		return [false, "Unbekannter Code"]
	return apply_code_reward(code, e)


## Gives what a code gives (credits, a car) and remembers the code: [ok, message].
func apply_code_reward(code: String, e: Dictionary) -> Array:
	var got: Array = []
	var cr := int(e.get("credits", 0))
	if cr > 0:
		settings["credits"] = int(settings["credits"]) + cr
		got.append("%s Credits" % format_points(cr))
	var car := str(e.get("car", ""))
	if CARS.has(car) and not (settings["owned_cars"] as Array).has(car):
		settings["owned_cars"].append(car)
		got.append(str(CARS[car]["name"]))
	if code != "":
		settings["redeemed_codes"].append(code)
	save_settings()
	return [true, t("Eingelöst: ") + (", ".join(got) if not got.is_empty() else "nichts Neues")]


func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	settings["credits"] = int(settings["credits"]) + amount
	save_settings()


## The UI's German text in the chosen language (Labels and Buttons do this on their own; this is
## for texts that are formatted or drawn).
static func t(text: String) -> String:
	return String(TranslationServer.translate(text))


func _setup_translations() -> void:
	var tr_en := Translation.new()
	tr_en.locale = "en"
	for k in EnTexts.EN:
		tr_en.add_message(k, EnTexts.EN[k])
	TranslationServer.add_translation(tr_en)
	TranslationServer.set_locale("de")


func track_name(track_id: String) -> String:
	for tk in TRACKS:
		if tk["id"] == track_id:
			return t(tk["name"])
	return track_id


func mode_name(mode_id: String) -> String:
	if mode_id == "tutorial":
		return t("Tutorial")
	if mode_id == "editor":
		return t("Welt-Editor")
	for m in MODES:
		if m["id"] == mode_id:
			return t(m["name"])
	return mode_id


func weather_name(weather_id: String) -> String:
	for w in WEATHER_MODES:
		if w["id"] == weather_id:
			return t(w["name"])
	return weather_id


func day_cycle_name(minutes: int) -> String:
	return "Aus (feste Uhrzeit)" if minutes <= 0 else "%d Minuten pro Tag" % minutes


func time_name(tod_id: String) -> String:
	for tt in TIMES_OF_DAY:
		if tt["id"] == tod_id:
			return t(tt["name"])
	return tod_id


func local_player_info() -> Dictionary:
	var car := driven_car()
	return {
		"name": str(settings["player_name"]).substr(0, 20),
		"car": car,
		"paint": settings["paint"],
		"custom_color": settings["custom_color"],
		"paint_finish": str(settings.get("paint_finish", "gloss")),
		"rims": get_rims(car),
		"transmission": settings["transmission"],
		"burble": get_burble(car),
		"underglow": get_underglow(car),
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
