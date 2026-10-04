extends RefCounted
## Option pages shared by the main menu and the pause menu (graphics, audio, gameplay).

const UiKit = preload("res://scripts/ui/ui_kit.gd")


## Tabbed options: Grafik / Audio / Spiel. `on_quality` is called after the quality preset changed.
static func tabs(on_quality: Callable = Callable(), in_race := false) -> TabContainer:
	var tc := TabContainer.new()
	tc.custom_minimum_size = Vector2(660, 560 if not in_race else 520)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# gamepad: the tab row takes the focus too (up from the first option), ◀ ▶ then switch tabs
	tc.get_tab_bar().focus_mode = Control.FOCUS_ALL
	# RB / LB (E / Q) switch the category
	var pager := Node.new()
	pager.set_script(load("res://scripts/ui/tab_pager.gd"))
	tc.add_child(pager)
	tc.tooltip_text = "Kategorie wechseln: RB / LB  (E / Q)"
	var video := _scroll(video_page(on_quality, in_race))
	video.name = "Grafik"
	tc.add_child(video)
	var audio := _scroll(audio_page())
	audio.name = "Audio"
	tc.add_child(audio)
	var game := _scroll(gameplay_page())
	game.name = "Spiel"
	tc.add_child(game)
	var ctl := _scroll(controls_page())
	ctl.name = "Steuerung"
	tc.add_child(ctl)
	return tc


static func _scroll(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# gamepad / keyboard: the list scrolls along with the selected entry
	sc.follow_focus = true
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


static func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	return v


static func video_page(on_quality: Callable = Callable(), in_race := false) -> VBoxContainer:
	var v := _page()
	v.add_child(UiKit.labeled("Anzeigemodus", UiKit.option(Game.WINDOW_MODES, int(Game.settings["window_mode"]), func(i):
		Game.set_setting("window_mode", i))))
	var res_list: Array = Game.available_resolutions()
	var labels: Array = []
	var current: Vector2i = Game.selected_resolution()
	var sel := res_list.size() - 1
	for i in res_list.size():
		var r: Vector2i = res_list[i]
		labels.append("%d × %d" % [r.x, r.y])
		if r == current:
			sel = i
	var res_opt := UiKit.option(labels, sel, func(i):
		Game.set_setting("resolution", Game.resolution_key(res_list[i])))
	res_opt.tooltip_text = "Im Vollbild ist das die 3D-Renderauflösung (Menüs bleiben scharf)."
	v.add_child(UiKit.labeled("Auflösung", res_opt))
	var aa := UiKit.option(Game.AA_MODES, int(Game.settings["aa"]), func(i): Game.set_setting("aa", i))
	aa.tooltip_text = "Empfohlen: MSAA 4x + TAA – glättet auch in Bewegung (dünne Masten, Zäune, Blätter). FXAA flimmert in Bewegung stärker."
	v.add_child(UiKit.labeled("Kantenglättung", aa))
	var up := UiKit.option(Game.UPSCALERS, int(Game.settings["upscaler"]), func(i): Game.set_setting("upscaler", i))
	up.tooltip_text = "Hochskalierung, wenn im Vollbild eine kleinere Auflösung gewählt ist. FSR 2.2 ersetzt TAA."
	v.add_child(UiKit.labeled("Upscaling", up))
	v.add_child(UiKit.labeled("Schärfe (FSR)", UiKit.slider(0, 1, 0.05, float(Game.settings["sharpness"]), func(x):
		Game.set_setting("sharpness", x))))
	v.add_child(UiKit.labeled("VSync", UiKit.option(Game.VSYNC_MODES, int(Game.settings["vsync"]), func(i):
		Game.set_setting("vsync", i))))
	var fps_labels: Array = []
	var fps_sel := 0
	for i in Game.FPS_LIMITS.size():
		var f: int = Game.FPS_LIMITS[i]
		fps_labels.append("Unbegrenzt" if f == 0 else "%d FPS" % f)
		if f == int(Game.settings["max_fps"]):
			fps_sel = i
	v.add_child(UiKit.labeled("FPS-Limit", UiKit.option(fps_labels, fps_sel, func(i):
		Game.set_setting("max_fps", Game.FPS_LIMITS[i]))))
	var gamma_val := UiKit.label("%.2f" % float(Game.settings["gamma"]), 16, UiKit.TEXT_DIM)
	var gamma := UiKit.slider(0.5, 1.8, 0.02, float(Game.settings["gamma"]), func(x):
		gamma_val.text = "%.2f" % x
		Game.set_setting("gamma", x), 200)
	v.add_child(UiKit.labeled("Gamma", UiKit.row([gamma, gamma_val], 8)))
	var mb := UiKit.option(Game.MOTION_BLUR_NAMES, clampi(int(Game.settings.get("motion_blur", 0)), 0, Game.MOTION_BLUR_NAMES.size() - 1), func(i):
		Game.set_setting("motion_blur", i))
	mb.tooltip_text = "Wie das Auge bei Tempo: die Mitte bleibt scharf, zum Rand hin verschwimmt das Bild –\nje schneller, desto stärker. Schnelle Kameraschwenks verwischen seitlich."
	v.add_child(UiKit.labeled("Motion Blur", mb))
	var art := UiKit.option(Game.ART_STYLE_NAMES, clampi(int(Game.settings.get("art_style", 0)), 0, Game.ART_STYLE_NAMES.size() - 1), func(i):
		Game.set_setting("art_style", i))
	art.tooltip_text = "Bildstil-Filter über dem ganzen Spiel:\nRetro 90er – niedrige Auflösung, wenige Farben mit Dithering, Scanlines, VHS-Farbsaum.\nComic – flache Farbflächen, Tuschelinien, Rasterpunkte in den Schatten."
	v.add_child(UiKit.labeled("Art-Style", art))
	v.add_child(UiKit.sep())
	var q := UiKit.option(Game.QUALITY_NAMES, int(Game.settings["quality"]), func(i):
		Game.set_setting("quality", i)
		if on_quality.is_valid():
			on_quality.call())
	q.tooltip_text = "Effekte (SSAO, Spiegelungen, Glow), Baum- und Buschdichte, Sichtweite."
	v.add_child(UiKit.labeled("Grafikqualität", q))
	v.add_child(UiKit.labeled("Schatten", UiKit.option(Game.QUALITY_NAMES, int(Game.settings["shadow_quality"]), func(i):
		Game.set_setting("shadow_quality", i))))
	var grass := UiKit.option(Game.GRASS_NAMES, int(Game.settings["grass_quality"]), func(i):
		Game.set_setting("grass_quality", i))
	grass.tooltip_text = "Gras wird nur in der Nähe der Kamera gezeichnet – höhere Stufen: dichter und weiter."
	v.add_child(UiKit.labeled("Gras", grass))
	var vd_val := UiKit.label("%d m" % int(Game.settings["view_distance"]), 16, UiKit.TEXT_DIM)
	var vd := UiKit.slider(100, 3000, 50, float(Game.settings["view_distance"]), func(x):
		vd_val.text = "%d m" % int(x)
		Game.settings["view_distance"] = int(x)
		Game.save_settings(), 200)
	vd.tooltip_text = "Bis zu dieser Entfernung werden Bäume, Büsche, Felsen und Deko in 3D gezeichnet – und Gebäude, Ampeln, Laternen, Zuschauer und alle anderen Objekte entsprechend weiter oder näher (1200 m = Standard). Dahinter stehen die Bäume als 2D-Bilder bis zum Horizont. Weniger = mehr FPS. Wirkt sofort."
	v.add_child(UiKit.labeled("Sichtweite (Bäume, Gebäude, Objekte)", UiKit.row([vd, vd_val], 8)))
	var fps := CheckBox.new()
	fps.text = "FPS-Anzeige im Rennen"
	fps.button_pressed = bool(Game.settings.get("show_fps", false))
	fps.toggled.connect(func(on):
		Game.settings["show_fps"] = on
		Game.save_settings())
	v.add_child(fps)
	var perf := CheckBox.new()
	perf.text = "GPU- und CPU-Last im Rennen"
	perf.tooltip_text = "Zeigt unten rechts neben den FPS, wie viele Millisekunden Grafikkarte und Prozessor pro Bild brauchen und wie ausgelastet sie damit sind."
	perf.button_pressed = bool(Game.settings.get("show_perf", false))
	perf.toggled.connect(func(on):
		Game.settings["show_perf"] = on
		Game.save_settings())
	v.add_child(perf)
	var lf := CheckBox.new()
	lf.text = "Lens Flares (Sonne und Mond)"
	lf.button_pressed = bool(Game.settings["lens_flares"])
	lf.toggled.connect(func(on): Game.set_setting("lens_flares", on))
	v.add_child(lf)
	if in_race:
		v.add_child(UiKit.label("Grafikqualität und Baumdichte gelten ab dem nächsten Laden der Strecke.", 14, UiKit.TEXT_DIM))
	return v


## The car radio: its volume, the stations on the presets (FM1 / FM2, 1-6) – picked from all stations
## there are – and own stations by their stream address.
static func _radio_section(v: VBoxContainer) -> void:
	v.add_child(UiKit.label("Autoradio", 20, UiKit.GOLD))
	var rv := UiKit.slider(0, 1, 0.02, Radio.volume, func(x): Radio.set_volume(x))
	rv.tooltip_text = "Lautstärke des Autoradios (auch am Lautstärkeknopf des Radios)."
	v.add_child(UiKit.labeled("Radio-Lautstärke", rv))
	var pickers: Array = []          # [band, preset, OptionButton]
	var fill := func():
		var cat: Array = Radio.catalog()
		for p in pickers:
			var o: OptionButton = p[2]
			o.clear()
			var cur := str(Radio._stations[p[0]][p[1]].get("url", ""))
			for k in cat.size():
				var c: Dictionary = cat[k]
				o.add_item(("★ " if bool(c.get("own", false)) else "") + str(c.get("name", c.get("ps", ""))))
				o.set_item_metadata(k, str(c.get("url", "")))
				if str(c.get("url", "")) == cur:
					o.select(k)
	for b in 2:
		v.add_child(UiKit.label("FM%d – Stationstasten" % (b + 1), 16, UiKit.TEXT))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 6)
		for i in 6:
			var o := OptionButton.new()
			o.custom_minimum_size = Vector2(330, 40)
			o.fit_to_longest_item = false
			var bb := b
			var ii := i
			o.item_selected.connect(func(k): Radio.set_slot(bb, ii, str(o.get_item_metadata(k))))
			pickers.append([b, i, o])
			grid.add_child(UiKit.row([UiKit.label(str(i + 1), 18, UiKit.TEXT_DIM), o], 8))
		v.add_child(grid)
	# own stations
	v.add_child(UiKit.label("Eigener Sender (Stream-Adresse, MP3)", 16, UiKit.TEXT))
	var name_in := LineEdit.new()
	name_in.placeholder_text = "Name"
	name_in.custom_minimum_size = Vector2(180, 40)
	var url_in := LineEdit.new()
	url_in.placeholder_text = "https://…  (z. B. https://ice2.somafm.com/metal-128-mp3)"
	url_in.custom_minimum_size = Vector2(420, 40)
	url_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var note := UiKit.label("", 14, UiKit.TEXT_DIM)
	var own_box := VBoxContainer.new()
	own_box.add_theme_constant_override("separation", 4)
	var list_own := func(self_ref: Callable):
		for c in own_box.get_children():
			c.queue_free()
		for c in Game.settings.get("radio_custom", []):
			var url := str(c.get("url", ""))
			var del := UiKit.button("✕", func():
				Radio.remove_custom(url)
				fill.call()
				self_ref.call(self_ref), 46)
			del.alignment = HORIZONTAL_ALIGNMENT_CENTER
			del.tooltip_text = "Sender entfernen"
			var l := UiKit.label("★ %s  –  %s" % [str(c.get("name", "")), url], 15, UiKit.TEXT)
			l.clip_text = true
			l.custom_minimum_size = Vector2(560, 0)
			own_box.add_child(UiKit.row([del, l], 8))
	var add := UiKit.button("+ Hinzufügen", func():
		var err := Radio.add_custom(name_in.text, url_in.text)
		note.text = err if err != "" else "Hinzugefügt – jetzt oben einer Stationstaste zuweisen."
		note.add_theme_color_override("font_color", UiKit.BAD if err != "" else UiKit.GOOD)
		if err == "":
			name_in.text = ""
			url_in.text = ""
			fill.call()
			list_own.call(list_own), 170)
	v.add_child(UiKit.row([name_in, url_in, add], 8))
	v.add_child(note)
	v.add_child(own_box)
	v.add_child(UiKit.button("Standard-Sender wiederherstellen", func():
		Radio.reset_slots()
		fill.call(), 340))
	fill.call()
	list_own.call(list_own)


static func audio_page() -> VBoxContainer:
	var v := _page()
	v.add_child(UiKit.labeled("Gesamtlautstärke", UiKit.slider(0, 1, 0.05, float(Game.settings["master_volume"]), func(x):
		Game.set_setting("master_volume", x))))
	v.add_child(UiKit.labeled("Motorsound", UiKit.slider(0, 1.5, 0.05, float(Game.settings["engine_volume"]), func(x):
		Game.settings["engine_volume"] = x
		Game.save_settings())))
	var wv := UiKit.slider(0, 1.5, 0.05, float(Game.settings["weather_volume"]), func(x):
		Game.settings["weather_volume"] = x
		Game.save_settings())
	wv.tooltip_text = "Lautstärke von Regen und Wetter (ganz links = aus)."
	v.add_child(UiKit.labeled("Wetter / Regen", wv))
	var mv := UiKit.slider(0, 1.5, 0.05, float(Game.settings.get("menu_sfx_volume", 0.35)), func(x):
		Game.set_setting("menu_sfx_volume", x))
	mv.tooltip_text = "Regen und Donner im Hauptmenü (ganz links = aus)."
	v.add_child(UiKit.labeled("Hauptmenü-Geräusche", mv))
	v.add_child(UiKit.sep())
	_radio_section(v)
	v.add_child(UiKit.sep())
	# --- devices ---
	var outs := _device_list(AudioServer.get_output_device_list())
	var out_opt := UiKit.option(outs.map(_device_name), maxi(outs.find(str(Game.settings.get("audio_output", "Default"))), 0), func(i):
		Game.set_setting("audio_output", outs[i]))
	out_opt.tooltip_text = "Lautsprecher / Kopfhörer, auf denen das Spiel ausgegeben wird."
	v.add_child(UiKit.labeled("Ausgabegerät", out_opt))
	var ins := _device_list(AudioServer.get_input_device_list())
	var in_opt := UiKit.option(ins.map(_device_name), maxi(ins.find(str(Game.settings.get("audio_input", "Default"))), 0), func(i):
		Game.set_setting("audio_input", ins[i]))
	in_opt.tooltip_text = "Mikrofon (für Sprach-Funktionen)."
	v.add_child(UiKit.labeled("Mikrofon", in_opt))
	v.add_child(UiKit.labeled("Mikrofon-Pegel", UiKit.slider(0, 2, 0.05, float(Game.settings.get("mic_volume", 1.0)), func(x):
		Game.set_setting("mic_volume", x))))
	# microphone test: live level meter, nothing is played back
	var meter := ProgressBar.new()
	meter.min_value = 0.0
	meter.max_value = 1.0
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(260, 18)
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.1)
	bg.border_color = UiKit.ACCENT.darkened(0.3)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiKit.GOOD
	fill.set_corner_radius_all(4)
	meter.add_theme_stylebox_override("background", bg)
	meter.add_theme_stylebox_override("fill", fill)
	var poll := Timer.new()
	poll.wait_time = 0.05
	poll.timeout.connect(func(): meter.value = Game.mic_level())
	var test := CheckButton.new()
	test.text = "Mikrofon testen"
	test.toggled.connect(func(on):
		if on:
			Game.start_mic_test()
			poll.start()
		else:
			poll.stop()
			Game.stop_mic_test()
			meter.value = 0.0)
	# stop the test when the options close
	meter.tree_exiting.connect(func(): Game.stop_mic_test())
	v.add_child(UiKit.row([test, meter, poll]))
	return v


## "Default" first, then the devices the system reports.
static func _device_list(devices: PackedStringArray) -> Array:
	var out: Array = ["Default"]
	for d in devices:
		if d != "Default":
			out.append(d)
	return out


static func _device_name(d: String) -> String:
	return "Systemstandard" if d == "Default" else d


static func gameplay_page() -> VBoxContainer:
	var v := _page()
	# language (German is the source; the menus rebuild themselves when it changes)
	var langs: Array = Game.LANGUAGES.map(func(l): return l[1])
	var cur := 0
	for i in Game.LANGUAGES.size():
		if Game.LANGUAGES[i][0] == str(Game.settings.get("language", "de")):
			cur = i
	var lang := UiKit.option(langs, cur, func(i): Game.set_setting("language", Game.LANGUAGES[i][0]))
	lang.set_auto_translate_mode(Node.AUTO_TRANSLATE_MODE_DISABLED)      # (each in its own language)
	v.add_child(UiKit.labeled("Sprache / Language", lang))
	v.add_child(UiKit.sep())
	var adm := CheckBox.new()
	adm.text = "Admin-Modus (Hauptmenü: Admin · im Spiel: F10)"
	adm.button_pressed = bool(Game.settings.get("admin_mode", false))
	adm.tooltip_text = "Freie Kamera mit Tempo, Bots fein einstellen und Persönlichkeiten geben, Bot-Bestrunden als Standard, Aktionscodes anlegen."
	adm.toggled.connect(func(on): Game.set_setting("admin_mode", on))
	v.add_child(adm)
	v.add_child(UiKit.labeled("Sichtfeld (FOV)", UiKit.slider(60, 100, 1, float(Game.settings["fov"]), func(x):
		Game.set_setting("fov", x))))
	var cs_val := UiKit.label("%d %%" % int(float(Game.settings["camera_smoothing"]) * 100.0), 16, UiKit.TEXT_DIM)
	var cs := UiKit.slider(0.0, 1.0, 0.05, float(Game.settings["camera_smoothing"]), func(x):
		cs_val.text = "%d %%" % int(x * 100.0)
		Game.settings["camera_smoothing"] = x
		Game.save_settings(), 200)
	cs.tooltip_text = "Wie stark die Verfolgerkamera Bodenwellen, Federbewegungen und Ruckler beim Gasgeben und Bremsen ausfiltert."
	v.add_child(UiKit.labeled("Kamera-Glättung", UiKit.row([cs, cs_val], 8)))
	var cz_val := UiKit.label("%.1fx" % float(Game.settings["camera_zoom"]), 16, UiKit.TEXT_DIM)
	var cz := UiKit.slider(0.3, 2.4, 0.05, float(Game.settings["camera_zoom"]), func(x):
		cz_val.text = "%.1fx" % x
		Game.settings["camera_zoom"] = x
		Game.save_settings(), 200)
	cz.tooltip_text = "Abstand der Verfolgerkamera – auch während der Fahrt mit dem Mausrad."
	v.add_child(UiKit.labeled("Kamera-Abstand", UiKit.row([cz, cz_val], 8)))
	var ct_val := UiKit.label("%+d°" % int(rad_to_deg(float(Game.settings["camera_tilt"]))), 16, UiKit.TEXT_DIM)
	var ct := UiKit.slider(-0.2, 0.75, 0.01, float(Game.settings["camera_tilt"]), func(x):
		ct_val.text = "%+d°" % int(rad_to_deg(x))
		Game.settings["camera_tilt"] = x
		Game.save_settings(), 200)
	ct.tooltip_text = "Neigung der Verfolgerkamera – auch während der Fahrt: linke Maustaste halten und ziehen."
	v.add_child(UiKit.labeled("Kamera-Neigung", UiKit.row([ct, ct_val], 8)))
	v.add_child(UiKit.labeled("Maus-Empfindlichkeit", UiKit.slider(0.05, 1.0, 0.05, float(Game.settings["mouse_sensitivity"]), func(x):
		Game.set_setting("mouse_sensitivity", x))))
	v.add_child(UiKit.labeled("Konter-Lenkhilfe", UiKit.slider(0, 1, 0.05, float(Game.settings["steer_assist"]), func(x):
		Game.set_setting("steer_assist", x))))
	var abs_opt := UiKit.option(["An", "Aus"], 0 if bool(Game.settings.get("abs", true)) else 1, func(i):
		Game.set_setting("abs", i == 0))
	abs_opt.tooltip_text = "Antiblockiersystem: beim Vollbremsen blockieren die Räder nicht, das Auto bleibt lenkbar.\nIm Drehzahlmesser: ABS-Symbol grün = an, blinkt gelb beim Regeln.\nWährend der Fahrt umschalten: [K] / rechten Stick drücken."
	v.add_child(UiKit.labeled("ABS  [K]", abs_opt))
	var esp_opt := UiKit.option(["An", "Aus"], 0 if bool(Game.settings.get("esp", false)) else 1, func(i):
		Game.set_setting("esp", i == 0))
	esp_opt.tooltip_text = "Stabilitätsprogramm: nimmt Gas weg und fängt das Auto ab, sobald das Heck ausbricht –\nsicher beim Rennen, verhindert aber Drifts (Handbremse umgeht es). Symbol grün = an, blinkt gelb beim Regeln.\nWährend der Fahrt umschalten: [J] / linken Stick drücken."
	v.add_child(UiKit.labeled("ESP  [J]", esp_opt))
	var hb_val := UiKit.label("%d %%" % int(float(Game.settings["handbrake_strength"]) * 100.0), 16, UiKit.TEXT_DIM)
	var hb := UiKit.slider(0.1, 1.0, 0.05, float(Game.settings["handbrake_strength"]), func(x):
		hb_val.text = "%d %%" % int(x * 100.0)
		Game.settings["handbrake_strength"] = x
		Game.save_settings(), 200)
	hb.tooltip_text = "Die Handbremse (Leertaste) blockiert die Hinterräder immer – auch mit Gas (die Kupplung ist dabei getreten).\nDie Stärke bestimmt, wie viel Seitenhalt die blockierten Reifen behalten: schwach = mehr Halt, stark = das Heck kommt sofort."
	v.add_child(UiKit.labeled("Handbremse", UiKit.row([hb, hb_val], 8)))
	var sl_val := UiKit.label("%d %%" % int(float(Game.settings["slide"]) * 100.0), 16, UiKit.TEXT_DIM)
	var sl := UiKit.slider(0.0, 1.0, 0.05, float(Game.settings["slide"]), func(x):
		sl_val.text = "%d %%" % int(x * 100.0)
		Game.settings["slide"] = x
		Game.save_settings(), 200)
	sl.tooltip_text = "Wie weit die Autos seitlich rutschen: mehr = weichere, flüssigere Übergänge (Transitions)."
	v.add_child(UiKit.labeled("Seitliches Rutschen", UiKit.row([sl, sl_val], 8)))
	v.add_child(UiKit.labeled("Einheit", UiKit.option(["km/h", "mph"], 0 if Game.settings["units_kmh"] else 1, func(i):
		Game.set_setting("units_kmh", i == 0))))
	var nav := CheckButton.new()
	nav.button_pressed = bool(Game.settings.get("nav_arrow", true))
	nav.tooltip_text = "Ein animierter 3D-Pfeil oben im Bild zeigt Kurven voraus, falsche Richtung und den Weg zurück zur Strecke."
	nav.toggled.connect(func(on): Game.set_setting("nav_arrow", on))
	v.add_child(UiKit.labeled("Richtungspfeile", nav))
	return v


## Tastatur- und Gamepad-Belegung: click a field, then press the new key / button / stick.
static func controls_page() -> VBoxContainer:
	var v := _page()
	v.add_child(UiKit.label("Feld anwählen und neue Taste drücken (Esc / Start bricht ab).", 16, UiKit.TEXT_DIM))
	var head := HBoxContainer.new()
	head.add_child(_cell(UiKit.label("Aktion", 16, UiKit.TEXT_DIM), 200))
	head.add_child(_cell(UiKit.label("Tastatur", 16, UiKit.TEXT_DIM), 190))
	head.add_child(_cell(UiKit.label("Gamepad", 16, UiKit.TEXT_DIM), 190))
	v.add_child(head)
	var fields: Array = []
	for pair in Game.REBINDABLE:
		var action: String = pair[0]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(_cell(UiKit.label(pair[1], 17), 200))
		for pad in [false, true]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(190, 34)
			b.clip_text = true
			b.text = Game.binding_text(action, pad)
			b.pressed.connect(func(): _capture(b, action, pad))
			h.add_child(b)
			fields.append([b, action, pad])
		v.add_child(h)
	v.add_child(UiKit.button("Standardbelegung", func():
		Game.reset_bindings()
		for f in fields:
			(f[0] as Button).text = Game.binding_text(f[1], f[2]), 260))
	return v


static func _cell(c: Control, w: float) -> Control:
	c.custom_minimum_size.x = w
	return c


static func _capture(b: Button, action: String, pad: bool) -> void:
	var cap := Node.new()
	cap.set_script(load("res://scripts/ui/bind_capture.gd"))
	cap.pad = pad
	b.text = "Gamepad drücken …" if pad else "Taste drücken …"
	cap.captured.connect(func(key: int, p: Array):
		Game.rebind(action, key, p)
		if is_instance_valid(b):
			b.text = Game.binding_text(action, pad)
			b.grab_focus())
	cap.cancelled.connect(func():
		if is_instance_valid(b):
			b.text = Game.binding_text(action, pad))
	b.add_child(cap)
