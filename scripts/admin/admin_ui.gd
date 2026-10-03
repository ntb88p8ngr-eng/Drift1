extends RefCounted
## Admin mode screens (shared by the main menu screen and the in-game panel): bot personalities with
## every driving parameter, personalities per bot slot, the saved default laps, and action codes that
## give credits or cars.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const BotProfiles = preload("res://scripts/admin/bot_profiles.gd")
const RaceAI = preload("res://scripts/world/race_ai.gd")


## Sliders for every parameter of `p` (changed in place); on_change(p) after every change.
static func param_editor(p: Dictionary, on_change: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	for d in BotProfiles.PARAMS:
		var key: String = d[0]
		var val := float(p.get(key, BotProfiles.DEFAULTS.get(key, (RaceAI.LEVELS[1] as Dictionary).get(key, 1.0))))
		if key == "nitro":
			val = 1.0 if (bool(p.get(key, true)) if p.get(key) is bool else float(p.get(key, 1.0)) > 0.5) else 0.0
		var l := UiKit.label("%s: %s" % [d[1], str(snappedf(val, float(d[4])))], 15)
		l.tooltip_text = str(d[5])
		box.add_child(l)
		var sl := UiKit.slider(float(d[2]), float(d[3]), float(d[4]), val, func(v):
			p[key] = v
			l.text = "%s: %s" % [d[1], str(snappedf(v, float(d[4])))]
			on_change.call(p), 340)
		sl.tooltip_text = str(d[5])
		box.add_child(sl)
	return box


## The main menu's admin screen, built into `add` (a Callable taking a Control).
static func build_screen(add: Callable, refresh: Callable, status: Callable) -> void:
	# --- personalities ---
	add.call(UiKit.label("BOT-PERSÖNLICHKEITEN", 20, UiKit.GOLD))
	var names := BotProfiles.all_names()
	var sel := [str(names[0])]
	var editing := [BotProfiles.get_profile(sel[0]).duplicate()]
	var holder := VBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = sel[0]
	name_edit.custom_minimum_size = Vector2(220, 40)
	var rebuild := func(): pass
	rebuild = func():
		for c in holder.get_children():
			c.queue_free()
		var full := BotProfiles.resolve(RaceAI.LEVELS[1], "")
		for k in editing[0]:
			full[k] = editing[0][k]
		holder.add_child(param_editor(full, func(p):
			editing[0] = p))
	add.call(UiKit.row([UiKit.option(names, 0, func(i):
		sel[0] = str(names[i])
		name_edit.text = sel[0]
		editing[0] = BotProfiles.get_profile(sel[0]).duplicate()
		rebuild.call(), 220), name_edit,
		UiKit.button("Speichern", func():
			var nm := name_edit.text.strip_edges()
			if nm == "":
				return
			BotProfiles.save_profile(nm, editing[0])
			status.call("Persönlichkeit „%s“ gespeichert" % nm)
			refresh.call(), 140),
		UiKit.button("Löschen", func():
			if BotProfiles.BUILTIN.has(name_edit.text):
				status.call("Eingebaute Persönlichkeiten bleiben (überschreiben geht)")
				return
			BotProfiles.delete_profile(name_edit.text)
			refresh.call(), 120)]))
	add.call(UiKit.label("Werte gelten für die Stufe „Mittel“ – die Stufe im Einzelspieler setzt die Grundwerte, die Persönlichkeit ändert sie.", 13, UiKit.TEXT_DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(380, 300)
	sc.add_child(holder)
	add.call(sc)
	rebuild.call()
	# --- slots ---
	add.call(UiKit.spacer(6))
	add.call(UiKit.label("BOT-PLÄTZE", 20, UiKit.GOLD))
	var slots: Array = Game.settings.get("bot_slots", [])
	if not (slots is Array):
		slots = []
	slots = slots.duplicate()
	slots.resize(7)
	var opts: Array = ["Zufällig"] + names
	var grid := GridContainer.new()
	grid.columns = 4
	for k in 7:
		var cur := str(slots[k]) if slots[k] != null else ""
		var idx := maxi(opts.find(cur), 0)
		grid.add_child(UiKit.label("Bot %d" % (k + 1), 15))
		grid.add_child(UiKit.option(opts, idx, func(i):
			slots[k] = "" if i == 0 else str(opts[i])
			Game.settings["bot_slots"] = slots
			Game.save_settings(), 170))
	add.call(grid)
	# --- default laps ---
	add.call(UiKit.spacer(6))
	add.call(UiKit.label("STANDARD-RUNDEN (Bots fahren diese Bestrunde nach)", 20, UiKit.GOLD))
	var any := false
	for t in Game.TRACKS:
		var line := BotProfiles.load_line(str(t["id"]))
		if line.is_empty():
			continue
		any = true
		var tid := str(t["id"])
		add.call(UiKit.row([UiKit.label("%s: %s – %s (%s)" % [t["name"], Game.format_time(float(line["time"])), line["name"], Game.get_car(str(line["car"]))["name"]], 15),
			UiKit.button("Entfernen", func():
				BotProfiles.clear_line(tid)
				refresh.call(), 130)]))
	if not any:
		add.call(UiKit.label("Keine – im Rennen mit F10 eine Bot-Bestrunde als Standard festlegen.", 14, UiKit.TEXT_DIM))
	# --- action codes ---
	add.call(UiKit.spacer(6))
	add.call(UiKit.label("AKTIONSCODES", 20, UiKit.GOLD))
	var code_e := LineEdit.new()
	code_e.placeholder_text = "CODE"
	code_e.custom_minimum_size = Vector2(160, 40)
	var cr_e := SpinBox.new()
	cr_e.max_value = 10000000
	cr_e.step = 500
	cr_e.custom_minimum_size = Vector2(140, 40)
	var car_ids: Array = [""] + Game.CAR_ORDER
	var car_names: Array = ["kein Auto"]
	for id in Game.CAR_ORDER:
		car_names.append(Game.CARS[id]["name"])
	var car_sel := [0]
	add.call(UiKit.row([code_e, UiKit.label("Credits", 15), cr_e, UiKit.option(car_names, 0, func(i): car_sel[0] = i, 220),
		UiKit.button("Anlegen", func():
			var code := code_e.text.strip_edges().to_upper().replace(" ", "")
			if code == "":
				return
			var codes: Dictionary = (Game.settings["admin_codes"] as Dictionary).duplicate()
			codes[code] = {"credits": int(cr_e.value), "car": str(car_ids[car_sel[0]])}
			Game.settings["admin_codes"] = codes
			Game.save_settings()
			status.call("Code %s angelegt" % code)
			refresh.call(), 130)]))
	for code in Game.settings["admin_codes"]:
		var e: Dictionary = Game.settings["admin_codes"][code]
		var what: Array = []
		if int(e.get("credits", 0)) > 0:
			what.append("%s Cr" % Game.format_points(int(e["credits"])))
		if str(e.get("car", "")) != "":
			what.append(str(Game.get_car(str(e["car"]))["name"]))
		var c2 := str(code)
		add.call(UiKit.row([UiKit.label("%s  →  %s" % [c2, ", ".join(what)], 15), UiKit.button("Löschen", func():
			var codes: Dictionary = (Game.settings["admin_codes"] as Dictionary).duplicate()
			codes.erase(c2)
			Game.settings["admin_codes"] = codes
			Game.save_settings()
			refresh.call(), 110)]))
	add.call(UiKit.label("Online-Server geben ihre eigenen Codes aus (Server-Einstellungen).", 13, UiKit.TEXT_DIM))
