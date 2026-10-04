extends Control
## The car radio's display (Radio OS), drawn like the original's orange LCD: 14-segment characters with
## the unlit segments faintly visible, the small A.P.I. / T.INFO / SEEK / LOUD / ST / DX indicators,
## band and station (or frequency), song titles scrolling through, the clock, the volume, a tape's reels.
## Lives in a SubViewport; its texture goes on the radio model's display.

const W := 800
const H := 160
const ORANGE := Color(1.0, 0.36, 0.06)
const GHOST := Color(1.0, 0.36, 0.06, 0.045)
const CHARS := 12

## segments: a top, b/c right upper/lower, d bottom, e/f left lower/upper, g/G middle left/right,
## h/i/j diagonal-centre-diagonal up, l/m/n diagonal-centre-diagonal down
const FONT := {
	"0": "abcdefjl", "1": "bcj", "2": "abgGde", "3": "abcdG", "4": "fgGbc", "5": "afgGcd", "6": "afgGcde",
	"7": "abc", "8": "abcdefgG", "9": "abcdfgG",
	"A": "abcefgG", "B": "abcdiGm", "C": "adef", "D": "abcdim", "E": "adefg", "F": "aefg", "G": "acdefG",
	"H": "bcefgG", "I": "adim", "J": "bcde", "K": "efgjn", "L": "def", "M": "bcefhj", "N": "bcefhn",
	"O": "abcdef", "P": "abefgG", "Q": "abcdefn", "R": "abefgGn", "S": "afgGcd", "T": "aim", "U": "bcdef",
	"V": "efjl", "W": "bcefln", "X": "hjln", "Y": "hjm", "Z": "ajld", "-": "gG", "/": "jl", "'": "i",
	"+": "gGim", "*": "hijlmn", "_": "d", "<": "jn", ">": "hl", "=": "gGd", "?": "abGm", "!": "bc",
	"(": "jn", ")": "hl", "&": "ahjmlde",
}
const ALL := "abcdefgGhijlmn"

var _t := 0.0
var _scroll_from := -100.0       # when the song title started scrolling
var _last_title := ""
var _clock_until := -1.0


func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	Radio.title_changed.connect(func(): _scroll_from = _t)


func show_clock() -> void:
	_clock_until = _t + 4.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## The 12 characters of the main line, and whether the tape's reels show.
func _main_text() -> String:
	if not Radio.on:
		return ""
	if Radio.flash_left() > 0.0:
		return Radio.flash_text
	if _t < _clock_until:
		return "    " + Time.get_time_string_from_system().left(5)
	if Radio.mode == "tape":
		var head := "TAPE"
		var tail := ""
		if Radio.status == "TUNING":
			tail = " LOAD"
		elif Radio.tape_paused:
			tail = " PAUSE"
		else:
			tail = " " + _scrolled(Radio.tape_title(), 8, true)
		return head + tail
	var band := "FM%d" % (Radio.band + 1)
	var st := Radio.station()
	if Radio.status == "NO SIGNAL":
		return band + " NO SIGNL"
	if Radio.status == "TUNING":
		return band + " " + ("SEEK" if fmod(_t, 0.8) < 0.5 else "")
	if Radio.show_freq:
		return band + "    " + str(st.get("freq", ""))
	return band + " " + _scrolled(str(st.get("ps", "")), 8, Radio.api)


## A text in `width` characters: when it is longer, it scrolls by every 14 s, else the station shows.
func _scrolled(fallback: String, width: int, allow: bool) -> String:
	var title := Radio.title.to_upper()
	if allow and title != "":
		var steps := title.length() + width
		var run := _t - _scroll_from
		if run > steps * 0.28 + 16.0:
			_scroll_from = _t        # again after a while
			run = 0.0
		var k := int(run / 0.28)
		if k < steps:
			var padded := " ".repeat(width) + title + " ".repeat(width)
			return padded.substr(k, width)
	return fallback.to_upper().left(width)


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.015, 0.008, 0.005))
	var on := Radio.on
	# the small indicators on the left (as printed on the original)
	_tag("A.P.I.", Vector2(14, 56), on and Radio.api)
	_tag("T.INFO", Vector2(14, 82), on and Radio.title != "")
	_tag("SEEK", Vector2(14, 134), on and Radio.status == "TUNING")
	_tag("LOUD", Vector2(86, 134), on and Radio.volume > 0.75)
	_tag("ST", Vector2(470, 134), on and Radio.status == "PLAY")
	_tag("DX", Vector2(590, 134), on and Radio.mode == "radio")
	# the main line: 12 characters of 14 segments
	var text := _main_text().to_upper()
	text = text.left(CHARS)
	var x0 := 140.0
	var cw := 46.0
	for i in CHARS:
		var ch := text[i] if i < text.length() else " "
		_char(ch, Vector2(x0 + i * cw, 24), 33.0, 78.0, on)
	# the volume: a bar of 15 steps along the bottom while the flash says VOL
	if on and Radio.flash_left() > 0.0 and Radio.flash_text.begins_with("VOL"):
		for k in 15:
			var lit := float(k) < Radio.volume * 15.0
			draw_rect(Rect2(150 + k * 20, 116, 14, 8), ORANGE if lit else GHOST)
	# a tape: its two reels turning
	if on and Radio.mode == "tape" and Radio.tape != "":
		var spin := 0.0 if Radio.tape_paused else _t * 5.0
		for cx in [690.0, 760.0]:
			_reel(Vector2(cx, 60), 22.0, spin)
	elif on and Radio.mode == "radio":
		# the preset number, small, top right
		_tag("P%d" % (int(Radio.preset[Radio.band]) + 1), Vector2(752, 30), true)


func _tag(text: String, pos: Vector2, lit: bool) -> void:
	var f := get_theme_default_font()
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ORANGE if lit else GHOST)


func _reel(c: Vector2, r: float, a: float) -> void:
	draw_arc(c, r, 0, TAU, 28, ORANGE, 3.0, true)
	draw_arc(c, r * 0.35, 0, TAU, 16, ORANGE, 2.0, true)
	for k in 3:
		var d := Vector2.from_angle(a + TAU * k / 3.0)
		draw_line(c + d * r * 0.35, c + d * r * 0.85, ORANGE, 3.0, true)


## One 14-segment character in the box at `p` (w x h), slanted a little like the original's digits.
func _char(ch: String, p: Vector2, w: float, h: float, on: bool) -> void:
	var segs: String = FONT.get(ch, "") if on else ""
	if ch == "." or ch == ":":
		segs = ""
	for s in ALL:
		var lit := segs.contains(s)
		_seg(s, p, w, h, ORANGE if lit else GHOST)
	if on and (ch == "." or ch == ":"):
		draw_circle(p + Vector2(w * 0.5, h - 3), 3.5, ORANGE)
		if ch == ":":
			draw_circle(p + Vector2(w * 0.5 + 4, h * 0.35), 3.5, ORANGE)


func _pt(p: Vector2, w: float, h: float, u: float, v: float) -> Vector2:
	# u, v in 0..1 of the cell; slanted: the top leans right
	return p + Vector2(u * w + (1.0 - v) * h * 0.12, v * h)


func _seg(s: String, p: Vector2, w: float, h: float, col: Color) -> void:
	var g := 0.08         # the gap at each segment's ends
	var a: Vector2
	var b: Vector2
	match s:
		"a": a = _pt(p, w, h, g, 0); b = _pt(p, w, h, 1 - g, 0)
		"d": a = _pt(p, w, h, g, 1); b = _pt(p, w, h, 1 - g, 1)
		"b": a = _pt(p, w, h, 1, g * 0.6); b = _pt(p, w, h, 1, 0.5 - g * 0.6)
		"c": a = _pt(p, w, h, 1, 0.5 + g * 0.6); b = _pt(p, w, h, 1, 1 - g * 0.6)
		"f": a = _pt(p, w, h, 0, g * 0.6); b = _pt(p, w, h, 0, 0.5 - g * 0.6)
		"e": a = _pt(p, w, h, 0, 0.5 + g * 0.6); b = _pt(p, w, h, 0, 1 - g * 0.6)
		"g": a = _pt(p, w, h, g, 0.5); b = _pt(p, w, h, 0.5 - g * 0.5, 0.5)
		"G": a = _pt(p, w, h, 0.5 + g * 0.5, 0.5); b = _pt(p, w, h, 1 - g, 0.5)
		"i": a = _pt(p, w, h, 0.5, g * 0.8); b = _pt(p, w, h, 0.5, 0.5 - g * 0.6)
		"m": a = _pt(p, w, h, 0.5, 0.5 + g * 0.6); b = _pt(p, w, h, 0.5, 1 - g * 0.8)
		"h": a = _pt(p, w, h, 0.14, 0.1); b = _pt(p, w, h, 0.42, 0.42)
		"j": a = _pt(p, w, h, 0.86, 0.1); b = _pt(p, w, h, 0.58, 0.42)
		"l": a = _pt(p, w, h, 0.42, 0.58); b = _pt(p, w, h, 0.14, 0.9)
		"n": a = _pt(p, w, h, 0.58, 0.58); b = _pt(p, w, h, 0.86, 0.9)
		_: return
	draw_line(a, b, col, 5.0, true)
