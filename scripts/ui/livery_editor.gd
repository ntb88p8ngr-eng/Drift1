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
var _shape_grid: GridContainer   # one colour
var _full_grid: GridContainer    # full colour
var _shape_note: Label
var _list: ItemList
var _props: VBoxContainer
var _ctl := {}             # property controls by key
var _syncing := false
var _dragging := false
var _orbit := false
var _custom: ColorPickerButton
var _placing := ""        # a shape picked from the grid, following the mouse over the car
var _place_rot := 0.0
var _place_size := 0.7
var _place_stretch := 0.0     # log2 width : height
var _hint: Label
var _pad := false          # the last input came from a gamepad: placing follows a cursor on the stick
var _pad_cursor := Vector2.ZERO
var _cursor: Control
var _handles: Control      # the selected sticker's outline with a handle on each corner
var _corners: Array = []   # their screen points (empty: none shown)
var _corner_drag := -1
var _designs: OptionButton
var _design_name: LineEdit


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
	_panel.custom_minimum_size = Vector2(600, 0)
	_panel.size = Vector2(600, get_viewport_rect().size.y - 120)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	v.add_child(UiKit.title("LACK & STICKER", 34))
	# the saved designs of this car: pick one to work on (it goes on the car), new, copy, rename, delete
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 6)
	_designs = OptionButton.new()
	_designs.custom_minimum_size = Vector2(150, 40)
	_designs.item_selected.connect(_pick_design)
	drow.add_child(_designs)
	_design_name = LineEdit.new()
	_design_name.custom_minimum_size = Vector2(130, 40)
	_design_name.placeholder_text = "Name"
	_design_name.text_submitted.connect(func(_t): _rename_design())
	_design_name.focus_exited.connect(_rename_design)
	drow.add_child(_design_name)
	drow.add_child(UiKit.button("Neu", func(): _new_design(false), 64))
	drow.add_child(UiKit.button("Kopie", func(): _new_design(true), 74))
	drow.add_child(UiKit.button("Löschen", _delete_design, 90))
	v.add_child(drow)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	v.add_child(body)
	var paint := _scroll(_paint_page())
	var stick := _scroll(_sticker_page())
	for p in [paint, stick]:
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		body.add_child(p)
		_pages.append(p)
	tabs.add_child(UiKit.button("Lack", func(): _show_page(0), 160))
	tabs.add_child(UiKit.button("Sticker", func(): _show_page(1), 160))
	_hint = UiKit.label("Klick aufs Auto: Sticker setzen / ziehen · Ecken ziehen: skalieren (Shift: proportional) · Q / E: drehen (Shift: fein) · Q / E: drehen (Shift: fein) · Strg+Z / Y: zurück / vor · Strg+C / V: kopieren / einfügen · rechte Maustaste: Kamera drehen · Mausrad: Zoom", 13, UiKit.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint)
	_show_page(1)
	# the shapes are drawn once (into user://decals)
	var gen := DecalShapes.new()
	add_child(gen)
	gen.done.connect(_fill_shapes)
	gen.ensure_all()
	_refresh_list()
	_refresh_designs()
	_apply()
	# the gamepad's cursor while placing: a ring with a cross
	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	_cursor.draw.connect(func():
		var a := Color(1, 1, 1, 0.9)
		_cursor.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 5.0, true)
		_cursor.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, a, 2.0, true)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_cursor.draw_line(d * 6.0, d * 22.0, a, 2.0, true))
	add_child(_cursor)
	_handles = Control.new()
	_handles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_handles.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handles.draw.connect(_draw_handles)
	add_child(_handles)
	move_child(_handles, 0)


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
			_remember_paint()
			main.refresh_showroom(false), 110, 40)
		b.tooltip_text = str(p["name"])
		grid.add_child(b)
	v.add_child(grid)
	# the colours used last (newest first)
	var recent: Array = Game.settings.get("recent_paints", [])
	if not recent.is_empty():
		v.add_child(UiKit.label("Zuletzt verwendet", 16, UiKit.TEXT_DIM))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for r in recent:
			var pid: String = str(r[0])
			var html: String = str(r[1])
			var b := _swatch_button(Color.from_string(html, Color.WHITE), func():
				if pid == "custom":
					Game.settings["custom_color"] = html
				Game.set_setting("paint", pid)
				_remember_paint()
				main.refresh_showroom(false), 44, 36)
			row.add_child(b)
		v.add_child(row)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(160, 40)
	cp.edit_alpha = false
	cp.color = Color.from_string(str(Game.settings.get("custom_color", "")), Color(0.3, 0.05, 0.5))
	cp.color_changed.connect(func(c):
		Game.settings["custom_color"] = c.to_html(false)
		Game.set_setting("paint", "custom")
		main.refresh_showroom(false))
	cp.popup_closed.connect(_remember_paint)
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
	sc.custom_minimum_size = Vector2(0, 300)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var kinds := VBoxContainer.new()
	kinds.add_theme_constant_override("separation", 6)
	kinds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(kinds)
	kinds.add_child(UiKit.label("Einfarbig – in der gewählten Farbe", 14, UiKit.TEXT))
	_shape_grid = GridContainer.new()
	kinds.add_child(_shape_grid)
	kinds.add_child(UiKit.label("Vollfarbe – im Original", 14, UiKit.TEXT))
	_full_grid = GridContainer.new()
	kinds.add_child(_full_grid)
	for g in [_shape_grid, _full_grid]:
		g.columns = 8
		g.add_theme_constant_override("h_separation", 4)
		g.add_theme_constant_override("v_separation", 4)
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
	# back / forward through the changes (Strg+Z / Strg+Y)
	var undo := UiKit.button("↶", _undo, 48)
	undo.alignment = HORIZONTAL_ALIGNMENT_CENTER
	undo.tooltip_text = "Zurück: letzte Änderung zurücknehmen (Strg+Z)"
	btns.add_child(undo)
	var redo := UiKit.button("↷", _redo_step, 48)
	redo.alignment = HORIZONTAL_ALIGNMENT_CENTER
	redo.tooltip_text = "Vor: zurückgenommene Änderung wiederholen (Strg+Y)"
	btns.add_child(redo)
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
			["size", "Größe (m)", 0.08, 3.0, 0.01], ["stretch", "Breite ↔ Höhe", -3.0, 3.0, 0.05], ["rot", "Drehung (°)", -180.0, 180.0, 0.1], ["alpha", "Deckkraft", 0.1, 1.0, 0.01]]:
		var key: String = k[0]
		_ctl[key] = UiKit.slider(k[2], k[3], k[4], 0.0, func(x): _set_prop(key, x), 240)
		_props.add_child(UiKit.labeled(k[1], _ctl[key], 170))
		if key == "rot":
			# fine turning: small steps either way (also Q / E on the car, with Shift 0.1°)
			var fine := HBoxContainer.new()
			fine.add_theme_constant_override("separation", 4)
			for d: float in [-5.0, -1.0, -0.1, 0.1, 1.0, 5.0]:
				var fb := UiKit.button(("%+.1f°" % d).replace(".0°", "°"), func(): _nudge_rot(d), 62)
				fb.alignment = HORIZONTAL_ALIGNMENT_CENTER
				fb.add_theme_font_size_override("font_size", 15)
				fine.add_child(fb)
			_props.add_child(UiKit.labeled("Fein drehen", fine, 170))
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
	_shape_note.text = "Form wählen, dann aufs Auto klicken – sie hängt bis dahin halb durchsichtig am Mauszeiger."
	for g in [_shape_grid, _full_grid]:
		for c in g.get_children():
			c.queue_free()
	for s in Livery.shapes():
		var id: String = s[0]
		var full := Livery.full_color(id)
		var b := Button.new()
		# the grid's whole width (8 to a row), the icon nearly to the button's edge
		b.custom_minimum_size = Vector2(60, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.icon = Livery.texture(id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb = b.get_theme_stylebox(st)
			if sb:
				sb = sb.duplicate()
				sb.set_content_margin_all(5)
				b.add_theme_stylebox_override(st, sb)
		# hovering (or the gamepad's focus): the shape big next to the panel
		var tex: Texture2D = b.icon
		var nm := str(s[1])
		b.mouse_entered.connect(func(): _show_big(b, tex, nm, full))
		b.focus_entered.connect(func(): _show_big(b, tex, nm, full))
		b.mouse_exited.connect(func(): _show_big(null, null, "", false))
		b.focus_exited.connect(func(): _show_big(null, null, "", false))
		b.pressed.connect(func():
			shape = id
			_start_placing(id))
		(_full_grid if full else _shape_grid).add_child(b)
	_apply()


var _big: PanelContainer
var _big_tex: TextureRect
var _big_name: Label


## The shape under the mouse, big, beside the panel (null: hidden).
func _show_big(b: Control, tex: Texture2D, nm: String, full: bool) -> void:
	if _big == null:
		_big = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.07, 0.11, 0.94)
		sb.border_color = Color(0.62, 0.32, 1.0, 0.8)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(14)
		_big.add_theme_stylebox_override("panel", sb)
		_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_big.add_child(v)
		_big_tex = TextureRect.new()
		_big_tex.custom_minimum_size = Vector2(220, 220)
		_big_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_big_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_big_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_big_tex)
		_big_name = UiKit.label("", 18, UiKit.TEXT)
		_big_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_big_name.custom_minimum_size = Vector2(220, 0)
		_big_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(_big_name)
		add_child(_big)
	if b == null or not is_instance_valid(b):
		_big.visible = false
		return
	_big_tex.texture = tex
	# one-colour shapes in the picked colour (white on the dark panel when that is too dark to see)
	_big_tex.modulate = Color.WHITE if full or color.get_luminance() < 0.15 else color
	_big_name.text = nm
	_big.visible = true
	_big.reset_size()
	var r := b.get_global_rect()
	var vs := get_viewport_rect().size
	var x := _panel.get_global_rect().end.x + 14.0
	var y := clampf(r.get_center().y - _big.size.y * 0.5, 10.0, vs.y - _big.size.y - 10.0)
	_big.global_position = Vector2(x, y)


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


## Turns the selected sticker by `d` degrees (the slider follows and applies it).
func _nudge_rot(d: float) -> void:
	if sel < 0:
		return
	var v := wrapf(float(layers[sel].get("rot", 0.0)) + d, -180.0, 180.0)
	(_ctl["rot"] as HSlider).value = snappedf(v, 0.1)


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
	for k in ["p", "h", "size", "stretch", "rot", "alpha"]:
		(_ctl[k] as HSlider).value = float(l.get(k, 0.0))
	(_ctl["mirror"] as CheckBox).button_pressed = bool(l.get("mirror", false))
	_syncing = false


func _apply() -> void:
	_remember_state()
	if sr and sr.car and is_instance_valid(sr.car):
		Livery.apply(sr.car.body, layers)


# --- undo / copy & paste --------------------------------------------------------------------------
var _hist: Array = []          # earlier states of the layers (newest last)
var _redo: Array = []
var _last_state = null         # the layers as they were after the last change
var _last_key := ""            # car + design the history belongs to
var _last_t := 0.0
var _last_sel := -1
var _clip = null               # the copied sticker (Strg+C)


## Every change goes on the history (a slider drag counts as one change: steps within 0.6 s of
## each other on the same sticker are one).
func _remember_state() -> void:
	var key := "%s/%d" % [_car_id(), int(Game.livery_designs(_car_id())["active"])]
	if key != _last_key:
		_last_key = key
		_hist.clear()
		_redo.clear()
		_last_state = layers.duplicate(true)
		return
	if _last_state != null and layers == _last_state:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not (now - _last_t < 0.6 and sel == _last_sel and _last_state != null and (_last_state as Array).size() == layers.size()) or _hist.is_empty():
		_hist.append(_last_state)
		if _hist.size() > 80:
			_hist.pop_front()
	_redo.clear()
	_last_t = now
	_last_sel = sel
	_last_state = layers.duplicate(true)


func _restore(state: Array) -> void:
	layers = state.duplicate(true)
	_last_state = layers.duplicate(true)
	_last_t = 0.0
	sel = mini(sel, layers.size() - 1)
	if sel < 0 and layers.size() > 0:
		sel = layers.size() - 1
	_refresh_list()
	if sr and sr.car and is_instance_valid(sr.car):
		Livery.apply(sr.car.body, layers)


func _undo() -> void:
	if _hist.is_empty():
		return
	_redo.append(layers.duplicate(true))
	_restore(_hist.pop_back())


func _redo_step() -> void:
	if _redo.is_empty():
		return
	_hist.append(layers.duplicate(true))
	_restore(_redo.pop_back())


func _copy() -> void:
	if sel >= 0:
		_clip = (layers[sel] as Dictionary).duplicate(true)


## The copied sticker as a new layer on top, a little further along (so it does not hide the first).
func _paste() -> void:
	if _clip == null:
		return
	var l: Dictionary = (_clip as Dictionary).duplicate(true)
	l["p"] = clampf(float(l.get("p", 0.0)) + 0.1, -1.0, 1.0)
	_clip = l.duplicate(true)       # pasting again: the next one further on
	layers.append(l)
	sel = layers.size() - 1
	_changed(true)


# --- designs --------------------------------------------------------------------------------------
func _car_id() -> String:
	return str(Game.settings["car"])


func _refresh_designs() -> void:
	var d: Dictionary = Game.livery_designs(_car_id())
	_designs.clear()
	for e in d["list"]:
		_designs.add_item(str(e["name"]))
	_designs.select(int(d["active"]))
	_design_name.text = str((d["list"] as Array)[int(d["active"])]["name"])


## Another design onto the car (the one being worked on is kept first).
func _pick_design(i: int) -> void:
	save()
	Game.select_design(_car_id(), i)
	layers = Game.get_livery(_car_id())
	sel = layers.size() - 1
	_refresh_list()
	_refresh_designs()
	_apply()


func _new_design(copy: bool) -> void:
	save()
	var n: int = (Game.livery_designs(_car_id())["list"] as Array).size() + 1
	Game.add_design(_car_id(), ("Kopie von %s" % _design_name.text) if copy else ("Design %d" % n), layers if copy else [])
	layers = Game.get_livery(_car_id())
	sel = layers.size() - 1
	_refresh_list()
	_refresh_designs()
	_apply()


func _rename_design() -> void:
	Game.rename_design(_car_id(), _designs.selected, _design_name.text)
	_refresh_designs()


func _delete_design() -> void:
	Game.delete_design(_car_id(), _designs.selected)
	layers = Game.get_livery(_car_id())
	sel = layers.size() - 1
	_refresh_list()
	_refresh_designs()
	_apply()


func save() -> void:
	Game.set_livery(str(Game.settings["car"]), layers)


## Gamepad while placing (ahead of the menu's own focus moves): A sticks it on, X sticks it on and
## keeps the shape, LB / RB turn it, B cancels; the sticks move the cursor and the camera, the
## triggers set the size (see _process).
func _input(event: InputEvent) -> void:
	if not visible or sr == null:
		return
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.3):
		_pad = true
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		_pad = false
		if _cursor and _cursor.visible:
			_cursor.visible = false
	if _placing == "" or not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	get_viewport().set_input_as_handled()
	if not (event is InputEventJoypadButton and event.pressed):
		return
	match (event as InputEventJoypadButton).button_index:
		JOY_BUTTON_A:
			_stamp(_pad_cursor, false)
		JOY_BUTTON_X:
			_stamp(_pad_cursor, true)
		JOY_BUTTON_LEFT_SHOULDER:
			_place_rot = wrapf(_place_rot - 15.0, -180.0, 180.0)
			_preview(_pad_cursor)
		JOY_BUTTON_RIGHT_SHOULDER:
			_place_rot = wrapf(_place_rot + 15.0, -180.0, 180.0)
			_preview(_pad_cursor)
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			# fine turning
			_place_rot = wrapf(_place_rot + (1.0 if (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_UP else -1.0), -180.0, 180.0)
			_preview(_pad_cursor)
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			_place_stretch = clampf(_place_stretch + (0.25 if (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_RIGHT else -0.25), -3.0, 3.0)
			_preview(_pad_cursor)
		JOY_BUTTON_B:
			_stop_placing()


func _process(delta: float) -> void:
	if not visible or sr == null:
		return
	_update_handles()
	var dz := func(v: float) -> float: return 0.0 if absf(v) < 0.18 else v
	# right stick: the camera round the car (always)
	var rx: float = dz.call(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X))
	var ry: float = dz.call(Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var moved := false
	if rx != 0.0 or ry != 0.0:
		sr.booth_orbit(rx * 520.0 * delta, ry * 380.0 * delta)
		moved = true
	if _placing == "" or not _pad:
		return
	var vs := get_viewport_rect().size
	var lx: float = dz.call(Input.get_joy_axis(0, JOY_AXIS_LEFT_X))
	var ly: float = dz.call(Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if lx != 0.0 or ly != 0.0:
		_pad_cursor += Vector2(lx, ly) * 760.0 * delta
		moved = true
	_pad_cursor = _pad_cursor.clamp(Vector2(_panel.position.x + _panel.size.x + 20.0, 20.0), vs - Vector2(20, 20))
	var lt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if lt > 0.1 or rt > 0.1:
		_place_size = clampf(_place_size * (1.0 + (rt - lt) * 1.2 * delta), 0.08, 3.0)
		moved = true
	_cursor.visible = true
	_cursor.position = _pad_cursor
	_cursor.queue_redraw()
	if moved:
		_preview(_pad_cursor)


## The car under the mouse: place / drag the selected sticker; right mouse turns the camera.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or sr == null:
		return
	# Strg+Z / Strg+Y: undo / redo, Strg+C / Strg+V: copy / paste the selected sticker
	if event is InputEventKey and event.pressed and not event.is_echo() and (event as InputEventKey).is_command_or_control_pressed():
		var key := (event as InputEventKey).keycode
		var done := true
		if key == KEY_Z and (event as InputEventKey).shift_pressed or key == KEY_Y:
			_redo_step()
		elif key == KEY_Z:
			_undo()
		elif key == KEY_C:
			_copy()
		elif key == KEY_V:
			_paste()
		else:
			done = false
		if done:
			get_viewport().set_input_as_handled()
			return
	if _placing != "":
		if event is InputEventMouseMotion:
			_preview((event as InputEventMouseMotion).position)
			if _orbit:
				sr.booth_orbit(event.relative.x, event.relative.y)
			return
		if event is InputEventMouseButton and event.pressed:
			var mb := event as InputEventMouseButton
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
					if mb.ctrl_pressed:
						_place_stretch = clampf(_place_stretch + (0.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25), -3.0, 3.0)
					elif mb.shift_pressed:
						_place_size = clampf(_place_size * (1.08 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.92), 0.08, 3.0)
					elif mb.alt_pressed:
						_place_rot = wrapf(_place_rot + (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0), -180.0, 180.0)
					else:
						_place_rot = wrapf(_place_rot + (15.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -15.0), -180.0, 180.0)
					_preview(mb.position)
				MOUSE_BUTTON_LEFT:
					_stamp(mb.position, mb.shift_pressed)
				MOUSE_BUTTON_RIGHT:
					_stop_placing()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed:
			var k := (event as InputEventKey).keycode
			if k == KEY_Z or k == KEY_Y or k == KEY_C:
				_place_stretch = clampf(_place_stretch + (0.25 if k == KEY_C else -0.25), -3.0, 3.0)
				_preview(get_viewport().get_mouse_position())
				get_viewport().set_input_as_handled()
			elif k == KEY_Q or k == KEY_E:
				var step := 1.0 if (event as InputEventKey).shift_pressed else 15.0
				_place_rot = wrapf(_place_rot + (-step if k == KEY_Q else step), -180.0, 180.0)
				_preview(get_viewport().get_mouse_position())
				get_viewport().set_input_as_handled()
			elif k == KEY_ESCAPE:
				_stop_placing()
				get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and sel >= 0:
		var k := (event as InputEventKey).keycode
		if k == KEY_Q or k == KEY_E:
			var step := 0.1 if (event as InputEventKey).shift_pressed else 1.0
			_nudge_rot(-step if k == KEY_Q else step)
			get_viewport().set_input_as_handled()
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
			if mb.pressed and _corner_at(mb.position) >= 0:
				_corner_drag = _corner_at(mb.position)
				get_viewport().set_input_as_handled()
				return
			if not mb.pressed and _corner_drag >= 0:
				_corner_drag = -1
				return
			_dragging = mb.pressed and _place(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbit:
			sr.booth_orbit(mm.relative.x, mm.relative.y)
		elif _corner_drag >= 0:
			_drag_corner(mm.position, mm.shift_pressed)
		elif _dragging:
			_place(mm.position)


func _place(pos: Vector2) -> bool:
	if sel < 0:
		return false
	var ray = sr.booth_ray(pos)
	if ray == null:
		return false
	var hit = Livery.pick_surface(sr.car.body, ray[0], ray[1])
	if hit == null:
		return false          # (beside the car)
	layers[sel]["side"] = hit[0]
	layers[sel]["p"] = hit[1]
	layers[sel]["h"] = hit[2]
	_sync_props()
	_apply()
	return true


# --- corner handles: drag a corner to scale (Shift: keep the proportions) ---------------------------
func _update_handles() -> void:
	var pts: Array = []
	if sel >= 0 and sel < layers.size() and _placing == "" and sr.car and is_instance_valid(sr.car):
		var fr = Livery.sticker_frame(sr.car.body, layers[sel])
		if fr != null:
			var xf: Transform3D = sr.car.body.global_transform
			var e: Vector2 = fr[4] * 0.5
			for c in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var q: Vector3 = xf * (fr[0] + fr[2] * e.x * c.x + fr[3] * e.y * c.y + fr[1] * 0.01)
				if sr.cam.is_position_behind(q):
					pts = []
					break
				pts.append(sr.cam.unproject_position(q))
	if pts != _corners:
		_corners = pts
		_handles.queue_redraw()


func _draw_handles() -> void:
	if _corners.size() != 4:
		return
	var line := PackedVector2Array(_corners + [_corners[0]])
	_handles.draw_polyline(line, Color(0, 0, 0, 0.5), 3.0, true)
	_handles.draw_polyline(line, Color(1, 1, 1, 0.85), 1.5, true)
	for i in 4:
		var q: Vector2 = _corners[i]
		var on := i == _corner_drag
		_handles.draw_rect(Rect2(q - Vector2(7, 7), Vector2(14, 14)), UiKit.ACCENT if on else Color.WHITE)
		_handles.draw_rect(Rect2(q - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0, 0.7), false, 1.5)


func _corner_at(pos: Vector2) -> int:
	for i in _corners.size():
		if (pos - (_corners[i] as Vector2)).length() < 13.0:
			return i
	return -1


## The corner follows the mouse on the sticker's plane; the opposite corner stays mirrored about the
## centre (the sticker grows / shrinks round its middle).
func _drag_corner(pos: Vector2, keep: bool) -> void:
	var fr = Livery.sticker_frame(sr.car.body, layers[sel])
	var ray = sr.booth_ray(pos)
	if fr == null or ray == null:
		return
	var hit = Plane(fr[1], fr[0]).intersects_ray(ray[0], ray[1])
	if hit == null:
		return
	var o: Vector3 = (hit as Vector3) - fr[0]
	var w := maxf(absf(o.dot(fr[2])) * 2.0, 0.04)
	var h := maxf(absf(o.dot(fr[3])) * 2.0, 0.04)
	var l: Dictionary = layers[sel]
	if keep:
		var e: Vector2 = fr[4]
		var k := maxf(w / maxf(e.x, 1e-4), h / maxf(e.y, 1e-4))
		l["size"] = clampf(float(l.get("size", 0.7)) * k, 0.05, 4.0)
	else:
		var ss := Livery.size_for(l, w, h)
		l["size"] = clampf(ss.x, 0.05, 4.0)
		l["stretch"] = ss.y
	_sync_props()
	_apply()
	_handles.queue_redraw()


# --- placing straight onto the car ------------------------------------------------------------------
func _start_placing(id: String) -> void:
	_placing = id
	if _pad:
		# (the cursor starts on the car's middle)
		_pad_cursor = sr.cam.unproject_position(sr.car.global_position + Vector3(0, 0.7, 0)) if sr and sr.car else get_viewport_rect().size * 0.6
		_hint.text = "Linker Stick: Sticker bewegen · A: aufkleben · X: aufkleben + weitere · LB / RB: drehen (Steuerkreuz ↑ ↓: fein) · LT / RT: Größe · Steuerkreuz ← →: breiter / höher · rechter Stick: Kamera · B: abbrechen"
		_preview(_pad_cursor)
	else:
		_hint.text = "Klick aufs Auto: hier aufkleben (Shift+Klick: weitere) · Mausrad oder Q / E: drehen (Alt+Mausrad / Shift+Q / E: fein) · Shift+Mausrad: Größe · Strg+Mausrad oder Y / C: breiter / höher · Rechtsklick / Esc: abbrechen"


func _stop_placing() -> void:
	_placing = ""
	if _cursor:
		_cursor.visible = false
	_hint.text = "Klick aufs Auto: Sticker setzen / ziehen · Ecken ziehen: skalieren (Shift: proportional) · Q / E: drehen (Shift: fein) · Strg+Z / Y: zurück / vor · Strg+C / V: kopieren / einfügen · rechte Maustaste: Kamera drehen · Mausrad: Zoom"
	_apply()


## The layer the picked shape would become under the mouse (null: not over the car).
func _ghost(pos: Vector2):
	var ray = sr.booth_ray(pos)
	if ray == null:
		return null
	var hit = Livery.pick_surface(sr.car.body, ray[0], ray[1])
	if hit == null:
		return null
	var l := Livery.new_layer(_placing, color)
	l["side"] = hit[0]
	l["p"] = hit[1]
	l["h"] = hit[2]
	l["rot"] = _place_rot
	l["size"] = _place_size
	l["stretch"] = _place_stretch
	l["mirror"] = false
	return l


## Shows it half see-through on the car.
func _preview(pos: Vector2) -> void:
	var g = _ghost(pos)
	if g == null:
		_apply()
		return
	g["alpha"] = 0.5
	if sr and sr.car and is_instance_valid(sr.car):
		Livery.apply(sr.car.body, layers + [g])


## Sticks it on (Shift: keep the shape for the next one).
func _stamp(pos: Vector2, keep: bool) -> void:
	var g = _ghost(pos)
	if g == null:
		return
	layers.append(g)
	sel = layers.size() - 1
	_refresh_list()
	if keep:
		_preview(pos)
	else:
		_stop_placing()


## The paint now on the car goes to the front of the "last used" row (8 at most).
func _remember_paint() -> void:
	var pid := str(Game.settings.get("paint", "red"))
	var col: Color = Game.get_paint(pid, str(Game.settings.get("custom_color", "")), "gloss")["color"]
	var entry := [pid, "#" + col.to_html(false)]
	var recent: Array = Game.settings.get("recent_paints", [])
	for r in recent.duplicate():
		if str(r[1]) == entry[1]:
			recent.erase(r)
	recent.push_front(entry)
	Game.settings["recent_paints"] = recent.slice(0, 8)
	Game.save_settings()

