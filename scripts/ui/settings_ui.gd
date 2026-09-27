extends RefCounted
## Option pages shared by the main menu and the pause menu (graphics, audio, gameplay).

const UiKit = preload("res://scripts/ui/ui_kit.gd")


## Tabbed options: Grafik / Audio / Spiel. `on_quality` is called after the quality preset changed.
static func tabs(on_quality: Callable = Callable(), in_race := false) -> TabContainer:
	var tc := TabContainer.new()
	tc.custom_minimum_size = Vector2(660, 560 if not in_race else 520)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var video := _scroll(video_page(on_quality, in_race))
	video.name = "Grafik"
	tc.add_child(video)
	var audio := _scroll(audio_page())
	audio.name = "Audio"
	tc.add_child(audio)
	var game := _scroll(gameplay_page())
	game.name = "Spiel"
	tc.add_child(game)
	return tc


static func _scroll(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	aa.tooltip_text = "MSAA glättet Kanten von Geometrie, FXAA/TAA zusätzlich Blätter, Gras und Shader-Kanten."
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
	vd.tooltip_text = "Bis zu dieser Entfernung werden Bäume, Büsche, Sträucher, Felsen und Deko in 3D gezeichnet. Dahinter stehen die Bäume als 2D-Bilder bis zum Horizont – es fehlt nie ein Baum. Weniger = mehr FPS. Wirkt sofort."
	v.add_child(UiKit.labeled("Sichtweite 3D-Bäume & Pflanzen", UiKit.row([vd, vd_val], 8)))
	var lf := CheckBox.new()
	lf.text = "Lens Flares (Sonne und Mond)"
	lf.button_pressed = bool(Game.settings["lens_flares"])
	lf.toggled.connect(func(on): Game.set_setting("lens_flares", on))
	v.add_child(lf)
	if in_race:
		v.add_child(UiKit.label("Grafikqualität und Baumdichte gelten ab dem nächsten Laden der Strecke.", 14, UiKit.TEXT_DIM))
	return v


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
	return v


static func gameplay_page() -> VBoxContainer:
	var v := _page()
	v.add_child(UiKit.labeled("Sichtfeld (FOV)", UiKit.slider(60, 100, 1, float(Game.settings["fov"]), func(x):
		Game.set_setting("fov", x))))
	var cs_val := UiKit.label("%d %%" % int(float(Game.settings["camera_smoothing"]) * 100.0), 16, UiKit.TEXT_DIM)
	var cs := UiKit.slider(0.0, 1.0, 0.05, float(Game.settings["camera_smoothing"]), func(x):
		cs_val.text = "%d %%" % int(x * 100.0)
		Game.settings["camera_smoothing"] = x
		Game.save_settings(), 200)
	cs.tooltip_text = "Wie stark die Verfolgerkamera Bodenwellen, Federbewegungen und Ruckler beim Gasgeben und Bremsen ausfiltert."
	v.add_child(UiKit.labeled("Kamera-Glättung", UiKit.row([cs, cs_val], 8)))
	v.add_child(UiKit.labeled("Maus-Empfindlichkeit", UiKit.slider(0.05, 1.0, 0.05, float(Game.settings["mouse_sensitivity"]), func(x):
		Game.set_setting("mouse_sensitivity", x))))
	v.add_child(UiKit.labeled("Konter-Lenkhilfe", UiKit.slider(0, 1, 0.05, float(Game.settings["steer_assist"]), func(x):
		Game.set_setting("steer_assist", x))))
	var hb_val := UiKit.label("%d %%" % int(float(Game.settings["handbrake_strength"]) * 100.0), 16, UiKit.TEXT_DIM)
	var hb := UiKit.slider(0.1, 1.0, 0.05, float(Game.settings["handbrake_strength"]), func(x):
		hb_val.text = "%d %%" % int(x * 100.0)
		Game.settings["handbrake_strength"] = x
		Game.save_settings(), 200)
	hb.tooltip_text = "Wie stark die Handbremse (Leertaste) greift: schwach = sanftes Einleiten, stark = Räder blockieren."
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
	return v
