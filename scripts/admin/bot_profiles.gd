extends RefCounted
## Bot personalities for the admin mode: every driving parameter of the race AI, as named profiles
## (built-in ones plus the admin's own, kept in the settings), and "default lines": a bot's best lap
## (speed and position across the road along the whole track), saved per track – when one is set,
## all bots drive that lap's line and speeds.

## [key, label, min, max, step, help]
const PARAMS := [
	["corner", "Kurventempo", 0.6, 1.3, 0.01, "Anteil des echten Kurvengrips, den sie nutzen"],
	["brake", "Bremspunkt", 0.6, 1.6, 0.01, "Bremsweg-Faktor (> 1 = früher bremsen)"],
	["throttle", "Gas", 0.5, 1.0, 0.01, "Wie voll sie beschleunigen"],
	["vmax", "Höchsttempo (m/s)", 30.0, 160.0, 1.0, "Schneller fahren sie nie"],
	["line", "Ideallinie", 0.0, 1.0, 0.01, "Wie sehr sie die Ideallinie nutzen"],
	["line_w", "Linienbreite", 0.3, 1.0, 0.01, "Wie weit nach innen sie ziehen"],
	["lane", "Spurwechsel", 0.0, 1.0, 0.01, "Wie sehr sie auf der Fahrbahn umherwandern"],
	["err", "Fehler", 0.0, 0.2, 0.002, "Zufällige Fehler: zu spät bremsen, unruhig lenken"],
	["edge", "Randabstand (m)", 0.0, 3.0, 0.05, "Abstand, den sie zum Fahrbahnrand halten"],
	["pred", "Vorausschau Rand (s)", 0.1, 1.2, 0.05, "Wie früh sie merken, dass sie zu weit nach außen kommen"],
	["slide0", "Drift-Toleranz", 0.05, 0.8, 0.01, "Ab diesem Rutschwinkel gehen sie vom Gas"],
	["slidemin", "Gas im Drift", 0.0, 1.0, 0.01, "Wie viel Gas sie beim Rutschen stehen lassen"],
	["exit", "Vorsicht am Ausgang", 0.0, 1.0, 0.01, "Weniger Gas bei viel Lenkeinschlag"],
	["grip", "Grip-Hilfe", 0.8, 1.4, 0.01, "Mehr Reifengrip (Rennspiel-Hilfe)"],
	["power", "Leistungs-Hilfe", 0.8, 1.5, 0.01, "Mehr Motorleistung"],
	["nitro", "Nitro", 0.0, 1.0, 1.0, "Nitro auf Geraden (0/1)"],
	["pace", "Tempo Standardrunde", 0.8, 1.15, 0.01, "Wie schnell sie eine festgelegte Bestrunde nachfahren"],
]
const DEFAULTS := {"line_w": 0.75, "lane": 1.0, "edge": 1.0, "pred": 0.5, "slide0": 0.22, "slidemin": 0.35, "exit": 0.0, "pace": 1.0}

## Built-in personalities: changes over the difficulty level (empty = just the level)
const BUILTIN := {
	"Ausgeglichen": {},
	"Aggressiv": {"corner": 1.08, "brake": 0.85, "edge": 0.5, "err": 0.03, "lane": 0.4, "exit": 0.0},
	"Vorsichtig": {"corner": 0.9, "brake": 1.25, "edge": 1.8, "err": 0.01, "throttle": 0.92, "exit": 0.4},
	"Drifter": {"slide0": 0.5, "slidemin": 0.85, "exit": 0.0, "corner": 1.0, "line": 0.6},
	"Chaot": {"err": 0.12, "lane": 1.0, "line": 0.3, "edge": 0.3},
}
const LINE_DIR := "user://bot_lines"


static func all_names() -> Array:
	var out: Array = BUILTIN.keys()
	for n in custom():
		if not out.has(n):
			out.append(n)
	return out


static func custom() -> Dictionary:
	var c = Game.settings.get("bot_personalities", {})
	return c if c is Dictionary else {}


static func get_profile(name: String) -> Dictionary:
	var c := custom()
	if c.has(name):
		return c[name]
	return BUILTIN.get(name, {})


static func save_profile(name: String, p: Dictionary) -> void:
	var c := custom().duplicate(true)
	c[name] = p
	Game.settings["bot_personalities"] = c
	Game.save_settings()


static func delete_profile(name: String) -> void:
	var c := custom().duplicate(true)
	c.erase(name)
	Game.settings["bot_personalities"] = c
	Game.save_settings()


## The full parameter set of a bot: level values, the defaults, then the personality on top.
static func resolve(level: Dictionary, personality: String) -> Dictionary:
	var out := DEFAULTS.duplicate()
	for k in level:
		out[k] = level[k]
	out["nitro"] = 1.0 if bool(level.get("nitro", false)) else 0.0
	var p := get_profile(personality)
	for k in p:
		out[k] = p[k]
	return out


## Personality per bot slot (admin), or "" for a random one.
static func slot_personality(slot: int) -> String:
	var s = Game.settings.get("bot_slots", [])
	if s is Array and slot < (s as Array).size():
		return str(s[slot])
	return ""


# ---------------------------------------------------------------------------
# Default lines (a bot's best lap)
# ---------------------------------------------------------------------------
static func line_path(track_id: String) -> String:
	return LINE_DIR.path_join(track_id + ".json")


static func save_line(track_id: String, line: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(LINE_DIR)
	var f := FileAccess.open(line_path(track_id), FileAccess.WRITE)
	if f == null:
		return false
	var out := {"time": line["time"], "name": line.get("name", ""), "car": line.get("car", ""),
		"speed": Marshalls.raw_to_base64((line["speed"] as PackedFloat32Array).to_byte_array()),
		"lat": Marshalls.raw_to_base64((line["lat"] as PackedFloat32Array).to_byte_array())}
	f.store_string(JSON.stringify(out))
	return true


static func load_line(track_id: String) -> Dictionary:
	if not FileAccess.file_exists(line_path(track_id)):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(line_path(track_id)))
	if not (d is Dictionary):
		return {}
	return {"time": float(d.get("time", 0.0)), "name": str(d.get("name", "")), "car": str(d.get("car", "")),
		"speed": Marshalls.base64_to_raw(str(d.get("speed", ""))).to_float32_array(),
		"lat": Marshalls.base64_to_raw(str(d.get("lat", ""))).to_float32_array()}


static func clear_line(track_id: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(line_path(track_id)))
