extends Control
## A driver's profile picture: one of the standard pictures, drawn (helmets in four colours, a
## steering wheel, a tyre, a chequered flag, a lightning bolt) on a round badge.

const COUNT := 8
const NAMES := ["Helm Lila", "Helm Rot", "Helm Blau", "Helm Gold", "Lenkrad", "Reifen", "Zielflagge", "Blitz"]
const BG := [Color(0.22, 0.1, 0.38), Color(0.32, 0.07, 0.08), Color(0.06, 0.13, 0.32), Color(0.3, 0.22, 0.05),
	Color(0.12, 0.12, 0.14), Color(0.16, 0.16, 0.18), Color(0.1, 0.1, 0.12), Color(0.18, 0.08, 0.32)]
const HELMET := [Color(0.62, 0.32, 1.0), Color(0.9, 0.15, 0.12), Color(0.15, 0.45, 1.0), Color(1.0, 0.78, 0.2)]

@export var idx := 0:
	set(v):
		idx = posmod(v, COUNT)
		queue_redraw()
var ring := Color(0.62, 0.32, 1.0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := o + Vector2(s, s) * 0.5
	draw_circle(c, s * 0.5, BG[idx])
	var at := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var pts := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in arr:
			out.append(at.call(q[0], q[1]))
		return out
	if idx < 4:
		# a racing helmet from the side, visor to the right
		var col: Color = HELMET[idx]
		draw_colored_polygon(pts.call([[0.2, 0.64], [0.18, 0.46], [0.24, 0.31], [0.36, 0.21], [0.52, 0.18], [0.68, 0.23],
			[0.79, 0.34], [0.84, 0.49], [0.84, 0.63], [0.78, 0.74], [0.55, 0.78], [0.3, 0.76]]), col)
		draw_line(at.call(0.24, 0.56), at.call(0.5, 0.21), col.lightened(0.55), s * 0.05, true)
		draw_colored_polygon(pts.call([[0.54, 0.37], [0.83, 0.37], [0.85, 0.55], [0.57, 0.56]]), Color(0.05, 0.05, 0.08))
		draw_line(at.call(0.58, 0.41), at.call(0.8, 0.41), Color(1, 1, 1, 0.35), s * 0.02, true)
		draw_colored_polygon(pts.call([[0.3, 0.76], [0.55, 0.78], [0.52, 0.84], [0.32, 0.83]]), col.darkened(0.45))
	else:
		match idx:
			4:      # steering wheel
				var w := Color(0.9, 0.9, 0.92)
				draw_arc(c, s * 0.29, 0.0, TAU, 40, w, s * 0.07, true)
				for a in [PI, 0.0, PI * 0.5]:
					draw_line(c, c + Vector2.from_angle(a) * s * 0.27, w, s * 0.06, true)
				draw_circle(c, s * 0.09, Color(0.62, 0.32, 1.0))
				draw_line(at.call(0.5, 0.21), at.call(0.5, 0.27), Color(1.0, 0.3, 0.2), s * 0.05)
			5:      # tyre and rim
				draw_circle(c, s * 0.33, Color(0.05, 0.05, 0.06))
				for k in 24:
					var a := TAU * k / 24.0
					draw_line(c + Vector2.from_angle(a) * s * 0.29, c + Vector2.from_angle(a) * s * 0.33, Color(0.2, 0.2, 0.22), s * 0.025)
				draw_circle(c, s * 0.19, Color(0.75, 0.76, 0.8))
				for k in 5:
					var a := TAU * k / 5.0 - PI * 0.5
					draw_line(c, c + Vector2.from_angle(a) * s * 0.17, Color(0.35, 0.35, 0.4), s * 0.045, true)
				draw_circle(c, s * 0.05, Color(0.62, 0.32, 1.0))
			6:      # chequered flag
				draw_line(at.call(0.28, 0.2), at.call(0.28, 0.82), Color(0.8, 0.8, 0.82), s * 0.04)
				var cols := 4
				var rows := 3
				for iy in rows:
					for ix in cols:
						var x0 := 0.3 + ix * 0.11
						var y0 := 0.22 + iy * 0.1 + 0.03 * sin(ix * 1.3)
						var y1 := y0 + 0.1
						var black := (ix + iy) % 2 == 0
						draw_colored_polygon(pts.call([[x0, y0], [x0 + 0.11, y0 + 0.03 * (sin((ix + 1) * 1.3) - sin(ix * 1.3))],
							[x0 + 0.11, y1 + 0.03 * (sin((ix + 1) * 1.3) - sin(ix * 1.3))], [x0, y1]]),
							Color(0.05, 0.05, 0.06) if black else Color(0.95, 0.95, 0.95))
			_:      # lightning bolt
				draw_colored_polygon(pts.call([[0.56, 0.16], [0.3, 0.54], [0.47, 0.54], [0.4, 0.86], [0.7, 0.44], [0.53, 0.44], [0.64, 0.16]]),
					Color(1.0, 0.85, 0.25))
	draw_arc(c, s * 0.5 - 1.0, 0.0, TAU, 48, ring, 2.0, true)
