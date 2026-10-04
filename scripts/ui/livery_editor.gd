extends Control
## The paint booth's editor (main menu → Lack & Sticker), on the left of the screen while the car
## stands in the booth: the paint (colour, finish) and the stickers – shapes, digits, letters and the
## graffiti pieces in any colour, as layers (later ones on top) placed on a side of the car.
## Click on the car: the selected sticker goes there (drag to move it). Right mouse button: turn the
## camera, wheel: zoom.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Livery = preload("res://scripts/car/livery.gd")
const DecalShapes = preload("res://scripts/car/decal_shapes.gd")

const SWATCHES := ["#000000", "#ffffff", "#e8202a", "#ff7a00", "#ffd400", "#2bd94a", "#00b7ff", "#1f3fff",
	"#8a2be2", "#ff3fa4", "#7a7a7a", "#c9a227"]

var main            # main.gd (refresh_showroom)
var sr              # showroom.gd
var layers: Array = []
var sel := -1
var shape := "star"
var color := Color.BLACK

var _panel: PanelContainer
var _pages: Array = []
var _shape_grid: GridContainer
var _shape_note: Label
var _list: ItemList
var _props: VBoxContainer
var _ctl := {}             # property controls by key
var _syncing := false
var _dragging := false
var _orbit := false
var _custom: ColorPickerButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layers = Game.get_livery(str(Game.settings["car"]))
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.11, 0.86)
	sb.border_color = Color(0.62, 0.32, 1.0, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(36, 30)
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.size = Vector2(560, get_viewport_rect().size.y - 120)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	v.add_child(UiKit.title("LACK & STICKER", 34))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var paint := _scroll(_paint_page())
	var stick := _scroll(_sticker_page())
	for p in [paint, stick]:
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		body.add_child(p)
		_pages.append(p)
	tabs.add_child(UiKit.button("Lack", func(): _show_page(0), 160))
	tabs.add_child(UiKit.button("Sticker", func(): _show_page(1), 160))
	v.add_child(UiKit.label("Klick aufs Auto: Sticker setzen / ziehen · rechte Maustaste: Kamera drehen · Mausrad: Zoom", 13, UiKit.TEXT_DIM))
	_show_page(1)
	# the shapes are drawn once (into user://decals)
	var gen := DecalShapes.new()
	add_child(gen)
	gen.done.connect(_fill_shapes)
	gen.ensure_all()
	_refresh_list()
	_apply()


func _scroll(c: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(c)
	return sc


func _show_page(i: int) -> void:
	for k in _pages.size():
		(_pages[k] as Control).visible = k == i


# --- paint -----------------------------------------------------------------------------------------
func _paint_page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiKit.label("Lackierung", 20, UiKit.GOLD))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for p in Game.PAINTS:
		var b := _swatch_button(p["color"], func():
			Game.set_setting("paint", p["id"])
			main.refresh_showroom(false), 110, 40)
		b.tooltip_text = str(p["name"])
		grid.add_child(b)
	v.add_child(grid)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(160, 40)
	cp.edit_alpha = false
	cp.color = Color.from_string(str(Game.settings.get("custom_color", "")), Color(0.3, 0.05, 0.5))
	cp.color_changed.connect(func(c):
		Game.settings["custom_color"] = c.to_html(false)
		Game.set_setting("paint", "custom")
		main.refresh_showroom(false))
	v.add_child(UiKit.labeled("Eigene Farbe", cp, 180))
	var fin_names: Array = []
	var fin_idx := 0
	for i in TexKit.PAINT_FINISHES.size():
		fin_names.append(TexKit.PAINT_FINISHES[i][1])
		if TexKit.PAINT_FINISHES[i][0] == str(Game.settings.get("paint_finish", "gloss")):
			fin_idx = i
	v.add_child(UiKit.labeled("Lack-Effekt", UiKit.option(fin_names, fin_idx, func(i):
		Game.set_setting("paint_finish", TexKit.PAINT_FINISHES[i][0])
		main.refresh_showroom(false), 240), 180))
	return v


# --- stickers ---------------------------------------------------------------------------------------
func _sticker_page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UiKit.label("Formen", 20, UiKit.GOLD))
	_shape_note = UiKit.label("Formen werden vorbereitet …", 14, UiKit.TEXT_DIM)
	v.add_child(_shape_note)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 190)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_shape_grid = GridContainer.new()
	_shape_grid.columns = 9
	_shape_grid.add_theme_constant_override("h_separation", 4)
	_shape_grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(_shape_grid)
	v.add_child(sc)
	v.add_child(UiKit.label("Farbe", 20, UiKit.GOLD))
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 4)
	for h in SWATCHES:
		var c := Color.from_string(h, Color.WHITE)
		sw.add_child(_swatch_button(c, func(): _set_color(c), 34, 30))
	_custom = ColorPickerButton.new()
	_custom.custom_minimum_size = Vector2(44, 30)
	_custom.color = color
	_custom.color_changed.connect(func(c): _set_color(c))
	sw.add_child(_custom)
	v.add_child(sw)
	v.add_child(UiKit.label("Ebenen (oben = zuletzt aufgeklebt)", 20, UiKit.GOLD))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.add_child(UiKit.button("+ Sticker", _add_layer, 120))
	btns.add_child(UiKit.button("Kopie", _dup_layer, 80))
	btns.add_child(UiKit.button("▲", func(): _move(1), 44))
	btns.add_child(UiKit.button("▼", func(): _move(-1), 44))
	btns.add_child(UiKit.button("Löschen", _del_layer, 100))
	v.add_child(btns)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 120)
	_list.fixed_icon_size = Vector2i(26, 26)
	_list.item_selected.connect(func(i):
		sel = layers.size() - 1 - i
		_sync_props())
	v.add_child(_list)
	_props = VBoxContainer.new()
	_props.add_theme_constant_override("separation", 4)
	v.add_child(_props)
	var sides: Array = []
	for s in Livery.SIDES:
		sides.append(Livery.SIDE_NAMES[s])
	_ctl["side"] = UiKit.option(sides, 0, func(i): _set_prop("side", Livery.SIDES[i]), 240)
	_props.add_child(UiKit.labeled("Seite", _ctl["side"], 170))
	for k in [["p", "Position (vorne – hinten)", -1.0, 1.0, 0.01], ["h", "Höhe / quer", -1.0, 1.0, 0.01],
			["size", "Größe (m)", 0.08, 3.0, 0.01], ["rot", "Drehung (°)", -180.0, 180.0, 1.0], ["alpha", "Deckkraft", 0.1, 1.0, 0.01]]:
		var key: String = k[0]
		_ctl[key] = UiKit.slider(k[2], k[3], k[4], 0.0, func(x): _set_prop(key, x), 240)
		_props.add_child(UiKit.labeled(k[1], _ctl[key], 170))
	var mir := CheckBox.new()
	mir.text = "Gespiegelt auf der anderen Seite"
	mir.toggled.connect(func(on): _set_prop("mirror", on))
	_ctl["mirror"] = mir
	_props.add_child(mir)
	return v


func _swatch_button(c: Color, cb: Callable, w: float, h: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.set_corner_radius_all(5)
	st.border_color = Color(1, 1, 1, 0.35)
	st.set_border_width_all(1)
	var hv := st.duplicate() as StyleBoxFlat
	hv.border_color = UiKit.ACCENT
	hv.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("focus", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.pressed.connect(cb)
	return b


func _fill_shapes() -> void:
	_shape_note.text = "Form wählen – sie gilt für den gewählten Sticker (oder „+ Sticker“)."
	for c in _shape_grid.get_children():
		c.queue_free()
	for s in Livery.shapes():
		var id: String = s[0]
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.tooltip_text = str(s[1])
		b.icon = Livery.texture(id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func():
			shape = id
			if sel >= 0:
				_set_prop("shape", id)
			else:
				_add_layer())
		_shape_grid.add_child(b)
	_apply()


func _set_color(c: Color) -> void:
	color = c
	_custom.color = c
	if sel >= 0:
		_set_prop("color", "#" + c.to_html(false))


func _add_layer() -> void:
	var l := Livery.new_layer(shape, color)
	if sel >= 0:
		l["side"] = layers[sel]["side"]
	layers.append(l)
	sel = layers.size() - 1
	_changed(true)


func _dup_layer() -> void:
	if sel < 0:
		return
	var l: Dictionary = (layers[sel] as Dictionary).duplicate()
	l["p"] = clampf(float(l["p"]) + 0.15, -1.0, 1.0)
	layers.append(l)
	sel = layers.size() - 1
	_changed(true)


func _del_layer() -> void:
	if sel < 0:
		return
	layers.remove_at(sel)
	sel = mini(sel, layers.size() - 1)
	_changed(true)


func _move(d: int) -> void:
	if sel < 0:
		return
	var j := clampi(sel + d, 0, layers.size() - 1)
	if j == sel:
		return
	var t = layers[sel]
	layers[sel] = layers[j]
	layers[j] = t
	sel = j
	_changed(true)


func _set_prop(key: String, value) -> void:
	if _syncing or sel < 0:
		return
	layers[sel][key] = value
	_changed(key == "shape" or key == "side")


func _changed(relist: bool) -> void:
	if relist:
		_refresh_list()
	_apply()


func _refresh_list() -> void:
	_list.clear()
	var names := {}
	for s in Livery.shapes():
		names[s[0]] = s[1]
	for i in range(layers.size() - 1, -1, -1):
		var l: Dictionary = layers[i]
		_list.add_item("%d.  %s  ·  %s" % [i + 1, Game.t(str(names.get(l["shape"], l["shape"]))), Game.t(str(Livery.SIDE_NAMES.get(l["side"], "")))],
			Livery.texture(str(l["shape"])))
	if sel >= 0:
		_list.select(layers.size() - 1 - sel)
	_sync_props()


func _sync_props() -> void:
	_props.visible = sel >= 0
	if sel < 0:
		return
	_syncing = true
	var l: Dictionary = layers[sel]
	(_ctl["side"] as OptionButton).selected = maxi(Livery.SIDES.find(str(l["side"])), 0)
	for k in ["p", "h", "size", "rot", "alpha"]:
		(_ctl[k] as HSlider).value = float(l.get(k, 0.0))
	(_ctl["mirror"] as CheckBox).button_pressed = bool(l.get("mirror", false))
	_syncing = false


func _apply() -> void:
	if sr and sr.car and is_instance_valid(sr.car):
		Livery.apply(sr.car.body, layers)


func save() -> void:
	Game.set_livery(str(Game.settings["car"]), layers)


## The car under the mouse: place / drag the selected sticker; right mouse turns the camera.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or sr == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbit = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			sr.booth_zoom(0.92)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			sr.booth_zoom(1.08)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed and _place(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbit:
			sr.booth_orbit(mm.relative.x, mm.relative.y)
		elif _dragging:
			_place(mm.position)


func _place(pos: Vector2) -> bool:
	if sel < 0:
		return false
	var ray = sr.booth_ray(pos)
	if ray == null:
		return false
	var box := Livery.body_box(sr.car.body)
	var hit = Livery.pick(str(layers[sel]["side"]), box, ray[0], ray[1])
	if hit == null:
		return false
	if absf(float(hit[0])) > 1.1 or absf(float(hit[1])) > 1.3:
		return false          # (beside the car)
	var p := clampf(float(hit[0]), -1.0, 1.0)
	var h := clampf(float(hit[1]), -1.0, 1.0)
	layers[sel]["p"] = p
	layers[sel]["h"] = h
	_sync_props()
	_apply()
	return true
