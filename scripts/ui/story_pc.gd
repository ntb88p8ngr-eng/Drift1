extends Control
## The office PC in the main-menu workshop: the story mode's chapter select, drawn as the computer's
## own screen (the menu lays it exactly over the monitor once the camera has flown there).
## Designed at 960 × 540 and scaled onto the monitor.

signal back_pressed
signal part_chosen(id: String)

const W := 960.0
const H := 540.0
const GREEN := Color(0.42, 1.0, 0.62)
const DIM := Color(0.25, 0.62, 0.4)
const AMBER := Color(1.0, 0.75, 0.3)
const BG := Color(0.015, 0.035, 0.03)

## The story's parts – built later; until then each is "in Arbeit".
const PARTS := [
	{"id": "prolog", "title": "Prolog – Regen über Neo Tokyo", "text": "Eine Nachricht mitten in der Nacht. Ein Treffpunkt am Hafen. Und ein Auto, das nicht dir gehört.", "ready": false},
	{"id": "part1", "title": "Teil 1 – Die erste Nacht", "text": "Die Crew will sehen, was du kannst. Drei Drifts, eine Chance.", "ready": false},
	{"id": "part2", "title": "Teil 2 – Hafen-Crew", "text": "Zwischen den Containern gelten eigene Regeln – und jemand schuldet jemandem Geld.", "ready": false},
	{"id": "part3", "title": "Teil 3 – Die Grüne Hölle", "text": "Das 24-Stunden-Festival. Der Ring bei Nacht. Kein Platz für Fehler.", "ready": false},
	{"id": "part4", "title": "Teil 4 – Bergkönig", "text": "Ein Pass, ein Rivale, eine alte Rechnung.", "ready": false},
	{"id": "finale", "title": "Finale – Midnight Drift", "text": "Ganz Neo Tokyo schaut zu.", "ready": false},
]

var _list: VBoxContainer
var _title: Label
var _text: Label
var _state: Label
var _log: Label
var _start: Button
var _sel := 0
var _mono: SystemFont
var _boot := 0.0
var _cursor: Polygon2D


func _ready() -> void:
	size = Vector2(W, H)
	pivot_offset = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 26)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(_label("MD-OS 2.4  ·  STORY.EXE", 22, GREEN))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label(Game.settings.get("player_name", "Driver") + "@werkstatt", 18, DIM))
	v.add_child(head)
	v.add_child(_rule())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.custom_minimum_size = Vector2(430, 0)
	cols.add_child(_list)
	for i in PARTS.size():
		var b := _button("", func(): _select(i, true))
		b.focus_entered.connect(func(): _select(i, false))
		b.mouse_entered.connect(func(): _select(i, false))
		_list.add_child(b)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_title = _label("", 22, GREEN)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_title)
	_text = _label("", 17, DIM)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_text)
	_state = _label("", 17, AMBER)
	right.add_child(_state)
	_start = _button("> STARTEN", func(): _select(_sel, true))
	right.add_child(_start)
	v.add_child(_rule())
	var foot := HBoxContainer.new()
	_log = _label("> Story-Teile werden geladen …", 16, DIM)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_log)
	foot.add_child(_button("< ZURÜCK", func(): back_pressed.emit()))
	v.add_child(foot)
	# scanlines and a soft vignette over everything (never catches the mouse)
	var crt := ColorRect.new()
	crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	float line = 0.5 + 0.5 * sin(UV.y * 540.0 * 3.14159);
	vec2 d = UV - 0.5;
	float vig = smoothstep(0.35, 0.75, length(d * vec2(1.0, 0.8)));
	COLOR = vec4(0.0, 0.0, 0.0, line * 0.16 + vig * 0.55);
}
"""
	mat.shader = sh
	crt.material = mat
	add_child(crt)
	# the computer's own mouse pointer (the system cursor is hidden while at the PC)
	_cursor = Polygon2D.new()
	_cursor.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 26), Vector2(7, 20), Vector2(12, 31),
		Vector2(17, 29), Vector2(12, 18), Vector2(20, 18)])
	_cursor.color = GREEN
	_cursor.z_index = 10
	_cursor.visible = false
	var edge := Line2D.new()
	edge.points = _cursor.polygon
	edge.closed = true
	edge.width = 2.0
	edge.default_color = BG
	_cursor.add_child(edge)
	add_child(_cursor)
	_refresh_list()
	_select(0, false)


## The in-game pointer at a position on the screen (or hidden).
func set_cursor(pos: Vector2, show: bool) -> void:
	if _cursor:
		_cursor.visible = show
		_cursor.position = pos.clamp(Vector2.ZERO, Vector2(W - 4, H - 4))


## Switched on: a short boot flicker, then the list takes the focus (gamepad / keyboard).
func power_on() -> void:
	_boot = 0.0
	modulate.a = 0.0
	_log.text = "> Story-Teile werden geladen …"
	set_process(true)
	(_list.get_child(_sel) as Button).grab_focus.call_deferred()


func _process(delta: float) -> void:
	_boot += delta
	modulate.a = clampf(_boot / 0.35, 0.0, 1.0) * (0.75 + 0.25 * float(int(_boot * 30.0) % 3 != 0)) if _boot < 0.5 else 1.0
	if _boot > 0.9 and _log.text.ends_with("…"):
		_log.text = "> %d Story-Teile gefunden. Auswahl mit ↑ ↓, Enter startet." % PARTS.size()
	if _boot > 1.0:
		set_process(false)


func _select(i: int, start: bool) -> void:
	_sel = i
	var p: Dictionary = PARTS[i]
	_title.text = str(p["title"])
	_text.text = str(p["text"])
	_state.text = "STATUS: BEREIT" if p["ready"] else "STATUS: IN ARBEIT"
	_start.disabled = not p["ready"]
	_refresh_list()
	if start:
		if p["ready"]:
			part_chosen.emit(str(p["id"]))
		else:
			_log.text = "> \"%s\" wird noch gebaut. Bald verfügbar." % str(p["title"]).get_slice(" – ", 0)


func _refresh_list() -> void:
	for i in _list.get_child_count():
		var p: Dictionary = PARTS[i]
		var b := _list.get_child(i) as Button
		b.text = ("> " if i == _sel else "  ") + str(p["title"]) + ("" if p["ready"] else "  [gesperrt]")


func _label(t: String, sz: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", _mono)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", _mono)
	b.add_theme_font_size_override("font_size", 18)
	for st in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(st, GREEN)
	b.add_theme_color_override("font_hover_color", BG)
	b.add_theme_color_override("font_pressed_color", BG)
	b.add_theme_color_override("font_disabled_color", DIM)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0)
	n.content_margin_left = 8
	n.content_margin_right = 8
	n.content_margin_top = 4
	n.content_margin_bottom = 4
	var f := n.duplicate() as StyleBoxFlat
	f.border_color = GREEN
	f.set_border_width_all(1)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = GREEN
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_stylebox_override("focus", f)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.pressed.connect(cb)
	return b


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = DIM
	r.custom_minimum_size = Vector2(0, 2)
	return r
