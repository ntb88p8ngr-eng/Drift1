extends CanvasLayer
## Loading screen while a world builds (in slices, see Game.load_tick): track name, a rev counter
## whose needle blips up to the limiter and drops back like an engine on the throttle, and a thin
## progress bar with the current step.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

var track_name := ""
var sub_text := ""
var title_only := false     # the start of the game: just the name and the percentage

var _draw_node: Control
var _t := 0.0
var _shown := 0.0          # displayed progress (eases towards Game.load_progress)


func _ready() -> void:
	layer = 50
	_draw_node = Control.new()
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_node.draw.connect(_on_draw)
	add_child(_draw_node)


func _process(delta: float) -> void:
	_t += delta
	_shown = lerpf(_shown, Game.load_progress, 1.0 - exp(-delta * 6.0))
	_draw_node.queue_redraw()


## Fades out and frees itself.
func finish() -> void:
	_shown = 1.0
	var tw := create_tween()
	tw.tween_property(_draw_node, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)


## Needle position 0..1: throttle blip to the limiter (with a little bounce), then back to idle.
func _rev(t: float) -> float:
	var p := fmod(t, 2.2)
	if p < 0.55:
		return lerpf(0.12, 0.93, 1.0 - pow(1.0 - p / 0.55, 2.2))
	if p < 0.95:
		# on the limiter: quick flutter
		return 0.93 + 0.025 * sin((p - 0.55) * 60.0) * (1.0 - (p - 0.55) / 0.4)
	return lerpf(0.93, 0.12, 1.0 - exp(-(p - 0.95) * 4.0))


func _on_draw() -> void:
	var c := _draw_node
	var size := c.size
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.01, 0.04))
	# a soft purple glow behind the gauge
	var mid := Vector2(size.x * 0.5, size.y * 0.47)
	for k in 6:
		var r := 260.0 - k * 38.0
		c.draw_circle(mid, r, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.012 + k * 0.004))
	var font := UiKit.title_font()
	var body := ThemeDB.fallback_font
	if title_only:
		var pct := "%d %%" % int(round(clampf(_shown, 0.0, 1.0) * 100.0))
		_text(font, "MIDNIGHT DRIFT", Vector2(mid.x, mid.y + 10.0), 84, UiKit.TEXT)
		_text(body, pct, Vector2(mid.x, mid.y + 70.0), 26, UiKit.TEXT_DIM)
		return
	_text(body, "MIDNIGHT DRIFT", Vector2(mid.x, mid.y - 210.0), 18, UiKit.TEXT_DIM)
	_text(font, track_name, Vector2(mid.x, mid.y - 160.0), 52, UiKit.TEXT)
	_text(body, sub_text, Vector2(mid.x, mid.y - 122.0), 17, UiKit.TEXT_DIM)

	# rev counter: 240° dial, red zone at the top end
	var rad := 78.0
	var a0 := deg_to_rad(150.0)
	var a1 := deg_to_rad(390.0)
	var centre := mid + Vector2(0, 10)
	c.draw_arc(centre, rad, a0, a1, 64, Color(1, 1, 1, 0.12), 3.0, true)
	c.draw_arc(centre, rad, lerpf(a0, a1, 0.82), a1, 16, Color(UiKit.BAD.r, UiKit.BAD.g, UiKit.BAD.b, 0.8), 3.0, true)
	for i in 10:
		var a := lerpf(a0, a1, i / 9.0)
		var dir := Vector2(cos(a), sin(a))
		var long := i % 3 == 0
		c.draw_line(centre + dir * (rad - (12.0 if long else 7.0)), centre + dir * (rad - 2.0), Color(1, 1, 1, 0.45 if long else 0.22), 2.0, true)
	var v := _rev(_t)
	var an := lerpf(a0, a1, v)
	# lit sweep behind the needle
	c.draw_arc(centre, rad + 7.0, a0, an, 48, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.85), 4.0, true)
	c.draw_arc(centre, rad + 7.0, a0, an, 48, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.18), 12.0, true)
	var nd := Vector2(cos(an), sin(an))
	var needle := UiKit.BAD if v > 0.82 else Color(1.0, 0.45, 0.3)
	c.draw_line(centre - nd * 10.0, centre + nd * (rad - 6.0), needle, 3.0, true)
	c.draw_circle(centre, 6.0, Color(0.12, 0.1, 0.16))
	c.draw_arc(centre, 6.0, 0.0, TAU, 16, needle, 2.0, true)
	_text(body, "x1000 U/min", centre + Vector2(0, 34.0), 12, Color(1, 1, 1, 0.35))

	# progress bar + step
	var bw := 380.0
	var bar := Rect2(mid.x - bw * 0.5, mid.y + 128.0, bw, 4.0)
	c.draw_rect(bar, Color(1, 1, 1, 0.1))
	var fill := Rect2(bar.position, Vector2(bw * clampf(_shown, 0.0, 1.0), bar.size.y))
	c.draw_rect(fill.grow(3.0), Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.15))
	c.draw_rect(fill, UiKit.ACCENT)
	var dots := ".".repeat(1 + int(_t * 2.5) % 3)
	c.draw_string(body, Vector2(bar.position.x, bar.position.y + 26.0), Game.t(Game.load_stage if Game.load_stage != "" else "Lade") + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.TEXT_DIM)
	c.draw_string(body, Vector2(bar.position.x, bar.position.y + 26.0), "%d %%" % int(round(clampf(_shown, 0.0, 1.0) * 100.0)), HORIZONTAL_ALIGNMENT_RIGHT, bw, 15, UiKit.TEXT_DIM)


func _text(font: Font, text: String, pos: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_draw_node.draw_string(font, Vector2(pos.x - w * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
