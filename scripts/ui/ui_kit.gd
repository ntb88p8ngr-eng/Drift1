extends RefCounted
## Theme and small widget helpers so all menus share one look (dark glass + midnight purple accent).

const ACCENT := Color(0.62, 0.32, 1.0)
const ACCENT_DARK := Color(0.32, 0.12, 0.55)
const TEXT := Color(0.94, 0.93, 0.98)
const TEXT_DIM := Color(0.7, 0.68, 0.78)
const GOOD := Color(0.45, 1.0, 0.55)
const BAD := Color(1.0, 0.35, 0.3)
const GOLD := Color(1.0, 0.82, 0.3)

static var _theme: Theme
static var _title_font: Font


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Bahnschrift", "Arial", "Helvetica", "Liberation Sans", "DejaVu Sans"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	t.default_font = font
	t.default_font_size = 19

	var normal := _box(Color(0.07, 0.06, 0.1, 0.82), Color(0.35, 0.2, 0.55, 0.9), 1)
	normal.border_width_left = 4
	var hover := _box(Color(0.22, 0.1, 0.38, 0.92), ACCENT, 1)
	hover.border_width_left = 4
	var pressed := _box(Color(0.4, 0.18, 0.7, 0.95), ACCENT, 2)
	var disabled := _box(Color(0.06, 0.06, 0.07, 0.6), Color(0.2, 0.2, 0.22), 1)
	var focus := _box(Color(0, 0, 0, 0), Color(0.85, 0.7, 1.0), 2)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color(0.45, 0.45, 0.5))
	var panel := _box(Color(0.04, 0.035, 0.07, 0.86), Color(0.35, 0.18, 0.6, 0.8), 1)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(18)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var edit := _box(Color(0.02, 0.02, 0.04, 0.9), Color(0.35, 0.2, 0.55), 1)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", _box(Color(0.02, 0.02, 0.04, 0.9), ACCENT, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "TextEdit", edit)
	t.set_stylebox("normal", "RichTextLabel", _box(Color(0.02, 0.02, 0.04, 0.6), Color(0.2, 0.12, 0.3), 1))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_color", "Label", TEXT)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(0.2, 0.18, 0.28)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	slider.set_corner_radius_all(3)
	t.set_stylebox("slider", "HSlider", slider)
	var fill := slider.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var popup := _box(Color(0.06, 0.05, 0.09, 0.97), ACCENT_DARK, 1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(Color(0.3, 0.14, 0.5, 1.0), ACCENT, 0))
	var sep := StyleBoxLine.new()
	sep.color = Color(0.4, 0.25, 0.6, 0.6)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var tab_sel := _box(Color(0.3, 0.14, 0.5, 0.95), ACCENT, 1)
	var tab_un := _box(Color(0.07, 0.06, 0.1, 0.85), Color(0.25, 0.15, 0.4), 1)
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_sel)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_sel)
	t.set_stylebox("panel", "TabContainer", panel)
	_theme = t
	return t


static func title_font() -> Font:
	if _title_font:
		return _title_font
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI Black", "Impact", "Arial Black", "DejaVu Sans"])
	f.font_weight = 800
	f.font_italic = true
	_title_font = f
	return f


static func _box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func label(text: String, size := 19, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func title(text: String, size := 54) -> Label:
	var l := label(text, size, Color.WHITE)
	l.add_theme_font_override("font", title_font())
	l.add_theme_color_override("font_shadow_color", Color(0.45, 0.1, 0.9, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func button(text: String, callback: Callable, min_width := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(callback)
	return b


static func option(items: Array, selected: int, callback: Callable, min_width := 280.0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	o.custom_minimum_size = Vector2(min_width, 42)
	o.item_selected.connect(callback)
	return o


static func slider(min_v: float, max_v: float, step: float, value: float, callback: Callable, min_width := 260.0) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(min_width, 28)
	s.value_changed.connect(callback)
	return s


static func row(children: Array, sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


static func col(children: Array, sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for c in children:
		v.add_child(c)
	return v


static func labeled(text: String, control: Control, label_width := 220.0) -> HBoxContainer:
	var l := label(text, 18, TEXT_DIM)
	l.custom_minimum_size = Vector2(label_width, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row([l, control])


static func panel(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_child(child)
	return p


static func spacer(h := 12.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func sep() -> HSeparator:
	return HSeparator.new()
