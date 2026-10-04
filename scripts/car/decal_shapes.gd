extends Node
## Draws the sticker shapes once (white on transparent) into user://decals_v2/ – basic shapes,
## emblems, racing marks, digits and letters in three styles. Everything is drawn as clean vector
## shapes at 512 px with 8x multisampling (smooth edges); holes (eyes, rings, cut-outs) are punched
## out by an eraser layer drawn over the shape. `ensure_all()` draws whatever is missing, a few per
## frame; `progress` goes 0 → 1.

const Livery = preload("res://scripts/car/livery.gd")
const SIZE := 512

signal done
var progress := 1.0
var _vp: SubViewport
var _pen: Painter


func ensure_all() -> void:
	var todo: Array = []
	for s in Livery.shapes():
		var id: String = s[0]
		if not id.begins_with("graffiti_") and Livery.texture(id) == null:
			todo.append(id)
	if todo.is_empty():
		progress = 1.0
		done.emit()
		return
	progress = 0.0
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.msaa_2d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_pen = Painter.new()
	_pen.scale = Vector2.ONE * (SIZE / 256.0)
	_vp.add_child(_pen)
	for i in todo.size():
		_pen.set_kind(todo[i])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		if img:
			img.convert(Image.FORMAT_RGBA8)
			Livery.remember(todo[i], img)
		progress = float(i + 1) / todo.size()
	_vp.queue_free()
	_vp = null
	done.emit()


## Punches the holes of the current shape out (writes transparent, no blending).
class Eraser extends Node2D:
	var pen: Painter

	func _draw() -> void:
		if pen:
			pen.holes(self)


## Draws one shape into a 256 x 256 square (scaled up to the viewport).
class Painter extends Node2D:
	var kind := ""
	var _font: SystemFont
	var _eraser: Eraser
	const W := Color.WHITE
	const C := Vector2(128, 128)
	const CLEAR := Color(0, 0, 0, 0)

	func _init() -> void:
		_eraser = Eraser.new()
		_eraser.pen = self
		# (no blending: whatever it draws replaces the pixels – transparent punches a hole)
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = "shader_type canvas_item;\nrender_mode blend_disabled;\nvoid fragment() { COLOR = COLOR; }\n"
		_eraser.material = m
		add_child(_eraser)

	func set_kind(k: String) -> void:
		kind = k
		queue_redraw()
		_eraser.queue_redraw()

	func _draw() -> void:
		match kind:
			"circle":
				draw_circle(C, 118, W)
			"ring":
				draw_circle(C, 116, W)
			"square":
				draw_rect(Rect2(14, 14, 228, 228), W)
			"frame":
				draw_rect(Rect2(10, 10, 236, 236), W)
			"triangle":
				_poly([Vector2(128, 14), Vector2(244, 230), Vector2(12, 230)])
			"diamond":
				_poly([Vector2(128, 8), Vector2(236, 128), Vector2(128, 248), Vector2(20, 128)])
			"pentagon":
				_ngon(5, 120, -PI * 0.5)
			"hexagon":
				_ngon(6, 120, 0.0)
			"star":
				_star(5, 122, 50)
			"star_outline":
				_star(5, 122, 50)
			"star4":
				_star(4, 124, 30, Vector2(128, 128))
			"compass":
				_star(8, 124, 22, Vector2(128, 128), [1.0, 0.55])
			"burst":
				_star(12, 124, 82)
			"sun_ring":
				_star(16, 124, 96, Vector2(128, 128))
			"heart":
				_heart(1.0)
			"cross":
				draw_rect(Rect2(96, 12, 64, 232), W)
				draw_rect(Rect2(12, 96, 232, 64), W)
			"iron_cross":
				_iron_cross()
			"arrow":
				_poly([Vector2(12, 96), Vector2(150, 96), Vector2(150, 30), Vector2(246, 128), Vector2(150, 226), Vector2(150, 160), Vector2(12, 160)])
			"arrow_outline":
				_poly([Vector2(12, 96), Vector2(150, 96), Vector2(150, 30), Vector2(246, 128), Vector2(150, 226), Vector2(150, 160), Vector2(12, 160)])
			"chevron":
				_chevron(20, 1.0)
			"chevron2":
				for k in 2:
					_chevron(10 + k * 92, 0.72)
			"chevron3":
				for k in 3:
					_chevron(6 + k * 70, 0.55)
			"stripe":
				draw_rect(Rect2(0, 100, 256, 56), W)
			"stripes2":
				draw_rect(Rect2(0, 70, 256, 44), W)
				draw_rect(Rect2(0, 142, 256, 44), W)
			"slash3":
				for k in 3:
					var x := 40.0 + k * 62.0
					_poly([Vector2(x + 40, 30), Vector2(x + 80, 30), Vector2(x, 226), Vector2(x - 40, 226)])
			"speed":
				for k in 4:
					var y := 64.0 + k * 38.0
					var l := 230.0 - k * 46.0
					_poly([Vector2(246 - l, y + 10), Vector2(246, y), Vector2(246, y + 22), Vector2(246 - l, y + 22)])
			"bolt":
				_poly([Vector2(150, 6), Vector2(54, 140), Vector2(118, 140), Vector2(92, 250), Vector2(204, 104), Vector2(136, 104)])
			"lightning":
				_lightning()
			"flame":
				_poly([Vector2(128, 250), Vector2(62, 222), Vector2(40, 160), Vector2(64, 98), Vector2(86, 132), Vector2(96, 64),
					Vector2(128, 8), Vector2(142, 76), Vector2(166, 44), Vector2(196, 110), Vector2(216, 168), Vector2(194, 226)])
			"flames_side":
				_side_flames()
			"moon":
				_crescent()
			"checker":
				for y in 4:
					for x in 4:
						if (x + y) % 2 == 0:
							draw_rect(Rect2(x * 64, y * 64, 64, 64), W)
			"checker_strip":
				for y in 2:
					for x in 8:
						if (x + y) % 2 == 0:
							draw_rect(Rect2(x * 32, 96 + y * 32, 32, 32), W)
			"flag":
				_flag(Vector2(56, 242), 0.0, 1.15)
			"flags_crossed":
				# the poles cross, each flag flies outwards
				_flag(Vector2(150, 246), -0.42, 0.95, true)
				_flag(Vector2(106, 246), 0.42, 0.95)
			"tree":
				draw_rect(Rect2(110, 150, 36, 100), W)
				_poly([Vector2(146, 200), Vector2(184, 176), Vector2(146, 186)])
				for cc in [[128, 76, 62], [76, 112, 50], [182, 112, 50], [100, 150, 46], [160, 150, 46], [128, 118, 56]]:
					draw_circle(Vector2(cc[0], cc[1]), cc[2], W)
			"unicorn":
				_unicorn()
			"skull":
				_skull()
			"crown":
				_crown()
			"wing":
				_wing(Vector2(70, 150), 1.0, 1.0)
			"wings":
				_wing(Vector2(118, 140), -1.0, 0.62)
				_wing(Vector2(138, 140), 1.0, 0.62)
			"wings_badge":
				_wing(Vector2(96, 132), -1.0, 0.5)
				_wing(Vector2(160, 132), 1.0, 0.5)
				draw_circle(Vector2(128, 132), 44, W)
			"laurel":
				_laurel(-1.0)
				_laurel(1.0)
			"trophy":
				_trophy()
			"crosshair":
				draw_circle(C, 96, W)
				for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					var a: Vector2 = C + d * 70.0
					var b: Vector2 = C + d * 124.0
					var side := Vector2(-d.y, d.x) * 9.0
					_poly([a - side, a + side, b + side, b - side])
			"target":
				draw_circle(C, 120, W)
			"gear":
				_gear()
			"wrenches":
				_wrench(-PI * 0.25)
				_wrench(PI * 0.25)
			"spade":
				_heart(-1.0)
				_poly([Vector2(128, 150), Vector2(170, 236), Vector2(86, 236)])
			"club":
				for cc in [[128, 70], [80, 140], [176, 140]]:
					draw_circle(Vector2(cc[0], cc[1]), 52, W)
				_poly([Vector2(128, 120), Vector2(170, 238), Vector2(86, 238)])
			"shield":
				_shield(1.0)
			"shield_frame":
				_shield(1.0)
			"plate_para":
				_poly([Vector2(50, 50), Vector2(246, 50), Vector2(206, 206), Vector2(10, 206)])
			"plate_round":
				_round_rect(Rect2(10, 48, 236, 160), 36)
			"plate_oval":
				_ellipse(C, 122, 84)
			"plate_circle":
				draw_circle(C, 120, W)
			"plate_diamond":
				_poly([Vector2(128, 6), Vector2(250, 128), Vector2(128, 250), Vector2(6, 128)])
			"splat":
				_splat()
			"drips":
				_drips()
			"claws":
				for k in 3:
					_tapered([Vector2(70 + k * 50, 20), Vector2(60 + k * 50, 120), Vector2(40 + k * 50, 236)], 16, 0.0)
			"swoosh":
				_swoosh()
			"comet":
				_star(5, 56, 24, Vector2(190, 70))
				for k in 3:
					var o := Vector2(0, (k - 1) * 30.0)
					_tapered([Vector2(150, 92) + o * 0.5, Vector2(80, 150) + o, Vector2(12, 206) + o * 1.2], 12.0 - k * 2.0, 0.0)
			"mountains":
				_poly([Vector2(10, 220), Vector2(100, 60), Vector2(160, 160), Vector2(190, 110), Vector2(246, 220)])
			"tribal":
				_tribal()
			"biohazard":
				_biohazard()
			"sparkles":
				_star(4, 92, 16, Vector2(110, 120))
				_star(4, 44, 8, Vector2(200, 60))
				_star(4, 34, 7, Vector2(196, 196))
			_:
				_text_shape()

	## The holes of the current shape, drawn by the eraser (`ci`) in transparent.
	func holes(ci: CanvasItem) -> void:
		var O := CLEAR
		match kind:
			"ring":
				ci.draw_circle(C, 80, O)
			"frame":
				ci.draw_rect(Rect2(44, 44, 168, 168), O)
			"star_outline":
				_star_on(ci, 5, 88, 36, Vector2(128, 132), O)
			"arrow_outline":
				ci.draw_colored_polygon(PackedVector2Array([Vector2(36, 118), Vector2(170, 118), Vector2(170, 82), Vector2(212, 128), Vector2(170, 174), Vector2(170, 138), Vector2(36, 138)]), O)
			"sun_ring":
				ci.draw_circle(C, 74, O)
			"crosshair":
				ci.draw_circle(C, 76, O)
				ci.draw_circle(C, 14, W)
			"target":
				ci.draw_circle(C, 94, O)
				ci.draw_circle(C, 68, W)
				ci.draw_circle(C, 42, O)
				ci.draw_circle(C, 18, W)
			"gear":
				ci.draw_circle(C, 40, O)
			"skull":
				for sx in [-1.0, 1.0]:
					var e := Vector2(128 + sx * 38, 110)
					ci.draw_colored_polygon(PackedVector2Array([e + Vector2(-sx * 30, -16), e + Vector2(sx * 26, -6), e + Vector2(sx * 18, 20), e + Vector2(-sx * 22, 16)]), O)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(128, 140), Vector2(140, 166), Vector2(116, 166)]), O)
				for k in 4:
					ci.draw_rect(Rect2(100 + k * 18, 196, 4, 40), O)
			"shield_frame":
				_shield_on(ci, 0.78, O)
			"plate_para":
				ci.draw_colored_polygon(PackedVector2Array([Vector2(66, 66), Vector2(226, 66), Vector2(194, 190), Vector2(34, 190)]), O)
			"plate_round":
				_round_rect_on(ci, Rect2(28, 66, 200, 124), 24, O)
			"plate_oval":
				_ellipse_on(ci, C, 102, 66, O)
			"plate_circle":
				ci.draw_circle(C, 100, O)
			"plate_diamond":
				ci.draw_colored_polygon(PackedVector2Array([Vector2(128, 32), Vector2(224, 128), Vector2(128, 224), Vector2(32, 128)]), O)
			"wrenches":
				for a in [-PI * 0.25, PI * 0.25]:
					for e in [-1.0, 1.0]:
						var d := Vector2(sin(a), -cos(a))
						var head: Vector2 = C + d * 92.0 * e
						var side := Vector2(-d.y, d.x)
						ci.draw_colored_polygon(PackedVector2Array([head - side * 11 + d * 0.0, head + side * 11, head + side * 11 + d * 40.0 * e, head - side * 11 + d * 40.0 * e]), O)
			"wings_badge":
				ci.draw_circle(Vector2(128, 132), 32, O)
				_star_on(ci, 5, 28, 12, Vector2(128, 134), W)
			"biohazard":
				ci.draw_circle(C, 22, O)
				for k in 3:
					var a := -PI * 0.5 + TAU * k / 3.0
					ci.draw_circle(C + Vector2(cos(a), sin(a)) * 64.0, 34, O)

	# --- shape helpers ----------------------------------------------------------------------------
	func _poly(pts: Array) -> void:
		draw_colored_polygon(PackedVector2Array(pts), W)

	func _ngon(n: int, r: float, a0: float) -> void:
		var pts: Array = []
		for k in n:
			var a := a0 + TAU * k / n
			pts.append(C + Vector2(cos(a), sin(a)) * r)
		_poly(pts)

	func _star(n: int, r0: float, r1: float, c := Vector2(128, 132), lens: Array = [1.0]) -> void:
		_star_on(self, n, r0, r1, c, W, lens)

	func _star_on(ci: CanvasItem, n: int, r0: float, r1: float, c: Vector2, col: Color, lens: Array = [1.0]) -> void:
		var pts := PackedVector2Array()
		for k in n * 2:
			var a := -PI * 0.5 + PI * k / n
			var r := r1
			if k % 2 == 0:
				r = r0 * float(lens[(k / 2) % lens.size()])
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		ci.draw_colored_polygon(pts, col)

	func _ellipse(c: Vector2, rx: float, ry: float) -> void:
		_ellipse_on(self, c, rx, ry, W)

	func _ellipse_on(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for k in 64:
			var a := TAU * k / 64.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		ci.draw_colored_polygon(pts, col)

	func _round_rect(r: Rect2, rad: float) -> void:
		_round_rect_on(self, r, rad, W)

	func _round_rect_on(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
		var pts := PackedVector2Array()
		var corners := [[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
			[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5]]
		for cn in corners:
			for k in 9:
				var a: float = float(cn[1]) + PI * 0.5 * k / 8.0
				pts.append((cn[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
		ci.draw_colored_polygon(pts, col)

	## A stroke along points, `w0` wide at the start tapering to `w1` (a pointed end with 0).
	func _tapered(pts: Array, w0: float, w1: float) -> void:
		var dense: Array = _curve(pts, 12)
		var left: Array = []
		var right: Array = []
		for k in dense.size():
			var a: Vector2 = dense[maxi(k - 1, 0)]
			var b: Vector2 = dense[mini(k + 1, dense.size() - 1)]
			var n := (b - a).normalized()
			n = Vector2(-n.y, n.x)
			var w := lerpf(w0, w1, float(k) / (dense.size() - 1)) * 0.5
			left.append(dense[k] + n * w)
			right.append(dense[k] - n * w)
		right.reverse()
		_poly(left + right)

	## Points along a smooth (Catmull-Rom) curve through `ctrl`.
	func _curve(ctrl: Array, per := 10) -> Array:
		var out: Array = []
		for k in ctrl.size() - 1:
			var p0: Vector2 = ctrl[maxi(k - 1, 0)]
			var p1: Vector2 = ctrl[k]
			var p2: Vector2 = ctrl[k + 1]
			var p3: Vector2 = ctrl[mini(k + 2, ctrl.size() - 1)]
			for j in per:
				var t := float(j) / per
				out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
		out.append(ctrl[ctrl.size() - 1])
		return out

	func _heart(dir: float) -> void:
		# dir 1: the point down (heart), -1: the point up (spade's leaf)
		var y0 := 92.0 if dir > 0 else 150.0
		draw_circle(Vector2(78, y0), 60, W)
		draw_circle(Vector2(178, y0), 60, W)
		if dir > 0:
			_poly([Vector2(22, 116), Vector2(234, 116), Vector2(128, 242)])
		else:
			_poly([Vector2(22, 126), Vector2(234, 126), Vector2(128, 10)])

	func _chevron(x: float, s: float) -> void:
		var pts: Array = []
		for p in [Vector2(0, 40), Vector2(76, 40), Vector2(180, 128), Vector2(76, 216), Vector2(0, 216), Vector2(104, 128)]:
			pts.append(Vector2(x + p.x * s, 128 + (p.y - 128) * maxf(s, 0.75)))
		_poly(pts)

	func _crescent() -> void:
		var pts: Array = []
		for k in 49:
			var a := -PI * 0.5 - PI * k / 48.0
			pts.append(C + Vector2(cos(a), sin(a)) * 116)
		for k in 49:
			var a := PI * 0.5 + PI * k / 48.0
			pts.append(Vector2(176, 128) + Vector2(cos(a) * 74, sin(a) * 116))
		_poly(pts)

	func _iron_cross() -> void:
		for k in 4:
			var b := Transform2D(PI * 0.5 * k, C)
			_poly([b * Vector2(-22, -20), b * Vector2(22, -20), b * Vector2(48, -118), b * Vector2(-48, -118)])
		draw_rect(Rect2(98, 98, 60, 60), W)

	func _lightning() -> void:
		_tapered([Vector2(150, 8), Vector2(110, 90), Vector2(146, 112), Vector2(96, 248)], 22, 0.0)
		_tapered([Vector2(110, 90), Vector2(60, 140), Vector2(40, 200)], 12, 0.0)
		_tapered([Vector2(146, 112), Vector2(200, 150), Vector2(214, 210)], 12, 0.0)

	func _side_flames() -> void:
		for k in 4:
			var y := 70.0 + k * 34.0
			var l := 236.0 - absf(k - 1.5) * 50.0
			_tapered([Vector2(14, 128 + (y - 128) * 0.25), Vector2(14 + l * 0.5, y - 10), Vector2(14 + l, y + 6)], 34.0 - absf(k - 1.5) * 8.0, 0.0)

	## A chequered flag on its pole, waving: base at the pole's foot, turned by `rot`.
	func _flag(foot: Vector2, rot: float, s: float, mirror := false) -> void:
		var xf := Transform2D(rot, foot) * Transform2D(0.0, Vector2(-s if mirror else s, s), 0.0, Vector2.ZERO)
		var pole := [Vector2(-5, 0), Vector2(5, 0), Vector2(5, -200), Vector2(-5, -200)]
		_poly(pole.map(func(p): return xf * p))
		var nx := 6
		var ny := 4
		var cw := 26.0
		var chh := 22.0
		for iy in ny:
			for ix in nx:
				if (ix + iy) % 2 != 0:
					continue
				var q: Array = []
				for c in [Vector2(ix, iy), Vector2(ix + 1, iy), Vector2(ix + 1, iy + 1), Vector2(ix, iy + 1)]:
					var px: float = 5.0 + c.x * cw
					var py: float = -196.0 + c.y * chh + sin(c.x * 0.9) * 10.0
					q.append(xf * Vector2(px, py))
				_poly(q)
		# the flag's outline (the white cells' edges)
		for side in [[Vector2(0, 0), Vector2(nx, 0)], [Vector2(0, ny), Vector2(nx, ny)]]:
			var pts := PackedVector2Array()
			for k in nx * 4 + 1:
				var c: Vector2 = (side[0] as Vector2).lerp(side[1], float(k) / (nx * 4))
				pts.append(xf * Vector2(5.0 + c.x * cw, -196.0 + c.y * chh + sin(c.x * 0.9) * 10.0))
			draw_polyline(pts, W, 3.0, true)

	func _skull() -> void:
		draw_circle(Vector2(128, 104), 96, W)
		_poly([Vector2(64, 150), Vector2(192, 150), Vector2(178, 240), Vector2(78, 240)])

	func _crown() -> void:
		_poly([Vector2(20, 200), Vector2(20, 80), Vector2(72, 140), Vector2(128, 50), Vector2(184, 140), Vector2(236, 80), Vector2(236, 200)])
		draw_rect(Rect2(20, 208, 216, 30), W)
		for p in [Vector2(20, 72), Vector2(128, 42), Vector2(236, 72)]:
			draw_circle(p, 16, W)

	## A wing spreading from `root` towards `dir` (1 right, -1 left): a curved arm along the top and a
	## row of feathers hanging from it, longer towards the tip.
	func _wing(root: Vector2, dir: float, s: float) -> void:
		var arm: Array = [root, root + Vector2(dir * 70, -50) * s, root + Vector2(dir * 150, -78) * s, root + Vector2(dir * 210, -60) * s]
		var line: Array = _curve(arm, 10)
		_tapered(arm, 44.0 * s, 16.0 * s)
		# the feathers: broad, overlapping, sweeping out and down, the outer ones longest
		for k in 9:
			var t := 0.05 + 0.95 * float(k) / 8.0
			var base: Vector2 = line[int(t * (line.size() - 1))]
			var l := (70.0 + 110.0 * t) * s
			var tip := base + Vector2(dir * (0.25 + 1.1 * t), 1.0).normalized() * l
			var bend := base.lerp(tip, 0.55) + Vector2(-dir * 10, 0) * s
			_tapered([base, bend, tip], 44.0 * s, 6.0 * s)

	func _laurel(side: float) -> void:
		for k in 9:
			var t := float(k) / 8.0
			var a := lerpf(PI * 0.6, PI * 1.45, t)
			var p := C + Vector2(cos(a) * -side, sin(a)) * 100.0 + Vector2(0, 10)
			var tan := Vector2(-sin(a) * -side, cos(a))
			var out := (p - C).normalized()
			var leaf: Array = []
			for j in 13:
				var u := float(j) / 12.0 * TAU
				leaf.append(p + (tan * cos(u) * 18.0 + out * sin(u) * 8.0).rotated(0.5 * side))
			_poly(leaf)
		_tapered([C + Vector2(-side * 30, 116), C + Vector2(-side * 104, 10), C + Vector2(-side * 60, -96)], 8, 4)

	func _trophy() -> void:
		var cup := PackedVector2Array()
		for k in 25:
			var a := PI * k / 24.0
			cup.append(Vector2(128 - cos(a) * 70, 40 + sin(a) * 100))
		cup.append(Vector2(58, 40))
		draw_colored_polygon(cup, W)
		draw_rect(Rect2(48, 30, 160, 16), W)
		for sx in [-1.0, 1.0]:
			draw_arc(Vector2(128 + sx * 72, 80), 30, -PI * 0.5 if sx > 0 else PI * 0.5, PI * 0.5 if sx > 0 else PI * 1.5, 24, W, 12.0, true)
		draw_rect(Rect2(116, 138, 24, 50), W)
		_poly([Vector2(84, 188), Vector2(172, 188), Vector2(186, 236), Vector2(70, 236)])

	func _gear() -> void:
		var pts := PackedVector2Array()
		var teeth := 10
		for k in teeth * 4:
			var a := TAU * k / (teeth * 4.0)
			var r := 116.0 if (k % 4 == 1 or k % 4 == 2) else 90.0
			pts.append(C + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, W)

	func _wrench(a: float) -> void:
		var d := Vector2(sin(a), -cos(a))
		var side := Vector2(-d.y, d.x)
		_poly([C - d * 80 - side * 12, C - d * 80 + side * 12, C + d * 80 + side * 12, C + d * 80 - side * 12])
		for e in [-1.0, 1.0]:
			draw_circle(C + d * 96.0 * e, 32, W)

	func _shield(s: float) -> void:
		_shield_on(self, s, W)

	func _shield_on(ci: CanvasItem, s: float, col: Color) -> void:
		var pts := PackedVector2Array()
		var top := 18.0
		pts.append(C + (Vector2(-110, top - 128)) * s)
		pts.append(C + (Vector2(0, top - 140)) * s)
		pts.append(C + (Vector2(110, top - 128)) * s)
		# straight sides first, curving in to the point at the bottom
		for k in 25:
			var t := float(k) / 24.0
			pts.append(C + Vector2(110.0 * (1.0 - pow(t, 2.4)), lerpf(top - 128 + 4, 120, t)) * s)
		for k in range(23, -1, -1):
			var t := float(k) / 24.0
			pts.append(C + Vector2(-110.0 * (1.0 - pow(t, 2.4)), lerpf(top - 128 + 4, 120, t)) * s)
		ci.draw_colored_polygon(pts, col)

	func _splat() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var pts: Array = []
		for k in 32:
			var a := TAU * k / 32.0
			var r := 70.0 + rng.randf_range(-8, 8) + (26.0 if k % 4 == 0 else 0.0)
			pts.append(C + Vector2(cos(a), sin(a)) * r)
		_poly(pts)
		for k in 9:
			var a := rng.randf() * TAU
			var r := rng.randf_range(96, 118)
			draw_circle(C + Vector2(cos(a), sin(a)) * r, rng.randf_range(5, 13), W)

	func _drips() -> void:
		draw_rect(Rect2(0, 20, 256, 54), W)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var x := 14.0
		while x < 246.0:
			var l := rng.randf_range(40, 170)
			var w := rng.randf_range(12, 24)
			draw_rect(Rect2(x - w * 0.5, 60, w, l), W)
			draw_circle(Vector2(x, 60 + l), w * 0.62, W)
			x += rng.randf_range(26, 44)

	func _swoosh() -> void:
		_tapered([Vector2(12, 196), Vector2(80, 196), Vector2(170, 150), Vector2(246, 52)], 56, 0.0)

	func _tribal() -> void:
		# two curling blades, back to back
		_tapered([Vector2(128, 236), Vector2(110, 160), Vector2(150, 90), Vector2(210, 70), Vector2(236, 20)], 46, 0.0)
		_tapered([Vector2(116, 200), Vector2(70, 150), Vector2(40, 90), Vector2(66, 36)], 34, 0.0)
		_tapered([Vector2(150, 150), Vector2(196, 168), Vector2(230, 214)], 24, 0.0)

	func _biohazard() -> void:
		for k in 3:
			var a := -PI * 0.5 + TAU * k / 3.0
			draw_circle(C + Vector2(cos(a), sin(a)) * 46.0, 56, W)
		draw_arc(C, 70, 0, TAU, 64, W, 14.0, true)

	func _unicorn() -> void:
		var p := [[22, 112], [30, 92], [44, 84], [60, 80], [118, 80], [150, 76], [160, 60], [166, 42],
			[160, 30], [172, 34], [178, 26], [188, 22], [198, 6], [196, 26], [206, 30], [232, 54], [234, 66],
			[222, 70], [204, 62], [194, 68], [184, 92], [178, 108], [178, 136], [182, 196], [190, 214],
			[176, 214], [168, 150], [160, 140], [156, 196], [162, 214], [148, 214], [142, 148], [120, 132],
			[84, 132], [74, 150], [80, 196], [88, 214], [74, 214], [62, 158], [56, 148], [52, 196], [58, 214],
			[44, 214], [40, 150], [42, 120], [34, 140], [18, 168], [8, 160], [14, 132]]
		var pts: Array = []
		for q in p:
			pts.append(Vector2(q[0], q[1] + 18))
		_poly(pts)

	## Digits and letters: "ch_X" heavy upright, "chi_X" racing italic, "cho_X" outline.
	func _text_shape() -> void:
		var t := ""
		var style := ""
		for pre in ["chi_", "cho_", "ch_"]:
			if kind.begins_with(pre):
				t = kind.trim_prefix(pre)
				style = pre
				break
		if t == "":
			return
		if _font == null:
			_font = SystemFont.new()
			_font.font_names = PackedStringArray(["Arial Black", "Impact", "DejaVu Sans", "Liberation Sans", "sans-serif"])
			_font.font_weight = 900
		var fs := 220
		var sz := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var asc := _font.get_ascent(fs)
		var desc := _font.get_descent(fs)
		var pos := Vector2(-sz.x * 0.5, (asc - desc) * 0.5 - 8)
		if style == "chi_":
			# leaning forward like a racing number
			draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, -0.32, C))
			draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, W)
		elif style == "cho_":
			draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE * 0.92, -0.2, C))
			draw_string_outline(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, W)
		else:
			draw_set_transform_matrix(Transform2D(0.0, C))
			draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, W)
		draw_set_transform_matrix(Transform2D.IDENTITY)
