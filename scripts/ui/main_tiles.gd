extends Control
## The main screen's entries as slanted tiles with a drawn icon, a title and a line under it, on
## pages that slide sideways: ‹ › buttons, the dots, the mouse wheel, a swipe, LB / RB (gamepad)
## or Bild↑ / Bild↓; moving the focus onto a tile of the other page slides there too.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

const TILE := Vector2(318, 118)
const GAP := Vector2(22, 16)
const COLS := 2
const SKEW := 0.16

signal page_changed(page: int)

var page := 0
var _pages: Array = []        # [Control page, [tiles]]
var _names: Array = []
var _strip: Control
var _clip: Control
var _dots: HBoxContainer
var _title: Label
var _tw: Tween
var _drag_from := NAN


## entries per page: [[title, sub, icon, Callable], …]; names: one heading per page.
func setup(pages: Array, names: Array) -> void:
	_names = names
	var rows := 0
	for p in pages:
		rows = maxi(rows, ceili(float(p.size()) / COLS))
	# (the rows step to the right like the slant: the lowest row of the tallest page sets the width)
	var pw := COLS * TILE.x + (COLS - 1) * GAP.x + TILE.y * SKEW + (rows - 1) * (TILE.y + GAP.y) * SKEW * 0.5 + 12.0
	var ph := rows * TILE.y + (rows - 1) * GAP.y
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	# the page's name and the way to the other page
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_title = UiKit.label("", 15, UiKit.TEXT_DIM)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var prev := _arrow("‹", func(): set_page(page - 1))
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 8)
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	var next := _arrow("›", func(): set_page(page + 1))
	top.add_child(prev)
	top.add_child(_dots)
	top.add_child(next)
	v.add_child(top)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.custom_minimum_size = Vector2(pw, ph + 6.0)
	_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	_clip.gui_input.connect(_on_clip_input)
	v.add_child(_clip)
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_strip)
	for pi in pages.size():
		var holder := Control.new()
		holder.position = Vector2(pi * (pw + 40.0), 3.0)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_strip.add_child(holder)
		var tiles: Array = []
		var list: Array = pages[pi]
		for k in list.size():
			var e: Array = list[k]
			var t := _tile(str(e[0]), str(e[1]), str(e[2]), e[3])
			# a slanted column: each row a little further right, like the tiles' own slant
			var r := k / COLS
			var c := k % COLS
			t.position = Vector2(c * (TILE.x + GAP.x) + (rows - 1 - r) * (TILE.y + GAP.y) * SKEW * 0.5, r * (TILE.y + GAP.y))
			holder.add_child(t)
			tiles.append(t)
			t.focus_entered.connect(func(): set_page(pi))
		_pages.append([holder, tiles])
		var dot := Button.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.focus_mode = Control.FOCUS_NONE
		dot.tooltip_text = str(names[pi]) if pi < names.size() else ""
		dot.pressed.connect(func(): set_page(pi))
		_dots.add_child(dot)
	custom_minimum_size = Vector2(pw, ph + 60.0)
	_wire_focus()
	_show_page(0, false)


func first_tile() -> Button:
	return (_pages[0][1] as Array)[0] if not _pages.is_empty() else null


func set_page(p: int) -> void:
	p = clampi(p, 0, _pages.size() - 1)
	if p == page:
		return
	var old := page
	page = p
	_show_page(p, true)
	# the focus goes along (gamepad / keyboard), onto the tile in the same place
	var f := get_viewport().gui_get_focus_owner()
	var old_tiles: Array = _pages[old][1]
	if f and old_tiles.has(f):
		var tiles: Array = _pages[p][1]
		(tiles[mini(old_tiles.find(f), tiles.size() - 1)] as Button).grab_focus()
	page_changed.emit(p)


func _show_page(p: int, animate: bool) -> void:
	var x: float = -(_pages[p][0] as Control).position.x
	if _tw:
		_tw.kill()
	if animate:
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_property(_strip, "position:x", x, 0.32)
	else:
		_strip.position.x = x
	for i in _pages.size():
		for t in _pages[i][1]:
			(t as Button).mouse_filter = Control.MOUSE_FILTER_STOP if i == p else Control.MOUSE_FILTER_IGNORE
	for i in _dots.get_child_count():
		var d := _dots.get_child(i) as Button
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(7)
		sb.bg_color = UiKit.ACCENT if i == p else Color(1, 1, 1, 0.22)
		for st in ["normal", "hover", "pressed", "focus"]:
			d.add_theme_stylebox_override(st, sb)
	_title.text = ""          # (no page name – the dots show the page)


## Left / right off the edge of a page's grid leads onto the next page.
func _wire_focus() -> void:
	for pi in _pages.size():
		var tiles: Array = _pages[pi][1]
		for k in tiles.size():
			var t: Button = tiles[k]
			if k % COLS == COLS - 1 or k == tiles.size() - 1:
				if pi + 1 < _pages.size():
					var nt: Array = _pages[pi + 1][1]
					t.focus_neighbor_right = t.get_path_to(nt[mini((k / COLS) * COLS, nt.size() - 1)])
			if k % COLS == 0 and pi > 0:
				var pt: Array = _pages[pi - 1][1]
				t.focus_neighbor_left = t.get_path_to(pt[mini((k / COLS) * COLS + COLS - 1, pt.size() - 1)])


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var d := 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			d = 1
		elif event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			d = -1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEDOWN:
			d = 1
		elif event.keycode == KEY_PAGEUP:
			d = -1
	if d != 0:
		set_page(page + d)
		get_viewport().set_input_as_handled()


## The wheel and a sideways swipe over the tiles turn the page.
func _on_clip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				set_page(page + 1)
				accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				set_page(page - 1)
				accept_event()


func _gui_input(event: InputEvent) -> void:
	_on_clip_input(event)


func _unhandled_input(event: InputEvent) -> void:
	# a swipe: press, drag sideways, let go
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _clip.get_global_rect().has_point(event.position):
			_drag_from = event.position.x
		elif not event.pressed and not is_nan(_drag_from):
			var dx: float = event.position.x - _drag_from
			_drag_from = NAN
			if absf(dx) > 80.0:
				set_page(page + (1 if dx < 0.0 else -1))


func _arrow(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(38, 30)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b


func _tile(title: String, sub: String, icon: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = TILE
	b.size = TILE
	b.pressed.connect(cb)
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.07, 0.06, 0.11, 0.82)
	base.border_color = Color(0.62, 0.32, 1.0, 0.45)
	base.border_width_left = 5
	base.border_width_bottom = 1
	base.border_width_top = 1
	base.border_width_right = 1
	base.set_corner_radius_all(3)
	base.skew = Vector2(SKEW, 0)
	base.shadow_color = Color(0, 0, 0, 0.35)
	base.shadow_size = 6
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.1, 0.34, 0.92)
	hover.border_color = UiKit.ACCENT
	hover.border_width_left = 9
	var focus := hover.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.36, 0.16, 0.62, 0.95)
	focus.shadow_color = Color(0.62, 0.32, 1.0, 0.45)
	focus.shadow_size = 14
	var pressed := focus.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.5, 0.25, 0.85, 1.0)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	var ic := MenuIcon.new()
	ic.kind = icon
	ic.position = Vector2(30, (TILE.y - 46.0) * 0.5)
	ic.size = Vector2(46, 46)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var t := UiKit.label(title, 27, UiKit.TEXT)
	t.position = Vector2(94, TILE.y * 0.5 - (30.0 if sub != "" else 19.0))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	if sub == "":
		return b
	var s := UiKit.label(sub, 14, UiKit.TEXT_DIM)
	s.position = Vector2(95, TILE.y * 0.5 + 6.0)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(s)
	return b


## Line icons drawn in code (the font has no such symbols).
class MenuIcon extends Control:
	var kind := ""

	func _draw() -> void:
		var c := Color(0.94, 0.93, 0.98)
		var a := Color(0.62, 0.32, 1.0)
		var w := 3.0
		var s := size
		var m := s * 0.5
		match kind:
			"story":       # an open book
				draw_polyline(PackedVector2Array([Vector2(4, 10), Vector2(22, 14), Vector2(42, 10), Vector2(42, 38), Vector2(22, 42), Vector2(4, 38), Vector2(4, 10)]), c, w)
				draw_line(Vector2(22, 14), Vector2(22, 42), c, w)
				for y in [20.0, 27.0]:
					draw_line(Vector2(9, y), Vector2(18, y + 1.5), a, 2.0)
					draw_line(Vector2(26, y + 1.5), Vector2(37, y), a, 2.0)
			"single":      # a steering wheel
				draw_arc(m, 19, 0, TAU, 40, c, w)
				draw_arc(m, 5, 0, TAU, 20, a, w)
				draw_line(m + Vector2(-5, 0), m + Vector2(-19, 0), c, w)
				draw_line(m + Vector2(5, 0), m + Vector2(19, 0), c, w)
				draw_line(m + Vector2(0, 5), m + Vector2(0, 19), c, w)
			"online":      # a globe
				draw_arc(m, 19, 0, TAU, 40, c, w)
				draw_line(m + Vector2(-19, 0), m + Vector2(19, 0), c, 2.0)
				draw_line(m + Vector2(-16, -9), m + Vector2(16, -9), a, 2.0)
				draw_line(m + Vector2(-16, 9), m + Vector2(16, 9), a, 2.0)
				var pts := PackedVector2Array()
				for k in 21:
					var t := -PI * 0.5 + PI * k / 20.0
					pts.append(m + Vector2(cos(t) * 8.0, sin(t) * 19.0))
				draw_polyline(pts, c, 2.0)
				for k in pts.size():
					pts[k] = Vector2(2.0 * m.x - pts[k].x, pts[k].y)
				draw_polyline(pts, c, 2.0)
			"garage":      # two open-end spanners crossed
				for k in 2:
					var sgn := 1.0 if k == 0 else -1.0
					var lo := Vector2(23 - sgn * 13, 41)
					var hi := Vector2(23 + sgn * 10, 15)
					draw_line(lo, hi, c, 6.0)
					draw_circle(lo, 3.0, c)
					var jc := hi + Vector2(sgn * 3.5, -4.0)
					# the jaw: a thick ring open towards the outer corner
					if k == 0:
						draw_arc(jc, 6.0, 0.0, PI * 1.5, 18, c, 5.0)
					else:
						draw_arc(jc, 6.0, -PI * 0.5, PI, 18, c, 5.0)
			"tutorial":    # a chequered flag
				draw_line(Vector2(8, 6), Vector2(8, 42), c, w)
				for r in 3:
					for k in 4:
						var col := c if (r + k) % 2 == 0 else a
						draw_rect(Rect2(10 + k * 8, 8 + r * 7, 8, 7), col)
			"replays":     # play in a circle with a rewind tail
				draw_arc(m, 18, PI * 0.2, PI * 1.9, 32, c, w)
				draw_colored_polygon(PackedVector2Array([m + Vector2(-6, -9), m + Vector2(10, 0), m + Vector2(-6, 9)]), a)
				draw_colored_polygon(PackedVector2Array([m + Vector2(14, -16), m + Vector2(20, -6), m + Vector2(9, -7)]), c)
			"editor":      # a pencil over a grid
				for k in 3:
					draw_line(Vector2(4, 12 + k * 12), Vector2(42, 12 + k * 12), Color(c, 0.3), 1.5)
				draw_line(Vector2(10, 38), Vector2(36, 12), c, 7.0)
				draw_colored_polygon(PackedVector2Array([Vector2(6, 42), Vector2(7, 35), Vector2(13, 41)]), a)
			"leaderboard": # a trophy
				draw_arc(Vector2(23, 12), 12, 0, PI, 20, c, w)
				draw_line(Vector2(11, 12), Vector2(35, 12), c, w)
				draw_arc(Vector2(10, 17), 5, PI * 0.5, PI * 1.5, 10, c, 2.0)
				draw_arc(Vector2(36, 17), 5, -PI * 0.5, PI * 0.5, 10, c, 2.0)
				draw_line(Vector2(23, 24), Vector2(23, 34), c, w)
				draw_rect(Rect2(14, 34, 18, 6), a)
			"controls":    # a gamepad
				draw_arc(Vector2(13, 26), 9, PI * 0.5, PI * 1.5, 14, c, w)
				draw_arc(Vector2(33, 26), 9, -PI * 0.5, PI * 0.5, 14, c, w)
				draw_line(Vector2(13, 17), Vector2(33, 17), c, w)
				draw_line(Vector2(13, 35), Vector2(33, 35), c, w)
				draw_line(Vector2(9, 26), Vector2(17, 26), a, 2.5)
				draw_line(Vector2(13, 22), Vector2(13, 30), a, 2.5)
				draw_circle(Vector2(31, 24), 2.2, a)
				draw_circle(Vector2(36, 28), 2.2, a)
			"options":     # a cog
				for k in 8:
					var t := TAU * k / 8.0
					draw_line(m + Vector2(cos(t), sin(t)) * 12.0, m + Vector2(cos(t), sin(t)) * 19.0, c, 5.0)
				draw_arc(m, 13, 0, TAU, 32, c, w)
				draw_arc(m, 5, 0, TAU, 16, a, w)
			"admin":       # a shield
				draw_polyline(PackedVector2Array([Vector2(23, 4), Vector2(40, 10), Vector2(38, 26), Vector2(23, 42), Vector2(8, 26), Vector2(6, 10), Vector2(23, 4)]), c, w)
				draw_line(Vector2(16, 23), Vector2(21, 29), a, w)
				draw_line(Vector2(21, 29), Vector2(31, 17), a, w)
			"credits":     # a star
				var st := PackedVector2Array()
				for k in 11:
					var t := -PI * 0.5 + TAU * k / 10.0
					st.append(m + Vector2(cos(t), sin(t)) * (19.0 if k % 2 == 0 else 8.0))
				draw_polyline(st, c, w)
				draw_circle(m, 3, a)
			"booth":       # a paint brush with a fresh stroke of paint
				var stroke := PackedVector2Array([Vector2(4, 42), Vector2(10, 33), Vector2(19, 30), Vector2(24, 35), Vector2(18, 41), Vector2(9, 44)])
				draw_colored_polygon(stroke, a)
				# bristles, ferrule, handle (diagonal up to the right)
				draw_colored_polygon(PackedVector2Array([Vector2(14, 34), Vector2(22, 26), Vector2(28, 32), Vector2(20, 40)]), c)
				draw_colored_polygon(PackedVector2Array([Vector2(22, 26), Vector2(26, 22), Vector2(32, 28), Vector2(28, 32)]), Color(c, 0.6))
				draw_line(Vector2(29, 25), Vector2(42, 12), c, 5.0)
				draw_circle(Vector2(42, 12), 2.5, c)
			"quit":        # power
				draw_arc(m, 17, -PI * 0.3, PI * 1.3, 32, c, w)
				draw_line(m + Vector2(0, -21), m + Vector2(0, -4), a, w)
