extends Node3D
## The world editor (Welt-Editor): a free camera over one of the tracks and tools to reshape it –
## raise / lower / smooth / level the ground, water, new roads drawn as curves (live preview), and
## every tree, rock and object on the map can be picked, moved, turned, scaled and deleted; new
## ones are placed from all the game's assets or from uploaded 3D models (GLB, packed into the map).
## Saved as a copy of the track (user://maps) or exported to a file; a saved map can be raced on.

const MapData = preload("res://scripts/editor/map_data.gd")
const AssetLib = preload("res://scripts/editor/asset_lib.gd")
const RoadBuilder = preload("res://scripts/editor/road_builder.gd")
const Snap = preload("res://scripts/editor/snap.gd")
const TerrainPaint = preload("res://scripts/world/terrain_paint.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const MMUtil = preload("res://scripts/util/mm_util.gd")

const TOOLS := [
	["select", "Auswählen", "Klicken: Objekt / Baum wählen · Ziehen: verschieben · R / Shift+R: drehen · +/-: Größe · Bild↑/↓: Höhe · Entf: löschen"],
	["place", "Platzieren", "Objekt aus der Liste wählen · Klicken: setzen · R: drehen · +/-: Größe"],
	["raise", "Anheben", "Gedrückt halten: Gelände anheben (Pinselgröße / -stärke links)"],
	["lower", "Absenken", "Gedrückt halten: Gelände absenken"],
	["smooth", "Glätten", "Gedrückt halten: Gelände glätten"],
	["level", "Ebnen", "Gedrückt halten: auf die Höhe des ersten Klicks ebnen"],
	["water", "Wasser", "Klicken: Wasserfläche (Pinselgröße) · Bild↑/↓: Pegel · Entf: löschen"],
	["paint", "Malen", "Gedrückt halten: Textur malen (Textur, Pinselgröße / -stärke links) · Shift gedrückt: wegradieren"],
	["road", "Straße", "Klicken: Punkte setzen (Vorschau folgt der Maus) · Enter / Rechtsklick: fertig · Rücktaste: letzter Punkt · Esc: verwerfen"],
]
const INDEX_CELL := 16.0
const PICK_R := 3.5
const ROT_STEP := PI / 12.0

var world
var map                      # map_data.gd
var map_path := ""
var holder: Node3D           # the map's own things (MapContent)
var base_heights := PackedFloat32Array()   # the track's ground before any editing

var tool := "select"
var cam: Camera3D
var _focus := Vector3.ZERO
var _yaw := 0.6
var _pitch := -0.75
var _dist := 90.0
var _rmb := false
var _mmb := false

# brush
var brush_r := 18.0
var brush_s := 6.0
var protect_track := true
var _stroke := false
var _stroke_level := 0.0
var _stroke_old := {}        # vertex index -> height before the stroke (undo)
var _dirty := Rect2i()
var _has_dirty := false
var _rebuild_t := 0.0
var _ring: MeshInstance3D

# selection: items {kind: "node", node} / {kind: "spot", id} / {kind: "water", node} – one or many
var _sel: Array = []
var _drag := false
var _drag_start := Vector3.ZERO
var _drag_before: Array = []
var _boxing := false
var _box_from := Vector2.ZERO
var _box_rect: ColorRect
var _sel_box: MeshInstance3D
var paint_id := 1              # the texture the paint tool lays (terrain_paint.gd TEXTURES)
var _paint_before = null       # paint snapshot at the start of a stroke (undo)
var _paint_flush_t := 0.0
var _paint_box: Control
var _paint_btns := {}
var deflicker := true          # placed objects get a few mm of offset each: no flicker where they overlap
var _df_n := 0
var snap_objects := true       # G: dock onto other objects (side by side, stacked)
var snap_grid := false         # Shift+G: 1 m grid
var _drag_box := AABB()        # the dragged objects' bounds when the drag began
var _drag_has_box := false
var _drag_nodes: Array = []
var _ghost_at = null           # where a click would place the ghost (snapped)
var _snap_boxes: Array = []    # the checkboxes (kept in step with G / Shift+G)
var _clip: Array = []          # Ctrl+C: [asset, transform relative to the copied group's middle]
var _panels: Array = []        # the UI panels (the mouse wheel scrolls them, not the camera)

# placing
var place_asset := "tree_pine"
var _ghost: Node3D
var _ghost_rot := 0.0
var _ghost_scale := 1.0

# roads
var road_w := 10.0
var road_surface := "asphalt"
var road_flatten := true
var road_h := 0.0              # height above the ground (bridges) or below it (cuttings)
var _road_pts: Array = []
var _road_h_slider: HSlider
var _road_preview: MeshInstance3D
var _preview_t := 0.0
var _preview_dirty := false

# scenery index: id -> {pos, gy, orig (key of its original spot), list: [[mm, idx, MMI transform]], label, h, w, dead}
var _spots := {}
var _cells := {}            # Vector2i -> Array of spot ids
var _next_id := 0
var _indexed := false

var _undo: Array = []       # Callables
var _changed := false
var _mouse := Vector2.ZERO

# UI
var ui: CanvasLayer
var _hint: Label
var _status: Label
var _tool_btns := {}
var _palette: ItemList
var _palette_ids: Array = []
var _brush_box: Control
var _road_box: Control
var _name_edit: LineEdit
var _file_dlg: FileDialog


func setup(p_world, p_map, p_path: String, p_holder: Node3D, p_base: PackedFloat32Array) -> void:
	world = p_world
	map = p_map
	map_path = p_path
	holder = p_holder
	base_heights = p_base


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "EditorCam"
	cam.far = 6000.0
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()
	if world.local_car:
		_focus = world.local_car.global_position
		_yaw = world.local_car.global_rotation.y + PI
	_ring = MeshInstance3D.new()
	_ring.mesh = ImmediateMesh.new()
	_ring.material_override = _line_mat(Color(1.0, 0.85, 0.3))
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_sel_box = MeshInstance3D.new()
	_sel_box.mesh = ImmediateMesh.new()
	_sel_box.material_override = _line_mat(Color(0.3, 0.9, 1.0))
	_sel_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sel_box)
	_road_preview = MeshInstance3D.new()
	_road_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_road_preview)
	_build_ui()
	_build_index()
	_set_tool("select")
	_update_cam()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func _line_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	m.render_priority = 10
	return m


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	ui.add_child(root)
	# left: tools and their settings
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	var lp := UiKit.panel(left)
	lp.position = Vector2(10, 10)
	lp.custom_minimum_size = Vector2(300, 0)
	root.add_child(lp)
	_panels.append(lp)
	left.add_child(UiKit.label("WELT-EDITOR", 22, UiKit.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	for t in TOOLS:
		var b := UiKit.button(t[1], _set_tool.bind(t[0]), 140)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		_tool_btns[t[0]] = b
		grid.add_child(b)
	left.add_child(grid)
	# snapping
	for sn in [["An Objekten einrasten (G)", snap_objects, true], ["Raster 1 m (Shift+G)", snap_grid, false]]:
		var cb := CheckBox.new()
		cb.text = str(sn[0])
		cb.button_pressed = bool(sn[1])
		cb.focus_mode = Control.FOCUS_NONE
		var is_obj: bool = sn[2]
		cb.toggled.connect(func(on):
			if is_obj:
				snap_objects = on
			else:
				snap_grid = on)
		_snap_boxes.append(cb)
		left.add_child(cb)
	var dfc := CheckBox.new()
	dfc.text = "Deflicker-Modus"
	dfc.tooltip_text = "Gesetzte Objekte und Straßen bekommen je ein paar Millimeter Versatz,\ndamit ineinander gesetzte Flächen nicht flackern."
	dfc.button_pressed = deflicker
	dfc.focus_mode = Control.FOCUS_NONE
	dfc.toggled.connect(func(on): deflicker = on)
	left.add_child(dfc)
	var dfb := UiKit.button("Alle Objekte entflackern", _deflicker_all, 280)
	dfb.focus_mode = Control.FOCUS_NONE
	left.add_child(dfb)
	# brush
	_brush_box = VBoxContainer.new()
	var size_l := UiKit.label("Pinsel: %d m" % int(brush_r), 16)
	_brush_box.add_child(size_l)
	_brush_box.add_child(UiKit.slider(4, 120, 1, brush_r, func(v):
		brush_r = v
		size_l.text = "Pinsel: %d m" % int(v), 280))
	var str_l := UiKit.label("Stärke: %.1f" % brush_s, 16)
	_brush_box.add_child(str_l)
	_brush_box.add_child(UiKit.slider(0.5, 30, 0.5, brush_s, func(v):
		brush_s = v
		str_l.text = "Stärke: %.1f" % v, 280))
	var prot := CheckBox.new()
	prot.text = "Strecke schützen"
	prot.button_pressed = protect_track
	prot.focus_mode = Control.FOCUS_NONE
	prot.toggled.connect(func(on): protect_track = on)
	_brush_box.add_child(prot)
	left.add_child(_brush_box)
	# paint: the ten standard textures
	var pv := VBoxContainer.new()
	pv.add_child(UiKit.label("Textur", 16))
	var pg := GridContainer.new()
	pg.columns = 2
	pg.add_theme_constant_override("h_separation", 4)
	pg.add_theme_constant_override("v_separation", 4)
	for tx in TerrainPaint.TEXTURES:
		var tid: int = tx[0]
		var b := Button.new()
		b.text = str(tx[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(138, 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var sw := ColorRect.new()
		sw.color = tx[2]
		sw.custom_minimum_size = Vector2(14, 14)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.position = Vector2(118, 8)
		sw.size = Vector2(14, 14)
		b.add_child(sw)
		b.button_pressed = tid == paint_id
		b.pressed.connect(func():
			paint_id = tid
			for k in _paint_btns:
				_paint_btns[k].button_pressed = k == tid)
		_paint_btns[tid] = b
		pg.add_child(b)
	pv.add_child(pg)
	_paint_box = pv
	_paint_box.visible = false
	left.add_child(_paint_box)
	# road
	_road_box = VBoxContainer.new()
	var w_l := UiKit.label("Breite: %d m" % int(road_w), 16)
	_road_box.add_child(w_l)
	_road_box.add_child(UiKit.slider(3, 30, 0.5, road_w, func(v):
		road_w = v
		w_l.text = "Breite: %.1f m" % v
		_preview_dirty = true, 280))
	var names: Array = []
	for s in RoadBuilder.SURFACES:
		names.append(s[1])
	_road_box.add_child(UiKit.option(names, 0, func(i):
		road_surface = RoadBuilder.SURFACES[i][0]
		_preview_dirty = true, 280))
	var h_l := UiKit.label("Höhe: %.1f m" % road_h, 16)
	_road_box.add_child(h_l)
	_road_h_slider = UiKit.slider(-6, 25, 0.5, road_h, func(v):
		road_h = v
		h_l.text = "Höhe: %.1f m%s" % [v, "  (Brücke)" if v > 0.3 else ("  (vertieft)" if v < -0.3 else "")]
		_preview_dirty = true, 280)
	_road_h_slider.tooltip_text = "Höhe über dem Gelände. Eine gewählte Straße: Bild↑ / Bild↓ hebt und senkt sie."
	_road_box.add_child(_road_h_slider)
	var flat := CheckBox.new()
	flat.text = "Gelände anpassen"
	flat.button_pressed = road_flatten
	flat.focus_mode = Control.FOCUS_NONE
	flat.toggled.connect(func(on): road_flatten = on)
	_road_box.add_child(flat)
	left.add_child(_road_box)
	# asset palette
	_palette = ItemList.new()
	_palette.custom_minimum_size = Vector2(280, 300)
	_palette.focus_mode = Control.FOCUS_NONE
	_palette.item_selected.connect(func(i):
		place_asset = _palette_ids[i]
		_set_tool("place"))
	left.add_child(_palette)
	_fill_palette()
	var up := UiKit.button("3D-Modell hochladen (.glb)", _open_upload, 280)
	up.focus_mode = Control.FOCUS_NONE
	left.add_child(up)
	var undo := UiKit.button("Rückgängig (Strg+Z)", _do_undo, 280)
	undo.focus_mode = Control.FOCUS_NONE
	left.add_child(undo)
	# right: the map
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	var rp := UiKit.panel(right)
	_pin(rp, 1.0, 0.0, Vector2(-330, 10))
	_panels.append(rp)
	_box_rect = ColorRect.new()
	_box_rect.color = Color(0.3, 0.9, 1.0, 0.15)
	_box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_rect.visible = false
	root.add_child(_box_rect)
	rp.custom_minimum_size = Vector2(320, 0)
	root.add_child(rp)
	right.add_child(UiKit.label("Basis: " + Game.track_name(map.base_track), 16, UiKit.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.text = map.map_name
	_name_edit.custom_minimum_size = Vector2(300, 0)
	_name_edit.text_changed.connect(func(t): map.map_name = t)
	right.add_child(_name_edit)
	for b in [["Speichern", _save_copy], ["Exportieren …", _open_export], ["Testfahrt", _test_drive], ["Beenden", _quit]]:
		var btn := UiKit.button(b[0], b[1], 300)
		btn.focus_mode = Control.FOCUS_NONE
		right.add_child(btn)
	# bottom: hints
	_hint = UiKit.label("", 16, UiKit.TEXT)
	_pin(_hint, 0.0, 1.0, Vector2(330, -64))
	root.add_child(_hint)
	_status = UiKit.label("Kamera: WASD / Pfeile bewegen · Q/E drehen · Rechte Maus: drehen · Mittlere Maus: schieben · Mausrad: Zoom · Shift: schneller", 15, UiKit.TEXT_DIM)
	_pin(_status, 0.0, 1.0, Vector2(330, -36))
	root.add_child(_status)
	_file_dlg = FileDialog.new()
	_file_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_file_dlg.use_native_dialog = true
	_file_dlg.size = Vector2i(900, 600)
	root.add_child(_file_dlg)


## Anchors a control to a corner (ax, ay: 0 = left / top, 1 = right / bottom) at an offset.
static func _pin(c: Control, ax: float, ay: float, off: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = off.x
	c.offset_top = off.y
	c.grow_horizontal = Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_END


func _fill_palette() -> void:
	_palette.clear()
	_palette_ids.clear()
	var group := ""
	var entries: Array = AssetLib.ASSETS.duplicate()
	for id in map.models:
		entries.append(["model:" + str(id), str(map.models[id].get("name", id)).get_basename(), "Hochgeladen"])
	for a in entries:
		if a[2] != group:
			group = a[2]
			var gi := _palette.add_item("— %s —" % group)
			_palette.set_item_disabled(gi, true)
			_palette.set_item_selectable(gi, false)
			_palette_ids.append("")
		_palette.add_item("   " + a[1])
		_palette_ids.append(a[0])


func _set_tool(t: String) -> void:
	if _road_pts.size() > 0 and t != "road":
		_cancel_road()
	tool = t
	for k in _tool_btns:
		_tool_btns[k].button_pressed = k == t
	_brush_box.visible = t in ["raise", "lower", "smooth", "level", "water", "paint"]
	_paint_box.visible = t == "paint"
	_road_box.visible = t == "road"
	for d in TOOLS:
		if d[0] == t:
			_hint.text = d[2]
	if t != "select":
		_select({})
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if t == "place":
		_ghost = AssetLib.make(place_asset)
		if _ghost:
			add_child(_ghost)
			_ghost.scale = Vector3.ONE * _ghost_scale


func message(text: String) -> void:
	if _status:
		_status.text = text


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------
func _update_cam() -> void:
	var dir := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	var eye := _focus - dir * _dist
	var gy: float = world.terrain.height_at(eye.x, eye.z) + 2.0
	eye.y = maxf(eye.y, gy)
	cam.global_transform = Transform3D(Basis.looking_at(_focus - eye, Vector3.UP), eye)


func _process(delta: float) -> void:
	var typing := _name_edit and _name_edit.has_focus()
	var mv := Vector2.ZERO
	if not typing:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			mv.y += 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			mv.y -= 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			mv.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			mv.x += 1
		if Input.is_key_pressed(KEY_Q):
			_yaw += delta * 1.6
		if Input.is_key_pressed(KEY_E):
			_yaw -= delta * 1.6
	var fast := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	if mv != Vector2.ZERO:
		var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
		var right := Vector3(-cos(_yaw), 0, sin(_yaw))
		_focus += (fwd * mv.y + right * mv.x).normalized() * delta * (20.0 + _dist * 0.9) * fast
	_focus.y = lerpf(_focus.y, world.terrain.height_at(_focus.x, _focus.z), minf(delta * 4.0, 1.0))
	_update_cam()
	# the tool under the mouse
	var hit = _ground_hit(_mouse)
	_draw_ring(hit)
	if hit != null:
		if _ghost and tool == "place":
			_ghost.global_transform = Transform3D(Basis(Vector3.UP, _ghost_rot).scaled(Vector3.ONE * _ghost_scale), _snap_ghost(hit))
		if tool == "road" and _road_pts.size() > 0:
			_preview_dirty = true
	if _stroke and hit != null:
		_brush(hit, delta)
	_paint_flush_t -= delta
	if tool == "paint" and _paint_flush_t <= 0.0:
		_paint_flush_t = 0.06
		world.terrain.paint.flush()
	_rebuild_t -= delta
	if _has_dirty and (_rebuild_t <= 0.0 or not _stroke):
		_flush_terrain()
	_preview_t -= delta
	if _preview_dirty and _preview_t <= 0.0:
		_preview_t = 0.06
		_preview_dirty = false
		_update_road_preview(hit)
	_draw_selection()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _rmb:
			_yaw -= mm.relative.x * 0.005
			_pitch = clampf(_pitch - mm.relative.y * 0.004, -1.5, -0.08)
		elif _mmb:
			var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
			var right := Vector3(-cos(_yaw), 0, sin(_yaw))
			_focus += (-right * mm.relative.x + fwd * mm.relative.y) * _dist * 0.0018
		elif _drag:
			_drag_move()
		elif _boxing:
			_update_box()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				# over the panels the wheel scrolls them, not the camera
				if _over_ui(mb.position):
					return
				_dist = clampf(_dist * (0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14), 6.0, 1500.0)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and tool == "road" and _road_pts.size() >= 2:
					_finish_road()
				else:
					_rmb = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_mmb = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_click(mb.double_click, mb.shift_pressed)
				else:
					_release(mb.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		_key(event as InputEventKey)


func _over_ui(p: Vector2) -> bool:
	for c in _panels:
		if is_instance_valid(c) and (c as Control).visible and (c as Control).get_global_rect().has_point(p):
			return true
	return false


func _key(k: InputEventKey) -> void:
	var handled := true
	match k.keycode:
		KEY_Z:
			if k.ctrl_pressed:
				_do_undo()
			else:
				handled = false
		KEY_S:
			if k.ctrl_pressed:
				_save_copy()
			else:
				handled = false
		KEY_C:
			if k.ctrl_pressed:
				_copy()
			else:
				handled = false
		KEY_V:
			if k.ctrl_pressed:
				_paste()
			else:
				handled = false
		KEY_A:
			if k.ctrl_pressed:
				handled = true
			else:
				handled = false
		KEY_R:
			_rotate(-ROT_STEP if k.shift_pressed else ROT_STEP)
		KEY_G:
			if k.shift_pressed:
				_set_snap(snap_objects, not snap_grid)
			else:
				_set_snap(not snap_objects, snap_grid)
		KEY_PLUS, KEY_KP_ADD, KEY_EQUAL:
			_scale(1.1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_scale(1.0 / 1.1)
		KEY_PAGEUP:
			_raise(0.5 if not k.shift_pressed else 0.1)
		KEY_PAGEDOWN:
			_raise(-0.5 if not k.shift_pressed else -0.1)
		KEY_DELETE:
			_delete()
		KEY_ENTER, KEY_KP_ENTER:
			if tool == "road":
				_finish_road()
		KEY_BACKSPACE:
			if tool == "road" and _road_pts.size() > 0:
				_road_pts.pop_back()
				_preview_dirty = true
		KEY_ESCAPE:
			if tool == "road" and _road_pts.size() > 0:
				_cancel_road()
			else:
				_select({})
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			if not k.ctrl_pressed:
				_set_tool(TOOLS[k.keycode - KEY_1][0])
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _click(double: bool, shift := false) -> void:
	var hit = _ground_hit(_mouse)
	match tool:
		"select":
			var it := _pick_at(_mouse)
			# a track barrier: its stretch round the click can be taken out (Delete)
			var wall := _wall_at(_mouse)
			if not wall.is_empty() and (str(it.get("kind", "")) == "none" or it.is_empty()):
				_sel = [wall]
				message("Leitplanke ausgewählt (%d m) – Entf entfernt dieses Stück (Rückgängig: Strg+Z)" % int(float(wall["p1"]) - float(wall["p0"])))
				return
			if str(it.get("kind", "")) == "none":
				if not shift:
					_select({})
				message("%s gehört fest zur Karte und ist nicht editierbar." % str(it["why"]))
				return
			if it.is_empty():
				# empty ground: drag a box to select several
				if not shift:
					_select({})
				_boxing = true
				_box_from = _mouse
				_update_box()
				return
			if shift:
				_toggle(it)
				return
			if _index_of(it) < 0:
				_select(it)
			# drag: everything selected moves along
			if hit != null and _movable():
				_drag = true
				_drag_start = hit
				_drag_before = _states(_sel)
				_begin_drag_box()
		"place":
			if hit != null:
				_place(_ghost_at if _ghost_at != null else hit)
		"paint":
			if hit != null:
				_stroke = true
				_paint_before = world.terrain.paint.snapshot()
		"raise", "lower", "smooth", "level":
			if hit != null:
				_stroke = true
				_stroke_old = {}
				_stroke_level = world.terrain.height_at(hit.x, hit.z)
		"water":
			if hit != null:
				_add_water(hit)
		"road":
			if hit != null:
				if double and _road_pts.size() >= 2:
					_finish_road()
				else:
					_road_pts.append(hit)
					_preview_dirty = true


func _release(shift := false) -> void:
	if _stroke and tool == "paint":
		_stroke = false
		world.terrain.paint.flush()
		var snap = _paint_before
		_undo.append(func():
			world.terrain.paint.restore(snap))
		_changed = true
	if _stroke:
		_stroke = false
		_flush_terrain()
		world.terrain.refresh_collision()
		_follow_ground(_stroke_old)
		var old: Dictionary = _stroke_old
		_undo.append(func():
			_restore_heights(old))
		_changed = true
	if _drag:
		_drag = false
		var before: Array = _drag_before
		var moved := false
		for st in before:
			if _item_xf(st[0]) != st[1]:
				moved = true
		if moved:
			for st in before:
				if st[0]["kind"] == "node" and is_instance_valid(st[0]["node"]):
					_deflicker_node(st[0]["node"])
			_sync_objects()
			_undo.append(func():
				_restore_states(before))
			_changed = true
	if _boxing:
		_boxing = false
		_box_rect.visible = false
		_box_select(Rect2(_box_from, _mouse - _box_from).abs(), shift)


# ---------------------------------------------------------------------------
# Picking
# ---------------------------------------------------------------------------
func _ray(pos: Vector2) -> Array:
	return [cam.project_ray_origin(pos), cam.project_ray_normal(pos)]


## Where the mouse ray meets the ground (terrain, roads, placed things) – null when it misses.
func _ground_hit(pos: Vector2, exclude: Array[RID] = []):
	if cam == null:
		return null
	var r := _ray(pos)
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * 5000.0, 1, exclude)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		return res["position"]
	# beyond the collision grid: march the height field
	var p: Vector3 = r[0]
	for i in 400:
		p += r[1] * 8.0
		if p.y <= world.terrain.height_at(p.x, p.z):
			return p
	return null


## The thing under the mouse: placed objects and game objects by their colliders, scenery (trees,
## rocks, props …) by whether the mouse ray passes through its upright body – whichever is nearer
## the camera. Parts of the map that can't be edited (city blocks, the track, shared colliders)
## come back as {kind: "none", why: text}.
func _pick_at(mpos: Vector2) -> Dictionary:
	var r := _ray(mpos)
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	var q := PhysicsRayQueryParameters3D.create(ro, ro + rd * 5000.0, 0xFFFFFFFF)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	var ground = res.get("position") if not res.is_empty() else _ground_hit(mpos)
	# water (no collider): a plane under the ray
	for c in holder.get_children():
		if c.has_meta("water"):
			var w := c as MeshInstance3D
			var t := (w.global_position.y - ro.y) / rd.y if absf(rd.y) > 0.001 else -1.0
			if t > 0.0:
				var p: Vector3 = ro + rd * t
				var pm := w.mesh as PlaneMesh
				var lp: Vector3 = w.global_transform.affine_inverse() * p
				if absf(lp.x) < pm.size.x * 0.5 and absf(lp.z) < pm.size.y * 0.5 and (ground == null or ro.distance_to(p) <= ro.distance_to(ground) + 0.5):
					return {"kind": "water", "node": w}
	var hit_d := ro.distance_to(res["position"]) if not res.is_empty() else (ro.distance_to(ground) if ground != null else 800.0)
	# scenery along the ray up to what it hits: the nearest upright body the ray passes through
	var reach := minf(hit_d + 6.0, 900.0)
	var seen := {}
	var best := -1
	var best_t := 1e9
	var px := 1.0 / _focal_px()          # metres per pixel at 1 m
	var t := 0.0
	while t <= reach:
		for id in _ids_near(ro + rd * t, 16.0):
			if seen.has(id):
				continue
			seen[id] = true
			var e: Dictionary = _spots[id]
			if bool(e.get("dead", false)):
				continue
			var foot: Vector3 = e["pos"]
			var top: Vector3 = foot + Vector3(0, maxf(float(e["h"]), 0.3), 0)
			var cp := Geometry3D.get_closest_points_between_segments(ro, ro + rd * reach, foot, top)
			var along := ro.distance_to(cp[0])
			# its radius, plus a few pixels of slack so thin things (posts, signs) can be hit
			var radius := maxf(float(e["w"]) * 0.45, 0.3) + along * px * 5.0
			if (cp[0] as Vector3).distance_to(cp[1]) < radius and along < best_t:
				best_t = along
				best = id
		t += 12.0
	if best >= 0 and best_t <= hit_d + 1.0:
		return {"kind": "spot", "id": best}
	if not res.is_empty():
		var n = _pickable(res["collider"])
		if n is Node3D:
			return {"kind": "node", "node": n}
		if n is String:
			return {"kind": "none", "why": n}
	return {}


func _focal_px() -> float:
	return get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)


## The thing to move for a hit collider: a placed object, a loose game object (tyres, barrels, parked
## cars …) or the model a collider belongs to. null for the ground and the car (nothing to pick:
## a box can be dragged there), a text for parts of the map that can't be edited.
func _pickable(c: Object):
	if not (c is CollisionObject3D):
		return null
	var n := c as Node3D
	if n.name == "TerrainBody" or (world.local_car and (n == world.local_car or world.local_car.is_ancestor_of(n))):
		return null
	if world.track and world.track.is_ancestor_of(n):
		return "Die Strecke (Fahrbahn, Randsteine, Leitplanken)"
	# placed in the editor (or part of something placed)
	var a: Node = n
	while a and a != world:
		if a.has_meta("asset") or a.has_meta("road") or a.has_meta("city_build") or a.has_meta("city_prop"):
			return a
		a = a.get_parent()
	if n is RigidBody3D:
		return n
	var shapes := 0
	for ch in n.get_children():
		if ch is CollisionShape3D:
			shapes += 1
	# one collider for a whole model (a house, a hall): the model is the thing
	if n.get_parent() is MeshInstance3D and shapes <= 1:
		return n.get_parent()
	if shapes > 1 or n.get_parent() is MeshInstance3D:
		return {"BuildingColliders": "Die Gebäude der Stadt", "LampColliders": "Straßenlampen, Ampeln und Masten"}.get(str(n.name), "Dieser Teil der Karte")
	return n


func _select(it: Dictionary) -> void:
	_sel = [] if it.is_empty() else [it]
	_sel_message()


func _toggle(it: Dictionary) -> void:
	var i := _index_of(it)
	if i >= 0:
		_sel.remove_at(i)
	else:
		_sel.append(it)
	_sel_message()


func _index_of(it: Dictionary) -> int:
	for i in _sel.size():
		var s: Dictionary = _sel[i]
		if s["kind"] == it["kind"] and ((it["kind"] == "spot" and s["id"] == it["id"]) or (it["kind"] != "spot" and s["node"] == it["node"])):
			return i
	return -1


func _sel_message() -> void:
	if _sel.is_empty():
		message("")
	elif _sel.size() > 1:
		message("%d Objekte ausgewählt · Ziehen: verschieben · R: drehen · +/-: Größe · Entf: löschen · Strg+C / Strg+V" % _sel.size())
	else:
		var s: Dictionary = _sel[0]
		match str(s["kind"]):
			"node":
				var n: Node3D = s["node"]
				var nm := str(n.name)
				if n.has_meta("label"):
					nm = str(n.get_meta("label"))
				elif n.has_meta("asset"):
					var aid := str(n.get_meta("asset"))
					nm = "Kopie: Gebäude" if aid.begins_with("cbld:") else ("Kopie: " + aid.substr(6) if aid.begins_with("cprop:") else AssetLib.name_of(aid))
				elif n.has_meta("road"):
					nm = "Straße"
				message("Ausgewählt: %s" % nm)
			"spot":
				message("Ausgewählt: %s" % _spot_name(int(s["id"])))
			"water":
				message("Ausgewählt: Wasser (Bild↑/↓: Pegel)")


func _spot_name(id: int) -> String:
	var lab := str(_spots[id].get("label", ""))
	if lab.begins_with("Tree") or lab.begins_with("Oak"):
		return "Baum"
	if lab.begins_with("Bush") or lab.begins_with("Shrub") or lab.begins_with("Fern"):
		return "Busch"
	if lab.begins_with("Rock") or lab.begins_with("Stone"):
		return "Fels"
	return lab.trim_prefix("Prop_").trim_prefix("Fest_") if lab != "" else "Szenerie-Objekt"


# --- box select --------------------------------------------------------------
func _update_box() -> void:
	var r := Rect2(_box_from, _mouse - _box_from).abs()
	_box_rect.position = r.position
	_box_rect.size = r.size
	_box_rect.visible = r.size.length() > 4.0


func _box_select(r: Rect2, add: bool) -> void:
	if r.size.length() < 6.0:
		return
	var found: Array = []
	# the ground under the box (corners and centre), plus a margin
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for pt in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), r.get_center()]:
		var g = _ground_hit(pt)
		if g != null:
			lo = lo.min(Vector2(g.x, g.z))
			hi = hi.max(Vector2(g.x, g.z))
	if hi.x >= lo.x:
		lo -= Vector2(10, 10)
		hi += Vector2(10, 10)
		var ncell := (int((hi.x - lo.x) / INDEX_CELL) + 1) * (int((hi.y - lo.y) / INDEX_CELL) + 1)
		if ncell < 40000:
			for cz in range(floori(lo.y / INDEX_CELL), floori(hi.y / INDEX_CELL) + 1):
				for cx in range(floori(lo.x / INDEX_CELL), floori(hi.x / INDEX_CELL) + 1):
					for id in _cells.get(Vector2i(cx, cz), []):
						var e: Dictionary = _spots[id]
						var mid: Vector3 = e["pos"] + Vector3(0, float(e["h"]) * 0.5, 0)
						if not cam.is_position_behind(mid) and r.has_point(cam.unproject_position(mid)):
							found.append({"kind": "spot", "id": id})
	for c in holder.get_children():
		if c.has_meta("asset") and not cam.is_position_behind(c.global_position) and r.has_point(cam.unproject_position(c.global_position)):
			found.append({"kind": "node", "node": c})
	if not add:
		_sel = []
	for it in found:
		if _index_of(it) < 0:
			_sel.append(it)
	_sel_message()


# ---------------------------------------------------------------------------
# Scenery instances (trees, rocks, props …): every MultiMesh instance at the same spot is one thing,
# with an id; its LOD copies are edited together. Instance transforms are relative to their
# MultiMeshInstance (which can be moved, turned and scaled itself).
# ---------------------------------------------------------------------------
func _build_index() -> void:
	_indexed = true
	var t0 := Time.get_ticks_msec()
	var sc = world.scenery
	if sc == null:
		return
	# moved ones: their current spot -> their original one
	var moved := {}
	for k in map.edits:
		var v = map.edits[k]
		if v != null:
			moved[MapData.spot_key(MapData.arr_to_xf(v).origin)] = k
	var by_key := {}
	for r in sc._ranged:
		var mmi = r[0]
		if not (mmi is MultiMeshInstance3D) or not is_instance_valid(mmi):
			continue
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		if mm == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
			continue
		var mxf: Transform3D = (mmi as Node3D).global_transform
		var label := str(mmi.get_meta("label", "" if str(mmi.name).begins_with("@") else str(mmi.name)))
		var aabb: AABB = mm.mesh.get_aabb() if mm.mesh else AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
		var buf := mm.buffer
		var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
		for i in mm.instance_count:
			var j := i * stride
			if j + 11 >= buf.size():
				break
			var lb := Basis(Vector3(buf[j], buf[j + 4], buf[j + 8]), Vector3(buf[j + 1], buf[j + 5], buf[j + 9]), Vector3(buf[j + 2], buf[j + 6], buf[j + 10]))
			if absf(lb.determinant()) < 1e-6:
				continue      # removed (shrunk to nothing)
			var wxf := mxf * Transform3D(lb, Vector3(buf[j + 3], buf[j + 7], buf[j + 11]))
			var p := wxf.origin
			if p.y < -1000.0 or not p.is_finite():
				continue
			var key := MapData.spot_key(p)
			var id: int = by_key.get(key, -1)
			if id < 0:
				id = _next_id
				_next_id += 1
				by_key[key] = id
				var sy := wxf.basis.y.length()
				var sx := wxf.basis.x.length()
				_spots[id] = {"pos": p, "gy": _ground_y(p), "orig": moved.get(key, key), "list": [], "label": label,
					"h": maxf(aabb.end.y * sy, 0.6), "w": maxf(maxf(aabb.size.x, aabb.size.z) * sx, 0.6), "dead": false}
				_file(id)
			var e: Dictionary = _spots[id]
			e["list"].append([mm, i, mxf])
			if e["label"] == "" and label != "":
				e["label"] = label
	print("EDITOR: indexed %d scenery spots in %d ms" % [_spots.size(), Time.get_ticks_msec() - t0])


func _ground_y(p: Vector3) -> float:
	var h: float = world.terrain.height_at(p.x, p.z)
	return h if is_finite(h) else p.y


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / INDEX_CELL), floori(p.z / INDEX_CELL))


func _file(id: int) -> void:
	var c := _cell_of(_spots[id]["pos"])
	if not _cells.has(c):
		_cells[c] = []
	_cells[c].append(id)


func _unfile(id: int) -> void:
	var c := _cell_of(_spots[id]["pos"])
	if _cells.has(c):
		_cells[c].erase(id)


func _ids_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	for cz in range(floori((p.z - r) / INDEX_CELL), floori((p.z + r) / INDEX_CELL) + 1):
		for cx in range(floori((p.x - r) / INDEX_CELL), floori((p.x + r) / INDEX_CELL) + 1):
			out.append_array(_cells.get(Vector2i(cx, cz), []))
	return out


func _spot_xf(id: int) -> Transform3D:
	var l: Array = _spots[id]["list"][0]
	return (l[2] as Transform3D) * MMUtil.get_xf(l[0], l[1])


## Moves / turns / scales a scenery spot (all its LODs) – null removes it (shrunk to nothing where it
## stands, so its shaders and shadows have nothing left to draw).
func _spot_set(id: int, xf, record := true) -> void:
	var e: Dictionary = _spots[id]
	if xf != null and not (xf as Transform3D).origin.is_finite():
		return
	for l in e["list"]:
		var mm: MultiMesh = l[0]
		var mxf: Transform3D = l[2]
		if xf == null:
			MMUtil.hide(mm, l[1])
		else:
			MMUtil.set_xf(mm, l[1], mxf.affine_inverse() * (xf as Transform3D))
	if record:
		map.edits[e["orig"]] = null if xf == null else MapData.xf_to_arr(xf)
	if not e["dead"]:
		_unfile(id)
	e["dead"] = xf == null
	if xf != null:
		e["pos"] = (xf as Transform3D).origin
		e["gy"] = _ground_y(e["pos"])
		_file(id)


# ---------------------------------------------------------------------------
# Editing the selection (one or many)
# ---------------------------------------------------------------------------
func _item_xf(it: Dictionary):
	match str(it.get("kind", "")):
		"node", "water":
			var n: Node3D = it["node"]
			return n.global_transform if is_instance_valid(n) else Transform3D.IDENTITY
		"spot":
			return null if _spots[it["id"]]["dead"] else _spot_xf(it["id"])
		"wall":
			return Transform3D(Basis.IDENTITY, it["at"])
	return Transform3D.IDENTITY


func _item_set(it: Dictionary, xf: Transform3D) -> void:
	match str(it.get("kind", "")):
		"node":
			var n: Node3D = it["node"]
			if not is_instance_valid(n):
				return
			if not n.has_meta("asset") and not n.has_meta("orig_pos"):
				n.set_meta("orig_pos", n.global_position)
			if n is RigidBody3D:
				(n as RigidBody3D).freeze = true
			n.global_transform = xf
			if not n.has_meta("asset"):
				_record_node(n)
		"water":
			var w: Node3D = it["node"]
			if not is_instance_valid(w):
				return
			w.global_transform = xf
			var d: Dictionary = w.get_meta("water")
			d["c"] = [xf.origin.x, xf.origin.z]
			d["level"] = xf.origin.y
		"spot":
			_spot_set(it["id"], xf)


## Transforms of the given items (null for removed scenery), for undo.
func _states(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append([it, _item_xf(it)])
	return out


func _restore_states(states: Array) -> void:
	for st in states:
		var it: Dictionary = st[0]
		if st[1] == null:
			if it["kind"] == "spot":
				_spot_set(it["id"], null)
		else:
			if it["kind"] == "spot" and MapData.spot_key((st[1] as Transform3D).origin) == str(_spots[it["id"]]["orig"]):
				_spot_set(it["id"], st[1], false)
				map.edits.erase(_spots[it["id"]]["orig"])
			else:
				_item_set(it, st[1])
	_sync_objects()


## A game object (not one placed in the editor) that was moved: remembered by its original spot.
func _record_node(n: Node3D) -> void:
	if not n.has_meta("edit_orig"):
		n.set_meta("edit_orig", MapData.node_key(n.get_meta("orig_pos", n.global_position)))
	map.nodes[n.get_meta("edit_orig")] = MapData.xf_to_arr(n.global_transform)


func _drag_move() -> void:
	var ex: Array[RID] = []
	for it in _sel:
		if it["kind"] == "node" and it["node"] is CollisionObject3D:
			ex.append((it["node"] as CollisionObject3D).get_rid())
	var hit = _ground_hit(_mouse, ex)
	if hit == null or _sel.is_empty():
		return
	var d: Vector3 = hit - _drag_start
	d.y = 0.0
	var snapped := _snap_move(d)
	d = snapped[0]
	var top: float = snapped[1]
	for st in _drag_before:
		if st[1] == null:
			continue
		var xf: Transform3D = st[1]
		var to: Vector3 = xf.origin + d
		if not is_nan(top):
			# stacked: the group's bottom sits on the top it was dropped on
			to.y = xf.origin.y + top - _drag_box.position.y
		else:
			# stays as high above the ground as it stood
			var above: float = xf.origin.y - _ground_y(xf.origin)
			to.y = _ground_y(to) + above
		_item_set(st[0], Transform3D(xf.basis, to))
	_sync_objects()


## Where the placing ghost goes for a ground point: on the grid and/or docked onto objects.
func _snap_ghost(hit: Vector3) -> Vector3:
	var at := Snap.grid(hit) if snap_grid else hit
	if snap_grid:
		at.y = _ground_y(at)
	if snap_objects and _ghost:
		_ghost.global_transform = Transform3D(Basis(Vector3.UP, _ghost_rot).scaled(Vector3.ONE * _ghost_scale), at)
		var b := Snap.node_aabb(_ghost)
		if b.size != Vector3.ZERO:
			var res := Snap.dock(b, _snap_targets(at, []))
			at += res[0]
			if not is_nan(float(res[1])):
				at.y += float(res[1]) - b.position.y
	_ghost_at = at
	return at


## Deflicker: a placed object sits a few millimetres higher and is a hair bigger or smaller than
## its neighbours, so faces that lie in one plane (objects pushed into each other) never flicker.
func _deflicker_node(n: Node3D) -> void:
	if not deflicker or n == null or not is_instance_valid(n) or not n.has_meta("asset"):
		return
	var xf := n.global_transform
	if n.has_meta("df"):
		var o: Array = n.get_meta("df")
		xf.origin.y -= float(o[0])
		xf.basis = xf.basis.scaled(Vector3.ONE / float(o[1]))
	_df_n += 1
	var off := float(_df_n % 9 + 1) * 0.003
	var sc := 1.0 + float(_df_n % 5 + 1) * 0.0012 * (1.0 if _df_n % 2 == 0 else -1.0)
	xf.origin.y += off
	xf.basis = xf.basis.scaled(Vector3.ONE * sc)
	n.global_transform = xf
	n.set_meta("df", [off, sc])


func _deflicker_all() -> void:
	var was := deflicker
	deflicker = true
	var n := 0
	for c in holder.get_children():
		if c.has_meta("asset"):
			_deflicker_node(c)
			n += 1
	deflicker = was
	_sync_objects()
	_changed = true
	message("%d Objekte entflackert" % n)


## The dragged objects' bounds (their union) at the start of a drag.
func _begin_drag_box() -> void:
	_drag_has_box = false
	_drag_nodes = []
	for it in _sel:
		if it["kind"] != "node" or not is_instance_valid(it["node"]):
			continue
		_drag_nodes.append(it["node"])
		var b := Snap.node_aabb(it["node"])
		if b.size == Vector3.ZERO:
			continue
		_drag_box = b if not _drag_has_box else _drag_box.merge(b)
		_drag_has_box = true


## The drag offset with the grid and the docking applied: [offset, top it stands on or NAN].
func _snap_move(d: Vector3) -> Array:
	var top := NAN
	if snap_grid and not _drag_before.is_empty():
		var c0 := Vector3.ZERO
		var n := 0
		for st in _drag_before:
			if st[1] != null:
				c0 += (st[1] as Transform3D).origin
				n += 1
		c0 /= maxf(n, 1)
		var c1 := Snap.grid(c0 + d)
		d = Vector3(c1.x - c0.x, 0, c1.z - c0.z)
	if snap_objects and _drag_has_box:
		var moving := _drag_box
		moving.position += d
		var res := Snap.dock(moving, _snap_targets(moving.get_center(), _drag_nodes))
		d += res[0]
		top = res[1]
	return [d, top]


## Bounds of the placed objects and other movable things near a point (not the excluded ones).
func _snap_targets(near: Vector3, exclude: Array) -> Array:
	var out: Array = []
	for c in holder.get_children():
		if not (c is Node3D) or exclude.has(c) or c.has_meta("road") or c.has_meta("water"):
			continue
		var n := c as Node3D
		if Vector2(n.global_position.x - near.x, n.global_position.z - near.z).length() > Snap.REACH:
			continue
		var b := Snap.node_aabb(n)
		if b.size != Vector3.ZERO:
			out.append(b)
	return out


func _set_snap(objects: bool, grid_on: bool) -> void:
	snap_objects = objects
	snap_grid = grid_on
	if _snap_boxes.size() == 2:
		(_snap_boxes[0] as CheckBox).set_pressed_no_signal(objects)
		(_snap_boxes[1] as CheckBox).set_pressed_no_signal(grid_on)
	message("Einrasten an Objekten: %s · Raster 1 m: %s" % ["an" if objects else "aus", "an" if grid_on else "aus"])


## A built road a step higher or lower: rebuilt at its new height (undo puts the old one back).
func _road_height(body: Node3D, dy: float) -> void:
	var old: Dictionary = body.get_meta("road")
	var r := old.duplicate(true)
	r["height"] = clampf(float(old.get("height", 0.0)) + dy, -6.0, 25.0)
	r["flatten"] = false      # (the ground was levelled when it was first built)
	var idx := body.get_index()
	var nb := RoadBuilder.build(holder, world, r)
	if nb == null:
		return
	holder.move_child(nb, idx)
	holder.remove_child(body)
	_select({"kind": "node", "node": nb})
	_undo.append(func():
		if is_instance_valid(nb):
			holder.remove_child(nb)
			nb.queue_free()
		holder.add_child(body)
		holder.move_child(body, mini(idx, holder.get_child_count() - 1))
		_select({})
		_sync_objects())
	_sync_objects()
	_changed = true
	message("Straße auf %.1f m Höhe" % float(r["height"]))


## The track barrier under the mouse: {kind: wall, p0, p1 (metres along the track), side} for a
## 12 m stretch round the point (empty if the mouse isn't on a barrier).
func _wall_at(mpos: Vector2) -> Dictionary:
	var r := _ray(mpos)
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * 3000.0, 0xFFFFFFFF)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty() or not (res["collider"] is Node) or str((res["collider"] as Node).name) != "WallBody":
		return {}
	var t = world.track
	var pr: Array = t.project(res["position"], -1)
	var p := float(pr[1])
	return {"kind": "wall", "p0": maxf(p - 6.0, 0.0), "p1": minf(p + 6.0, float(t.length)), "side": signf(float(pr[2])), "at": res["position"]}


## Roads stay where they were drawn (delete and redraw them); water only changes level and size.
func _movable() -> bool:
	for it in _sel:
		if it["kind"] == "wall":
			return false
		if it["kind"] == "water" or (it["kind"] == "node" and (it["node"] as Node3D).has_meta("road")):
			return false
	return not _sel.is_empty()


## The middle of the selection (turning and scaling a group goes round it).
func _centre() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for it in _sel:
		var xf = _item_xf(it)
		if xf != null:
			c += (xf as Transform3D).origin
			n += 1
	return c / maxf(n, 1)


func _rotate(a: float) -> void:
	if tool == "place":
		_ghost_rot += a
		return
	if not _movable():
		return
	var c := _centre()
	var rot := Basis(Vector3.UP, a)
	_edit_all(func(xf: Transform3D) -> Transform3D:
		return Transform3D(rot * xf.basis, c + rot * (xf.origin - c)))


func _scale(f: float) -> void:
	if tool == "place":
		_ghost_scale = clampf(_ghost_scale * f, 0.1, 20.0)
		if _ghost:
			_ghost.scale = Vector3.ONE * _ghost_scale
		return
	if _sel.size() == 1 and _sel[0]["kind"] == "water":
		var w: MeshInstance3D = _sel[0]["node"]
		var pm := w.mesh as PlaneMesh
		pm.size *= f
		var d: Dictionary = w.get_meta("water")
		d["size"] = [pm.size.x, pm.size.y]
		_changed = true
		_sync_objects()
		return
	if not _movable():
		return
	var c := _centre()
	_edit_all(func(xf: Transform3D) -> Transform3D:
		var o := c + (xf.origin - c) * f
		o.y = xf.origin.y
		return Transform3D(xf.basis.scaled(Vector3.ONE * f), o))


func _raise(dy: float) -> void:
	if _sel.size() == 1 and _sel[0]["kind"] == "node" and is_instance_valid(_sel[0]["node"]) \
			and (_sel[0]["node"] as Node3D).has_meta("road"):
		_road_height(_sel[0]["node"], dy)
		return
	if _sel.size() == 1 and _sel[0]["kind"] == "water":
		var w: Node3D = _sel[0]["node"]
		var before := _states(_sel)
		_item_set(_sel[0], Transform3D(w.global_transform.basis, w.global_transform.origin + Vector3(0, dy, 0)))
		_undo.append(func(): _restore_states(before))
		_changed = true
		return
	if not _movable():
		return
	_edit_all(func(xf: Transform3D) -> Transform3D:
		return Transform3D(xf.basis, xf.origin + Vector3(0, dy, 0)))


func _edit_all(f: Callable) -> void:
	var before := _states(_sel)
	for st in before:
		if st[1] != null:
			_item_set(st[0], f.call(st[1]))
	_sync_objects()
	_undo.append(func(): _restore_states(before))
	_changed = true


func _delete() -> void:
	if _sel.is_empty():
		return
	var before := _states(_sel)
	var removed: Array = []
	for it in _sel:
		match str(it["kind"]):
			"wall":
				var gap := [float(it["p0"]), float(it["p1"]), float(it["side"])]
				world.track.wall_gaps.append(gap)
				map.wall_gaps.append(gap)
				world.track.rebuild_walls()
				removed.append([null, null, "", gap])
			"spot":
				if not _spots[it["id"]]["dead"]:
					_spot_set(it["id"], null)
			"node", "water":
				var n: Node3D = it["node"]
				if not is_instance_valid(n):
					continue
				var parent := n.get_parent()
				if n.has_meta("asset") or n.has_meta("road") or n.has_meta("water"):
					parent.remove_child(n)
					removed.append([n, parent])
				else:
					# a game object: hidden and without collision, remembered as removed
					var key := MapData.node_key(n.get_meta("orig_pos", n.global_position))
					n.set_meta("edit_orig", key)
					map.nodes[key] = null
					n.visible = false
					n.process_mode = Node.PROCESS_MODE_DISABLED
					removed.append([n, null, key])
	_undo.append(func():
		for r in removed:
			if r.size() > 3:
				world.track.wall_gaps.erase(r[3])
				map.wall_gaps.erase(r[3])
				world.track.rebuild_walls()
				continue
			var n: Node3D = r[0]
			if r[1] != null:
				(r[1] as Node).add_child(n)
			else:
				n.visible = true
				n.process_mode = Node.PROCESS_MODE_INHERIT
				map.nodes.erase(r[2])
		var spots_back: Array = []
		for st in before:
			if st[0]["kind"] == "spot":
				spots_back.append(st)
		_restore_states(spots_back))
	_select({})
	_sync_objects()
	_changed = true


func _do_undo() -> void:
	if _undo.is_empty():
		message("Nichts rückgängig zu machen")
		return
	var f: Callable = _undo.pop_back()
	f.call()
	_select({})
	_sync_objects()
	message("Rückgängig")


# --- copy & paste ------------------------------------------------------------
## Ctrl+C: what is selected, relative to its middle (scenery is pasted as placed copies).
func _copy() -> void:
	_clip = []
	var c := _centre()
	var skipped := 0
	for it in _sel:
		var xf = _item_xf(it)
		if xf == null:
			continue
		var asset := ""
		if it["kind"] == "node" and (it["node"] as Node3D).has_meta("asset"):
			asset = str((it["node"] as Node3D).get_meta("asset"))
		elif it["kind"] == "node" and (it["node"] as Node3D).has_meta("copy_asset"):
			asset = str((it["node"] as Node3D).get_meta("copy_asset"))
		elif it["kind"] == "spot":
			var e: Dictionary = _spots[it["id"]]
			if str(e["label"]) != "":
				var l: Array = e["list"][0]
				var mm: MultiMesh = l[0]
				var col := mm.get_instance_custom_data(l[1]) if mm.use_custom_data else Color(1, 1, 1, 1)
				asset = "scn:%s#%s" % [e["label"], col.to_html(true)]
		if asset == "":
			skipped += 1
			continue
		var x: Transform3D = xf
		var rel := x.origin - c
		rel.y = x.origin.y - _ground_y(x.origin)      # height above the ground
		_clip.append([asset, Transform3D(x.basis, rel)])
	message("%d kopiert%s – Strg+V setzt sie unter die Maus" % [_clip.size(), " (%d Spielobjekte lassen sich nicht kopieren)" % skipped if skipped > 0 else ""])


## Ctrl+V: the copied things around the point under the mouse.
func _paste() -> void:
	if _clip.is_empty():
		return
	var hit = _ground_hit(_mouse)
	if hit == null:
		return
	var at: Vector3 = hit
	var placed: Array = []
	for c in _clip:
		var rel: Transform3D = c[1]
		var o := Vector3(at.x + rel.origin.x, 0, at.z + rel.origin.z)
		o.y = _ground_y(o) + rel.origin.y
		var body := MapData.place_object(holder, str(c[0]), Transform3D(rel.basis, o))
		if body:
			_deflicker_node(body)
			placed.append(body)
	_undo.append(func():
		for b in placed:
			if is_instance_valid(b):
				b.get_parent().remove_child(b)
				b.queue_free()
		_sync_objects())
	_sel = []
	for b in placed:
		_sel.append({"kind": "node", "node": b})
	_sync_objects()
	_changed = true
	_sel_message()


# ---------------------------------------------------------------------------
# Placing
# ---------------------------------------------------------------------------
func _place(at: Vector3) -> void:
	var xf := Transform3D(Basis(Vector3.UP, _ghost_rot).scaled(Vector3.ONE * _ghost_scale), at)
	var body := MapData.place_object(holder, place_asset, xf)
	if body == null:
		message("Kann %s nicht setzen" % AssetLib.name_of(place_asset))
		return
	_deflicker_node(body)
	_undo.append(func():
		if is_instance_valid(body):
			body.get_parent().remove_child(body)
			body.queue_free()
		_sync_objects())
	_sync_objects()
	_changed = true


## The map's lists from what is in the holder now.
func _sync_objects() -> void:
	map.objects = []
	map.water = []
	map.roads = []
	for c in holder.get_children():
		if c.has_meta("asset"):
			map.objects.append({"asset": c.get_meta("asset"), "xf": MapData.xf_to_arr((c as Node3D).global_transform)})
		elif c.has_meta("water"):
			map.water.append(c.get_meta("water"))
		elif c.has_meta("road"):
			map.roads.append(c.get_meta("road"))


# ---------------------------------------------------------------------------
# Terrain
# ---------------------------------------------------------------------------
func _brush(hit: Vector3, delta: float) -> void:
	if not hit.is_finite():
		return
	if tool == "paint":
		world.terrain.paint.dab(hit, brush_r, paint_id, minf(brush_s * delta * 0.35, 1.0), Input.is_key_pressed(KEY_SHIFT))
		return
	var t = world.terrain
	var c: float = t.CELL
	var o: Vector2 = t.origin
	var rc := int(ceil(brush_r / c))
	var cx := int(round((hit.x - o.x) / c))
	var cz := int(round((hit.z - o.y) / c))
	var ix0 := maxi(cx - rc, 1)
	var iz0 := maxi(cz - rc, 1)
	var ix1 := mini(cx + rc, int(t.nx) - 2)
	var iz1 := mini(cz + rc, int(t.nz) - 2)
	if ix0 > ix1 or iz0 > iz1:
		return
	var hs: PackedFloat32Array = t.heights
	var nx: int = t.nx
	var src := hs.duplicate() if tool == "smooth" else hs
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var wx := o.x + ix * c
			var wz := o.y + iz * c
			var d := Vector2(wx - hit.x, wz - hit.z).length()
			var k := 1.0 - smoothstep(brush_r * 0.45, brush_r, d)
			if k <= 0.0:
				continue
			if protect_track:
				k *= smoothstep(float(t.flat_r), float(t.flat_r) + 6.0, float(t._dist_raw(wx, wz)))
				if k <= 0.0:
					continue
			var i := iz * nx + ix
			if not _stroke_old.has(i):
				_stroke_old[i] = hs[i]
			match tool:
				"raise":
					hs[i] += brush_s * delta * k
				"lower":
					hs[i] -= brush_s * delta * k
				"smooth":
					var avg := (src[i - 1] + src[i + 1] + src[i - nx] + src[i + nx] + src[i] * 4.0) * 0.125
					hs[i] = lerpf(hs[i], avg, minf(k * delta * brush_s * 0.6, 1.0))
				"level":
					hs[i] = lerpf(hs[i], _stroke_level, minf(k * delta * brush_s * 0.4, 1.0))
	t.heights = hs
	var r := Rect2i(ix0, iz0, ix1 - ix0 + 1, iz1 - iz0 + 1)
	_dirty = _dirty.merge(r) if _has_dirty else r
	_has_dirty = true


func _flush_terrain() -> void:
	if not _has_dirty:
		return
	_has_dirty = false
	_rebuild_t = 0.12
	world.terrain.rebuild_region(_dirty.position.x, _dirty.position.y, _dirty.end.x, _dirty.end.y)


func _restore_heights(old: Dictionary) -> void:
	var t = world.terrain
	var hs: PackedFloat32Array = t.heights
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for i in old:
		hs[i] = old[i]
		var p := Vector2i(int(i) % int(t.nx), int(i) / int(t.nx))
		lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
		hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
	t.heights = hs
	if hi.x >= 0:
		t.rebuild_region(lo.x, lo.y, hi.x, hi.y)
		t.refresh_collision()
		_follow_ground(old)


## Trees and scenery on reshaped ground move with it (up or down).
func _follow_ground(changed: Dictionary) -> void:
	if changed.is_empty() or not _indexed:
		return
	var t = world.terrain
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in changed:
		var p := Vector2(t.origin.x + (int(i) % int(t.nx)) * t.CELL, t.origin.y + (int(i) / int(t.nx)) * t.CELL)
		lo = lo.min(p)
		hi = hi.max(p)
	var ids: Array = []
	for cz in range(floori((lo.y - 4.0) / INDEX_CELL), floori((hi.y + 4.0) / INDEX_CELL) + 1):
		for cx in range(floori((lo.x - 4.0) / INDEX_CELL), floori((hi.x + 4.0) / INDEX_CELL) + 1):
			ids.append_array(_cells.get(Vector2i(cx, cz), []))
	for id in ids:
		var e: Dictionary = _spots[id]
		var p: Vector3 = e["pos"]
		var gy := _ground_y(p)
		var dy := gy - float(e["gy"])
		if absf(dy) < 0.01 or not is_finite(dy):
			continue
		var xf := _spot_xf(id)
		_spot_set(id, Transform3D(xf.basis, xf.origin + Vector3(0, dy, 0)))


func _draw_ring(hit) -> void:
	var im := _ring.mesh as ImmediateMesh
	im.clear_surfaces()
	if hit == null or not (tool in ["raise", "lower", "smooth", "level", "water"]):
		return
	var t = world.terrain
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 49:
		var a := TAU * i / 48.0
		var p := Vector3(hit.x + cos(a) * brush_r, 0, hit.z + sin(a) * brush_r)
		p.y = t.height_at(p.x, p.z) + 0.3
		im.surface_add_vertex(p)
	im.surface_end()


func _draw_selection() -> void:
	var im := _sel_box.mesh as ImmediateMesh
	im.clear_surfaces()
	if _sel.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := 0
	for it in _sel:
		n += 1
		if n > 200:
			break
		var xf = _item_xf(it)
		if xf == null:
			continue
		var bb := AABB(Vector3(-1.5, 0, -1.5), Vector3(3, 6, 3))
		match str(it["kind"]):
			"node":
				var nd: Node3D = it["node"]
				if not is_instance_valid(nd):
					continue
				bb = AssetLib.bounds(nd)
				if bb.size == Vector3.ZERO:
					bb = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
			"water":
				var pm := (it["node"] as MeshInstance3D).mesh as PlaneMesh
				bb = AABB(Vector3(-pm.size.x * 0.5, -0.2, -pm.size.y * 0.5), Vector3(pm.size.x, 0.4, pm.size.y))
			"spot":
				var l: Array = _spots[it["id"]]["list"][0]
				var mesh: Mesh = (l[0] as MultiMesh).mesh
				if mesh:
					bb = mesh.get_aabb()
		for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
			for k in e:
				im.surface_add_vertex((xf as Transform3D) * bb.get_endpoint(k))
	im.surface_end()


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------
func _add_water(at: Vector3) -> void:
	var w := {"c": [at.x, at.z], "size": [brush_r * 2.0, brush_r * 2.0], "level": at.y + 0.4}
	var mi := MapData.add_water(holder, w)
	_undo.append(func():
		if is_instance_valid(mi):
			mi.get_parent().remove_child(mi)
			mi.queue_free()
		_sync_objects())
	_select({"kind": "water", "node": mi})
	_sync_objects()
	_changed = true


# ---------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------
func _road_dict(pts: Array) -> Dictionary:
	var arr: Array = []
	for p in pts:
		arr.append([p.x, p.y, p.z])
	# deflicker: every road a little higher than the last, so crossing roads don't flicker
	var lift := 0.012 * float(map.roads.size() % 8 + 1) if deflicker else 0.0
	return {"pts": arr, "width": road_w, "surface": road_surface, "flatten": road_flatten, "height": road_h, "lift": lift}


func _update_road_preview(hit) -> void:
	var pts := _road_pts.duplicate()
	if hit != null and tool == "road":
		pts.append(hit)
	if pts.size() < 2:
		_road_preview.mesh = null
		return
	_road_preview.mesh = RoadBuilder.make_mesh(world, _road_dict(pts), false)
	if _road_preview.mesh:
		_road_preview.transparency = 0.35


func _finish_road() -> void:
	if _road_pts.size() < 2:
		return
	var r := _road_dict(_road_pts)
	var t = world.terrain
	var before: PackedFloat32Array = t.heights.duplicate() if road_flatten else PackedFloat32Array()
	var body := RoadBuilder.build(holder, world, r)
	_road_pts = []
	_road_preview.mesh = null
	if body == null:
		return
	# trees, bushes and rocks on the new road are cleared away
	var cleared := _clear_spots(RoadBuilder.centre_line(world, _pts_v3(r["pts"])), road_w * 0.5 + 1.5)
	var old := {}
	if road_flatten:
		var hs: PackedFloat32Array = t.heights
		for i in hs.size():
			if hs[i] != before[i]:
				old[i] = before[i]
		_follow_ground(old)
	_undo.append(func():
		if is_instance_valid(body):
			body.get_parent().remove_child(body)
			body.queue_free()
		if not old.is_empty():
			_restore_heights(old)
		for c in cleared:
			_spot_set(c[0], c[1], false)
			map.edits.erase(c[2])
		_sync_objects())
	_sync_objects()
	_changed = true
	message("Straße gebaut (%d m breit)" % int(road_w))


static func _pts_v3(arr: Array) -> Array:
	var out: Array = []
	for p in arr:
		out.append(Vector3(p[0], p[1], p[2]))
	return out


## Removes the scenery within `r` of a line: [[removed key, transform, original key]] (for undo).
func _clear_spots(line: PackedVector3Array, r: float) -> Array:
	var out: Array = []
	if line.size() < 2:
		return out
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in line:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var ids: Array = []
	for cz in range(floori((lo.y - r) / INDEX_CELL), floori((hi.y + r) / INDEX_CELL) + 1):
		for cx in range(floori((lo.x - r) / INDEX_CELL), floori((hi.x + r) / INDEX_CELL) + 1):
			ids.append_array(_cells.get(Vector2i(cx, cz), []))
	for id in ids:
		var e: Dictionary = _spots[id]
		var p: Vector3 = e["pos"]
		var q := Vector2(p.x, p.z)
		var near := false
		for i in line.size() - 1:
			var a := Vector2(line[i].x, line[i].z)
			var b := Vector2(line[i + 1].x, line[i + 1].z)
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < r:
				near = true
				break
		if near:
			var xf := _spot_xf(id)
			_spot_set(id, null)
			out.append([id, xf, e["orig"]])
	return out


func _cancel_road() -> void:
	_road_pts = []
	_road_preview.mesh = null


# ---------------------------------------------------------------------------
# Upload, save, test drive
# ---------------------------------------------------------------------------
func _open_upload() -> void:
	_reconnect(_file_dlg.file_selected, _on_upload)
	_file_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dlg.filters = PackedStringArray(["*.glb ; 3D-Modell (GLB)"])
	_file_dlg.title = "3D-Modell hochladen"
	_file_dlg.popup_centered()


func _on_upload(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		message("Datei nicht lesbar: " + path)
		return
	var id: String = map.add_model(path.get_file(), bytes)
	if not AssetLib.uploaded.has(id):
		map.models.erase(id)
		message("Kein gültiges GLB-Modell: " + path.get_file())
		return
	_fill_palette()
	place_asset = "model:" + id
	_set_tool("place")
	_changed = true
	message("Hochgeladen: %s (%d KB, wird mit der Karte gespeichert)" % [path.get_file(), bytes.size() / 1024])


func _open_export() -> void:
	_reconnect(_file_dlg.file_selected, _on_export)
	_file_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dlg.filters = PackedStringArray(["*.dmap ; Drift-Karte"])
	_file_dlg.title = "Karte exportieren"
	_file_dlg.current_file = MapData.safe_file_name(map.map_name) + ".dmap"
	_file_dlg.popup_centered()


static func _reconnect(sig: Signal, f: Callable) -> void:
	for c in sig.get_connections():
		sig.disconnect(c["callable"])
	sig.connect(f)


## Collects everything into the map (ground differences from the original track).
func _collect() -> void:
	_sync_objects()
	map.heights = {}
	var hs: PackedFloat32Array = world.terrain.heights
	if base_heights.size() == hs.size():
		for i in hs.size():
			if absf(hs[i] - base_heights[i]) > 0.001:
				map.heights[i] = hs[i]
	map.paint = world.terrain.paint.to_dict()


func _save_copy() -> void:
	_collect()
	if map_path == "" or not map_path.begins_with(MapData.MAP_DIR):
		map_path = MapData.MAP_DIR.path_join(MapData.safe_file_name(map.map_name) + ".dmap")
	if map.save(map_path):
		_changed = false
		message("Gespeichert: %s – im Einzelspieler unter „Eigene Karte“ fahrbar" % map.map_name)
	else:
		message("Speichern fehlgeschlagen")


func _on_export(path: String) -> void:
	_collect()
	if not path.ends_with(".dmap"):
		path += ".dmap"
	message(("Exportiert: " + path) if map.save(path) else "Export fehlgeschlagen")


func _test_drive() -> void:
	_save_copy()
	if not _changed:
		world.exit_requested.emit("map_test:" + map_path)


func _quit() -> void:
	if not _changed:
		world.exit_requested.emit("menu")
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Welt-Editor"
	dlg.dialog_text = "Ungespeicherte Änderungen. Speichern?"
	dlg.ok_button_text = "Speichern und beenden"
	dlg.cancel_button_text = "Verwerfen"
	ui.add_child(dlg)
	dlg.confirmed.connect(func():
		_save_copy()
		world.exit_requested.emit("menu"))
	dlg.canceled.connect(func(): world.exit_requested.emit("menu"))
	dlg.popup_centered()
