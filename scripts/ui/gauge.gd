extends Control
## Tachometer with speed, gear, transmission mode and turbo boost.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

var car   # car.gd


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if car == null or not is_instance_valid(car):
		return
	var font := ThemeDB.fallback_font
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	var redline: float = car.redline
	# scale like the real car's rev counter (R34: 9, Mustang: 8, M3 GT3: 10), extended when tuned past it
	var max_rpm := float(Game.get_car(str(car.car_id)).get("tach", ceilf(redline / 1000.0) * 1000.0 + 1000.0))
	if redline > max_rpm - 250.0:
		max_rpm = ceilf((redline + 250.0) / 1000.0) * 1000.0
	var start := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	draw_circle(c, r + 10.0, Color(0.02, 0.015, 0.04, 0.72))
	draw_arc(c, r + 10.0, 0.0, TAU, 64, Color(0.45, 0.22, 0.8, 0.8), 2.0, true)
	draw_arc(c, r - 4.0, start, start + sweep, 72, Color(1, 1, 1, 0.12), 8.0, true)
	var red_a := start + sweep * (redline / max_rpm)
	draw_arc(c, r - 4.0, red_a, start + sweep, 24, Color(1.0, 0.15, 0.1, 0.85), 8.0, true)
	var rpm: float = car.rpm
	var a := start + sweep * clampf(rpm / max_rpm, 0.0, 1.0)
	var fill_col := UiKit.ACCENT.lerp(Color(1.0, 0.25, 0.15), clampf((rpm - redline * 0.8) / (redline * 0.2), 0.0, 1.0))
	draw_arc(c, r - 16.0, start, a, 64, fill_col, 10.0, true)
	var k := 0
	while k * 1000.0 <= max_rpm:
		var ta := start + sweep * (k * 1000.0 / max_rpm)
		var dir := Vector2(cos(ta), sin(ta))
		draw_line(c + dir * (r - 30.0), c + dir * (r - 8.0), Color(1, 1, 1, 0.8), 2.0, true)
		var tp := c + dir * (r - 46.0) + Vector2(-6, 7)
		draw_string(font, tp, str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.35, 0.3) if k * 1000.0 >= redline else Color(1, 1, 1, 0.8))
		# half-thousand marks
		if (k + 0.5) * 1000.0 <= max_rpm:
			var ha := start + sweep * ((k + 0.5) * 1000.0 / max_rpm)
			var hd := Vector2(cos(ha), sin(ha))
			draw_line(c + hd * (r - 20.0), c + hd * (r - 8.0), Color(1, 1, 1, 0.45), 1.5, true)
		k += 1
	draw_string(font, c + Vector2(-r, -r * 0.64), "x1000 U/min", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 11, Color(1, 1, 1, 0.45))
	var nd := Vector2(cos(a), sin(a))
	draw_line(c - nd * 12.0, c + nd * (r - 12.0), Color(1.0, 0.3, 0.2), 4.0, true)
	draw_circle(c, 9.0, Color(0.15, 0.1, 0.2))
	# speed
	var kmh := int(round(float(car.speed) * 3.6))
	var units := "km/h"
	if not bool(Game.settings.get("units_kmh", true)):
		kmh = int(round(float(car.speed) * 2.237))
		units = "mph"
	draw_string(font, c + Vector2(-r, r * 0.42), str(kmh), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 46, Color.WHITE)
	draw_string(font, c + Vector2(-r, r * 0.6), units, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, Color(1, 1, 1, 0.6))
	# gear
	var g: int = car.gear
	var gtxt := "N" if g == 0 else ("R" if g < 0 else str(g))
	draw_string(font, c + Vector2(-r, -r * 0.08), gtxt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 50, UiKit.GOLD if float(car.shift_timer) > 0.0 else Color.WHITE)
	var trans := "AUTO" if car.transmission == "auto" else "MANUELL"
	draw_string(font, c + Vector2(-r, r * 0.13), trans, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 14, UiKit.ACCENT.lightened(0.3))
	# nitro bar
	var nw := r * 1.1
	var np := c + Vector2(-nw * 0.5, r * 0.93)
	draw_rect(Rect2(np, Vector2(nw, 7)), Color(1, 1, 1, 0.15))
	var ncol := Color(0.3, 0.55, 1.0) if not bool(car.nitro_active) else Color(0.6, 0.9, 1.0)
	draw_rect(Rect2(np, Vector2(nw * clampf(float(car.nitro), 0.0, 1.0), 7)), ncol)
	draw_string(font, np + Vector2(0, 19), "NITRO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	if bool(car.line_lock) or (bool(car.controls_locked) and float(car.throttle) > 0.4):
		draw_string(font, c + Vector2(-r, -r * 0.42), "LAUNCH", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 16, UiKit.GOLD)
	# boost bar
	if float(car.turbo_gain) > 0.0:
		var bw := r * 1.1
		var bp := c + Vector2(-bw * 0.5, r * 0.78)
		draw_rect(Rect2(bp, Vector2(bw, 7)), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(bp, Vector2(bw * clampf(float(car.boost), 0.0, 1.0), 7)), Color(0.3, 0.8, 1.0))
		draw_string(font, bp + Vector2(0, -4), "BOOST", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
