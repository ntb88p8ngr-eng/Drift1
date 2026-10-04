extends Control
## The office PC in the main-menu workshop: the story mode's chapter select, drawn as the computer's
## own screen (the menu lays it exactly over the monitor once the camera has flown there).
## Designed at 960 × 540 and scaled onto the monitor.

signal back_pressed
signal part_chosen(id: String)
signal code_redeemed            # an action code gave something (the menu refreshes credits / cars)

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
## the terminal (Ctrl+T): a fake remote session with a few commands
var _term: PanelContainer
var _term_out: RichTextLabel
var _term_in: LineEdit
var _term_queue: Array = []     # [delay, text] lines still to come (the connection sequence)
var _term_t := 0.0
var _term_hist: Array = []
var _term_hist_i := 0


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
	# action codes: only through the terminal (Ctrl+T, "code <CODE>")
	if not Net.code_result.is_connected(_on_code_result):
		Net.code_result.connect(_on_code_result)
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
	_build_terminal()
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


# ---------------------------------------------------------------------------
# Action codes
# ---------------------------------------------------------------------------
func _redeem(text: String) -> String:
	var r: Array = Game.redeem_code(text)
	var msg := "> " + str(r[1])
	_log.text = msg
	if bool(r[0]):
		code_redeemed.emit()
	return str(r[1])


func _on_code_result(ok: bool, text: String) -> void:
	_log.text = "> " + text
	if _term and _term.visible:
		_term_print(("[OK] " if ok else "[FEHLER] ") + text)
	if ok:
		code_redeemed.emit()


# ---------------------------------------------------------------------------
# Terminal (Ctrl+T)
# ---------------------------------------------------------------------------
const TERM_HOST := "relay.midnight-drift.net"
const FILES := {
	"crew.txt": "CREW – Stand: heute Nacht\n  Kenji .......... Hafen, fährt S13\n  Mara ........... Bergpass, AE86 (verschwunden?)\n  'Ghost' ........ niemand hat ihn je gesehen",
	"nachricht.log": "[02:13] unbekannt: Hafen. Tor 7. Komm allein.\n[02:14] unbekannt: Und bring das Auto mit, das dir nicht gehört.",
	"strecken.db": "kurohana_ridge  harbor_yard  playground  neo_tokyo  utah_desert  gruene_hoelle",
	"todo.md": "- Bremsen entlüften\n- Reifen für Utah besorgen (Sand!)\n- NICHT über den Damm driften",
}


func _build_terminal() -> void:
	_term = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.02, 0.015, 0.97)
	sb.border_color = GREEN
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	_term.add_theme_stylebox_override("panel", sb)
	_term.position = Vector2(70, 50)
	_term.size = Vector2(W - 140, H - 100)
	_term.visible = false
	add_child(_term)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_term.add_child(v)
	var bar := HBoxContainer.new()
	bar.add_child(_label("terminal — ssh %s@%s" % [_user(), TERM_HOST], 16, GREEN))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	bar.add_child(_label("[Strg+T / Esc schließt]", 14, DIM))
	v.add_child(bar)
	v.add_child(_rule())
	_term_out = RichTextLabel.new()
	_term_out.bbcode_enabled = false
	_term_out.scroll_following = true
	_term_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_term_out.add_theme_font_override("normal_font", _mono)
	_term_out.add_theme_font_size_override("normal_font_size", 16)
	_term_out.add_theme_color_override("default_color", GREEN)
	_term_out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_term_out)
	var row := HBoxContainer.new()
	row.add_child(_label("%s@md-net:~$" % _user(), 16, AMBER))
	_term_in = _line_edit("")
	_term_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_term_in.text_submitted.connect(_term_submit)
	_term_in.gui_input.connect(_term_keys)
	row.add_child(_term_in)
	v.add_child(row)


func _user() -> String:
	var n := str(Game.settings.get("player_name", "driver")).strip_edges().to_lower().replace(" ", "_")
	return n if n != "" else "driver"


func terminal_open() -> bool:
	return _term != null and _term.visible


func toggle_terminal() -> void:
	if terminal_open():
		close_terminal()
		return
	_term.visible = true
	_term_out.clear()
	_term_in.editable = false
	_term_queue = [
		[0.0, "$ ssh %s@%s" % [_user(), TERM_HOST]],
		[0.35, "Verbinde mit %s (185.%d.%d.%d) Port 22 …" % [TERM_HOST, randi() % 200 + 20, randi() % 250, randi() % 250]],
		[0.5, "Schlüsselaustausch: curve25519 … ok"],
		[0.35, "Host-Fingerabdruck SHA256:%s bestätigt." % Marshalls.raw_to_base64(Game.VERSION.sha256_buffer()).substr(0, 22)],
		[0.45, "Angemeldet als %s." % _user()],
		[0.25, ""],
		[0.1, "  __  __ ____        _   _ _____ _____"],
		[0.05, " |  \\/  |  _ \\      | \\ | | ____|_   _|"],
		[0.05, " | |\\/| | | | |_____|  \\| |  _|   | |"],
		[0.05, " | |  | | |_| |_____| |\\  | |___  | |"],
		[0.05, " |_|  |_|____/      |_| \\_|_____| |_|   v%s" % Game.VERSION],
		[0.2, ""],
		[0.1, "Willkommen im MD-NET. 'help' zeigt alle Befehle."],
	]
	_term_t = 0.0
	set_process(true)


func close_terminal() -> void:
	if _term:
		_term.visible = false
		_term_queue.clear()
		if _list and _list.get_child_count() > 0:
			(_list.get_child(_sel) as Button).grab_focus.call_deferred()


func _term_print(t: String) -> void:
	_term_out.add_text(t + "\n")


func _term_keys(e: InputEvent) -> void:
	# ↑ / ↓: the last commands again
	if e is InputEventKey and e.pressed and not _term_hist.is_empty():
		var k := (e as InputEventKey).keycode
		if k == KEY_UP or k == KEY_DOWN:
			_term_hist_i = clampi(_term_hist_i + (-1 if k == KEY_UP else 1), 0, _term_hist.size())
			_term_in.text = _term_hist[_term_hist_i] if _term_hist_i < _term_hist.size() else ""
			_term_in.caret_column = _term_in.text.length()
			_term_in.accept_event()


func _term_submit(line: String) -> void:
	_term_in.text = ""
	_term_print("%s@md-net:~$ %s" % [_user(), line])
	var t := line.strip_edges()
	if t == "":
		return
	_term_hist.append(t)
	_term_hist_i = _term_hist.size()
	var parts := t.split(" ", false)
	var cmd := parts[0].to_lower()
	var arg := " ".join(parts.slice(1))
	match cmd:
		"help", "hilfe", "?":
			for h in [
				"Befehle:",
				"  help              diese Liste",
				"  whoami            wer bin ich",
				"  status            Version, Credits, Auto",
				"  garage            deine Autos",
				"  story             die Story-Teile",
				"  ls                Dateien",
				"  cat <datei>       Datei anzeigen",
				"  code <CODE>       Aktionscode einlösen",
				"  ping <host>       Verbindung testen",
				"  date              Datum und Uhrzeit",
				"  echo <text>       Text ausgeben",
				"  clear             Bildschirm leeren",
				"  exit              Verbindung trennen"]:
				_term_print(h)
		"whoami":
			_term_print(_user())
		"status", "sysinfo":
			var car_id := str(Game.settings.get("car", ""))
			var car_name := str(Game.CARS[car_id]["name"]) if Game.CARS.has(car_id) else car_id
			_term_print("MD-OS 2.4 · Midnight Drift v%s" % Game.VERSION)
			_term_print("Credits: %s" % Game.format_points(int(Game.settings.get("credits", 0))))
			_term_print("Auto:    %s" % car_name)
		"garage", "cars":
			for c in Game.settings.get("owned_cars", []):
				if Game.CARS.has(str(c)):
					_term_print("  %-8s %s" % [str(c), str(Game.CARS[str(c)]["name"])])
		"story":
			for p in PARTS:
				_term_print("  [%s] %s" % ["OK" if p["ready"] else "--", str(p["title"])])
		"ls", "dir":
			_term_print("  ".join(FILES.keys()))
		"cat", "type":
			if FILES.has(arg):
				for l in str(FILES[arg]).split("\n"):
					_term_print(l)
			else:
				_term_print("cat: %s: Datei nicht gefunden" % (arg if arg != "" else "?"))
		"code", "redeem":
			if arg == "":
				_term_print("Benutzung: code <CODE>")
			else:
				_term_print("> " + _redeem(arg))
		"ping":
			var host := arg if arg != "" else TERM_HOST
			for k in 4:
				_term_print("64 Bytes von %s: icmp_seq=%d ttl=54 Zeit=%.1f ms" % [host, k + 1, randf_range(9.0, 38.0)])
		"date":
			_term_print(Time.get_datetime_string_from_system(false, true))
		"echo":
			_term_print(arg)
		"clear", "cls":
			_term_out.clear()
		"exit", "logout", "quit":
			_term_print("Verbindung zu %s getrennt." % TERM_HOST)
			close_terminal()
		"sudo":
			_term_print("%s ist nicht in der sudoers-Datei. Dieser Vorfall wird gemeldet." % _user())
		_:
			_term_print("%s: Befehl nicht gefunden – 'help' zeigt alle Befehle." % cmd)


## Ctrl+T opens and closes the terminal (only that way).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_T \
			and (event as InputEventKey).ctrl_pressed:
		toggle_terminal()
		get_viewport().set_input_as_handled()


func _line_edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", _mono)
	e.add_theme_font_size_override("font_size", 16)
	e.add_theme_color_override("font_color", GREEN)
	e.add_theme_color_override("font_placeholder_color", DIM)
	e.add_theme_color_override("caret_color", GREEN)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0.05, 0.03)
	sb.border_color = DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	e.add_theme_stylebox_override("normal", sb)
	var fs := sb.duplicate() as StyleBoxFlat
	fs.border_color = GREEN
	e.add_theme_stylebox_override("focus", fs)
	return e


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
	if not _term_queue.is_empty():
		# the terminal's connection sequence, line by line
		_term_t += delta
		while not _term_queue.is_empty() and _term_t >= float(_term_queue[0][0]):
			_term_t -= float(_term_queue[0][0])
			_term_print(str(_term_queue.pop_front()[1]))
		if _term_queue.is_empty():
			_term_in.editable = true
			_term_in.grab_focus()
	_boot += delta
	modulate.a = clampf(_boot / 0.35, 0.0, 1.0) * (0.75 + 0.25 * float(int(_boot * 30.0) % 3 != 0)) if _boot < 0.5 else 1.0
	if _boot > 0.9 and _log.text.ends_with("…"):
		_log.text = "> %d Story-Teile gefunden. Auswahl mit ↑ ↓, Enter startet." % PARTS.size()
	if _boot > 1.0 and _term_queue.is_empty():
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
