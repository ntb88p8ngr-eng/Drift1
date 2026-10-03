extends Node3D
## The world editor (Welt-Editor): a free camera over one of the tracks and tools to reshape it –
## raise / lower / smooth / level the ground, water, new roads drawn as curves (live preview), and
## every tree, rock and object on the map can be picked, moved, turned, scaled and deleted; new
## ones are placed from all the game's assets or from uploaded 3D models (GLB, packed into the map).
## Saved as a copy of the track (user://maps) or exported to a file; a saved map can be raced on.

const MapData = preload("res://scripts/editor/map_data.gd")
const AssetLib = preload("res://scripts/editor/asset_lib.gd")
const RoadBuilder = preload("res://scripts/editor/road_builder.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const TOOLS := [
	["select", "Auswählen", "Klicken: Objekt / Baum wählen · Ziehen: verschieben · R / Shift+R: drehen · +/-: Größe · Bild↑/↓: Höhe · Entf: löschen"],
	["place", "Platzieren", "Objekt aus der Liste wählen · Klicken: setzen · R: drehen · +/-: Größe"],
	["raise", "Anheben", "Gedrückt halten: Gelände anheben (Pinselgröße / -stärke links)"],
	["lower", "Absenken", "Gedrückt halten: Gelände absenken"],
	["smooth", "Glätten", "Gedrückt halten: Gelände glätten"],
	["level", "Ebnen", "Gedrückt halten: auf die Höhe des ersten Klicks ebnen"],
	["water", "Wasser", "Klicken: Wasserfläche (Pinselgröße) · Bild↑/↓: Pegel · Entf: löschen"],
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

# selection: {kind: "node", node} or {kind: "spot", key} or {kind: "water", node}
var _sel := {}
var _drag := false
var _drag_off := Vector3.ZERO
var _drag_from: Transform3D
var _sel_box: MeshInstance3D

# placing
var place_asset := "tree_pine"
var _ghost: Node3D
var _ghost_rot := 0.0
var _ghost_scale := 1.0

# roads
var road_w := 10.0
var road_surface := "asphalt"
var road_flatten := true
var _road_pts: Array = []
var _road_preview: MeshInstance3D
var _preview_t := 0.0
var _preview_dirty := false

# scenery index: spot key (current position) -> {pos, gy, orig, list: [[mm, idx, base]]}
var _spots := {}
var _cells := {}            # Vector2i -> Array of spot keys
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
	_brush_box.visible = t in ["raise", "lower", "smooth", "level", "water"]
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
			_ghost.global_transform = Transform3D(Basis(Vector3.UP, _ghost_rot).scaled(Vector3.ONE * _ghost_scale), hit)
		if tool == "road" and _road_pts.size() > 0:
			_preview_dirty = true
	if _stroke and hit != null:
		_brush(hit, delta)
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
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(_dist * 0.88, 6.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(_dist * 1.14, 1500.0)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and tool == "road" and _road_pts.size() >= 2:
					_finish_road()
				else:
					_rmb = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_mmb = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_click(mb.double_click)
				else:
					_release()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		_key(event as InputEventKey)


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
		KEY_R:
			_rotate(-ROT_STEP if k.shift_pressed else ROT_STEP)
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
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			_set_tool(TOOLS[k.keycode - KEY_1][0])
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _click(double: bool) -> void:
	var hit = _ground_hit(_mouse)
	match tool:
		"select":
			_pick()
			if _movable():
				var at = hit
				if at != null:
					_drag = true
					_drag_from = _sel_xf()
					_drag_off = _drag_from.origin - at
		"place":
			if hit != null:
				_place(hit)
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


func _release() -> void:
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
		var from := _drag_from
		var sel := _sel.duplicate()
		if _sel_xf() != from:
			_undo.append(func():
				_set_xf(sel, from))
			_changed = true


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


func _pick() -> void:
	var r := _ray(_mouse)
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * 5000.0, 0xFFFFFFFF)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	var ground = res.get("position") if not res.is_empty() else _ground_hit(_mouse)
	# water first (no collider): a plane under the ray
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	for c in holder.get_children():
		if c.has_meta("water"):
			var w := c as MeshInstance3D
			var t := (w.global_position.y - ro.y) / rd.y if absf(rd.y) > 0.001 else -1.0
			if t > 0.0:
				var p: Vector3 = ro + rd * t
				var pm := w.mesh as PlaneMesh
				var lp: Vector3 = w.global_transform.affine_inverse() * p
				if absf(lp.x) < pm.size.x * 0.5 and absf(lp.z) < pm.size.y * 0.5 and (ground == null or ro.distance_to(p) <= ro.distance_to(ground) + 0.5):
					_select({"kind": "water", "node": w})
					return
	if not res.is_empty():
		var body := _pickable(res["collider"])
		if body:
			_select({"kind": "node", "node": body})
			return
	if ground != null:
		var key := _nearest_spot(ground, PICK_R + 2.0)
		if key != "":
			_select({"kind": "spot", "key": key})
			return
	_select({})


## The thing to move for a hit collider (not the ground, the track or the car).
func _pickable(c: Object) -> Node3D:
	if not (c is CollisionObject3D):
		return null
	var n := c as Node3D
	if n.name == "TerrainBody" or n is VehicleBody3D or (world.local_car and (n == world.local_car or world.local_car.is_ancestor_of(n))):
		return null
	if world.track and world.track.is_ancestor_of(n):
		return null
	if n.has_meta("road"):
		return n
	return n


func _select(s: Dictionary) -> void:
	_sel = s
	if s.is_empty():
		message("")
		return
	match str(s["kind"]):
		"node":
			var n: Node3D = s["node"]
			message("Ausgewählt: %s" % (AssetLib.name_of(str(n.get_meta("asset"))) if n.has_meta("asset") else ("Straße" if n.has_meta("road") else str(n.name))))
		"spot":
			message("Ausgewählt: Baum / Szenerie-Objekt")
		"water":
			message("Ausgewählt: Wasser (Bild↑/↓: Pegel)")


# ---------------------------------------------------------------------------
# Scenery instances (trees, rocks, props …): every MultiMesh instance at the same spot is one thing
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
	for r in sc._ranged:
		var mmi = r[0]
		if not (mmi is MultiMeshInstance3D) or not is_instance_valid(mmi):
			continue
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		if mm == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
			continue
		var base: Vector3 = (mmi as Node3D).global_position
		var buf := mm.buffer
		var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
		for i in mm.instance_count:
			var j := i * stride
			var y := buf[j + 7] + base.y
			if y < -1000.0:
				continue
			var p := Vector3(buf[j + 3] + base.x, y, buf[j + 11] + base.z)
			var key := MapData.spot_key(p)
			var e: Dictionary = _spots.get(key, {})
			if e.is_empty():
				e = {"pos": p, "gy": float(world.terrain.height_at(p.x, p.z)), "orig": moved.get(key, key), "list": []}
				_spots[key] = e
				var c := Vector2i(floori(p.x / INDEX_CELL), floori(p.z / INDEX_CELL))
				if not _cells.has(c):
					_cells[c] = []
				_cells[c].append(key)
			e["list"].append([mm, i, base])
	print("EDITOR: indexed %d scenery spots in %d ms" % [_spots.size(), Time.get_ticks_msec() - t0])


func _nearest_spot(p: Vector3, r: float) -> String:
	var best := ""
	var bd := r
	var c0 := Vector2i(floori((p.x - r) / INDEX_CELL), floori((p.z - r) / INDEX_CELL))
	var c1 := Vector2i(floori((p.x + r) / INDEX_CELL), floori((p.z + r) / INDEX_CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for key in _cells.get(Vector2i(cx, cz), []):
				var q: Vector3 = _spots[key]["pos"]
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < bd:
					bd = d
					best = key
	return best


func _spot_xf(key: String) -> Transform3D:
	var e: Dictionary = _spots[key]
	var l: Array = e["list"][0]
	var xf: Transform3D = (l[0] as MultiMesh).get_instance_transform(l[1])
	return Transform3D(xf.basis, xf.origin + l[2])


## Moves / turns / scales a scenery spot (all its LODs) – null hides it (deleted). Returns its new key.
func _spot_set(key: String, xf, record := true) -> String:
	var e: Dictionary = _spots[key]
	for l in e["list"]:
		var mm: MultiMesh = l[0]
		if xf == null:
			mm.set_instance_transform(l[1], Transform3D(Basis.IDENTITY, Vector3(0, -3000, 0)))
		else:
			var x: Transform3D = xf
			mm.set_instance_transform(l[1], Transform3D(x.basis, x.origin - l[2]))
	if record:
		map.edits[e["orig"]] = null if xf == null else MapData.xf_to_arr(xf)
	# re-file under the new spot
	var old_c := Vector2i(floori(e["pos"].x / INDEX_CELL), floori(e["pos"].z / INDEX_CELL))
	if _cells.has(old_c):
		_cells[old_c].erase(key)
	_spots.erase(key)
	var p: Vector3 = Vector3(0, -3000, 0) if xf == null else (xf as Transform3D).origin
	var nkey := MapData.spot_key(p) if xf != null else "del:" + str(e["orig"])
	e["pos"] = p
	_spots[nkey] = e
	if xf != null:
		e["gy"] = float(world.terrain.height_at(p.x, p.z))
		var c := Vector2i(floori(p.x / INDEX_CELL), floori(p.z / INDEX_CELL))
		if not _cells.has(c):
			_cells[c] = []
		_cells[c].append(nkey)
	return nkey


# ---------------------------------------------------------------------------
# Editing the selection
# ---------------------------------------------------------------------------
func _sel_xf() -> Transform3D:
	match str(_sel.get("kind", "")):
		"node", "water":
			return (_sel["node"] as Node3D).global_transform
		"spot":
			return _spot_xf(_sel["key"])
	return Transform3D.IDENTITY


func _set_xf(sel: Dictionary, xf: Transform3D) -> void:
	match str(sel.get("kind", "")):
		"node":
			var n: Node3D = sel["node"]
			if not is_instance_valid(n):
				return
			n.global_transform = xf
			if not n.has_meta("asset"):
				_record_node(n)
		"water":
			var w: Node3D = sel["node"]
			if not is_instance_valid(w):
				return
			w.global_transform = xf
			var d: Dictionary = w.get_meta("water")
			d["c"] = [xf.origin.x, xf.origin.z]
			d["level"] = xf.origin.y
		"spot":
			var nk := _spot_set(sel["key"], xf)
			if _sel.get("key") == sel["key"]:
				_sel["key"] = nk
			sel["key"] = nk
	_sync_objects()


## A game object (not one placed in the editor) that was moved: remembered by its original spot.
func _record_node(n: Node3D) -> void:
	if not n.has_meta("edit_orig"):
		n.set_meta("edit_orig", MapData.node_key(n.get_meta("orig_pos", n.global_position)))
	map.nodes[n.get_meta("edit_orig")] = MapData.xf_to_arr(n.global_transform)


func _drag_move() -> void:
	var ex: Array[RID] = []
	if _sel.get("kind") == "node":
		ex.append((_sel["node"] as CollisionObject3D).get_rid())
	var hit = _ground_hit(_mouse, ex)
	if hit == null or _sel.is_empty():
		return
	var xf := _sel_xf()
	var to: Vector3 = hit + _drag_off
	# stays on the ground it stood on (scenery: its foot)
	var dy: float = xf.origin.y - world.terrain.height_at(xf.origin.x, xf.origin.z)
	to.y = world.terrain.height_at(to.x, to.z) + dy
	if _sel["kind"] == "node" and not (_sel["node"] as Node3D).has_meta("asset"):
		(_sel["node"] as Node3D).set_meta("orig_pos", (_sel["node"] as Node3D).get_meta("orig_pos", _drag_from.origin))
		if _sel["node"] is RigidBody3D:
			(_sel["node"] as RigidBody3D).freeze = true
	_set_xf(_sel, Transform3D(xf.basis, to))


## Roads stay where they were drawn (delete and redraw them); water only changes level and size.
func _movable() -> bool:
	if _sel.is_empty() or _sel["kind"] == "water":
		return false
	return not (_sel["kind"] == "node" and (_sel["node"] as Node3D).has_meta("road"))


func _rotate(a: float) -> void:
	if tool == "place":
		_ghost_rot += a
		return
	if not _movable():
		return
	var xf := _sel_xf()
	_edit_sel(Transform3D(Basis(Vector3.UP, a) * xf.basis, xf.origin))


func _scale(f: float) -> void:
	if tool == "place":
		_ghost_scale = clampf(_ghost_scale * f, 0.1, 20.0)
		if _ghost:
			_ghost.scale = Vector3.ONE * _ghost_scale
		return
	if _sel.is_empty() or not (_movable() or _sel["kind"] == "water"):
		return
	var xf := _sel_xf()
	if _sel["kind"] == "water":
		var w: MeshInstance3D = _sel["node"]
		var pm := w.mesh as PlaneMesh
		pm.size *= f
		var d: Dictionary = w.get_meta("water")
		d["size"] = [pm.size.x, pm.size.y]
		_changed = true
		_sync_objects()
		return
	_edit_sel(Transform3D(xf.basis.scaled(Vector3.ONE * f), xf.origin))


func _raise(dy: float) -> void:
	if _sel.is_empty() or not (_movable() or _sel["kind"] == "water"):
		return
	var xf := _sel_xf()
	_edit_sel(Transform3D(xf.basis, xf.origin + Vector3(0, dy, 0)))


func _edit_sel(xf: Transform3D) -> void:
	var from := _sel_xf()
	var sel := _sel.duplicate()
	if _sel["kind"] == "node" and not (_sel["node"] as Node3D).has_meta("asset"):
		(_sel["node"] as Node3D).set_meta("orig_pos", (_sel["node"] as Node3D).get_meta("orig_pos", from.origin))
	_set_xf(_sel, xf)
	sel["key"] = _sel.get("key", "")
	_undo.append(func():
		_set_xf(sel, from))
	_changed = true


func _delete() -> void:
	if _sel.is_empty():
		return
	var sel := _sel
	match str(sel["kind"]):
		"spot":
			var from := _spot_xf(sel["key"])
			var e: Dictionary = _spots[sel["key"]]
			var nk := _spot_set(sel["key"], null)
			_undo.append(func():
				var k2 := _spot_set(nk, from)
				if MapData.spot_key(from.origin) == e["orig"]:
					map.edits.erase(e["orig"])
				return k2)
		"node", "water":
			var n: Node3D = sel["node"]
			var parent := n.get_parent()
			if n.has_meta("asset") or n.has_meta("road") or n.has_meta("water"):
				parent.remove_child(n)
				_undo.append(func():
					parent.add_child(n)
					_sync_objects())
			else:
				# a game object: hidden and without collision, remembered as removed
				var key := MapData.node_key(n.get_meta("orig_pos", n.global_position))
				n.set_meta("edit_orig", key)
				map.nodes[key] = null
				n.visible = false
				n.process_mode = Node.PROCESS_MODE_DISABLED
				_undo.append(func():
					n.visible = true
					n.process_mode = Node.PROCESS_MODE_INHERIT
					map.nodes.erase(key))
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


# ---------------------------------------------------------------------------
# Placing
# ---------------------------------------------------------------------------
func _place(at: Vector3) -> void:
	var xf := Transform3D(Basis(Vector3.UP, _ghost_rot).scaled(Vector3.ONE * _ghost_scale), at)
	var body := MapData.place_object(holder, place_asset, xf)
	if body == null:
		message("Kann %s nicht setzen" % AssetLib.name_of(place_asset))
		return
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
	var keys: Array = []
	for cz in range(floori((lo.y - 4.0) / INDEX_CELL), floori((hi.y + 4.0) / INDEX_CELL) + 1):
		for cx in range(floori((lo.x - 4.0) / INDEX_CELL), floori((hi.x + 4.0) / INDEX_CELL) + 1):
			keys.append_array(_cells.get(Vector2i(cx, cz), []))
	for key in keys:
		var e: Dictionary = _spots[key]
		var p: Vector3 = e["pos"]
		var gy: float = t.height_at(p.x, p.z)
		var dy := gy - float(e["gy"])
		if absf(dy) < 0.01:
			continue
		var xf := _spot_xf(key)
		_spot_set(key, Transform3D(xf.basis, xf.origin + Vector3(0, dy, 0)))


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
	var bb := AABB(Vector3(-1.5, 0, -1.5), Vector3(3, 6, 3))
	var xf := _sel_xf()
	match str(_sel["kind"]):
		"node":
			var n: Node3D = _sel["node"]
			if not is_instance_valid(n):
				_sel = {}
				return
			bb = AssetLib.bounds(n)
			if bb.size == Vector3.ZERO:
				bb = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
		"water":
			var pm := (_sel["node"] as MeshInstance3D).mesh as PlaneMesh
			bb = AABB(Vector3(-pm.size.x * 0.5, -0.2, -pm.size.y * 0.5), Vector3(pm.size.x, 0.4, pm.size.y))
		"spot":
			var l: Array = _spots[_sel["key"]]["list"][0]
			var mesh: Mesh = (l[0] as MultiMesh).mesh
			if mesh:
				bb = mesh.get_aabb()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		for k in e:
			im.surface_add_vertex(xf * bb.get_endpoint(k))
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
	return {"pts": arr, "width": road_w, "surface": road_surface, "flatten": road_flatten}


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
			_spot_set(c[0], c[1])
			if MapData.spot_key(c[1].origin) == c[2]:
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
	var keys: Array = []
	for cz in range(floori((lo.y - r) / INDEX_CELL), floori((hi.y + r) / INDEX_CELL) + 1):
		for cx in range(floori((lo.x - r) / INDEX_CELL), floori((hi.x + r) / INDEX_CELL) + 1):
			keys.append_array(_cells.get(Vector2i(cx, cz), []))
	for key in keys:
		var e: Dictionary = _spots[key]
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
			var xf := _spot_xf(key)
			out.append([_spot_set(key, null), xf, e["orig"]])
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
