extends Node
## Draws the sticker shapes once (white on transparent, 256 px) into user://decals/ – basic shapes,
## a tree, a unicorn silhouette, digits and letters. `ensure_all()` draws whatever is missing, a few
## per frame; `progress` goes 0 → 1.

const Livery = preload("res://scripts/car/livery.gd")
const SIZE := 256

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
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_pen = Painter.new()
	_vp.add_child(_pen)
	for i in todo.size():
		_pen.kind = todo[i]
		_pen.queue_redraw()
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


## Draws one shape into the 256 px square.
class Painter extends Node2D:
	var kind := ""
	var _font: SystemFont

	func _draw() -> void:
		var w := Color.WHITE
		var c := Vector2(128, 128)
		match kind:
			"circle":
				draw_circle(c, 118, w)
			"ring":
				draw_arc(c, 98, 0, TAU, 96, w, 36.0, true)
			"square":
				draw_rect(Rect2(14, 14, 228, 228), w)
			"frame":
				draw_rect(Rect2(26, 26, 204, 204), w, false, 34.0)
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
			"burst":
				_star(12, 124, 82)
			"heart":
				draw_circle(Vector2(78, 92), 62, w)
				draw_circle(Vector2(178, 92), 62, w)
				_poly([Vector2(20, 112), Vector2(236, 112), Vector2(128, 240)])
			"cross":
				draw_rect(Rect2(96, 12, 64, 232), w)
				draw_rect(Rect2(12, 96, 232, 64), w)
			"arrow":
				_poly([Vector2(12, 96), Vector2(150, 96), Vector2(150, 30), Vector2(246, 128), Vector2(150, 226), Vector2(150, 160), Vector2(12, 160)])
			"chevron":
				_poly([Vector2(20, 40), Vector2(96, 40), Vector2(200, 128), Vector2(96, 216), Vector2(20, 216), Vector2(124, 128)])
			"stripe":
				draw_rect(Rect2(0, 100, 256, 56), w)
			"stripes2":
				draw_rect(Rect2(0, 70, 256, 44), w)
				draw_rect(Rect2(0, 142, 256, 44), w)
			"bolt":
				_poly([Vector2(150, 6), Vector2(54, 140), Vector2(118, 140), Vector2(92, 250), Vector2(204, 104), Vector2(136, 104)])
			"flame":
				_poly([Vector2(128, 250), Vector2(62, 222), Vector2(40, 160), Vector2(64, 98), Vector2(86, 132), Vector2(96, 64),
					Vector2(128, 8), Vector2(142, 76), Vector2(166, 44), Vector2(196, 110), Vector2(216, 168), Vector2(194, 226)])
			"moon":
				_crescent()
			"checker":
				for y in 4:
					for x in 4:
						if (x + y) % 2 == 0:
							draw_rect(Rect2(x * 64, y * 64, 64, 64), w)
			"tree":
				draw_rect(Rect2(110, 150, 36, 100), w)
				_poly([Vector2(146, 200), Vector2(184, 176), Vector2(146, 186)])
				for cc in [[128, 76, 62], [76, 112, 50], [182, 112, 50], [100, 150, 46], [160, 150, 46], [128, 118, 56]]:
					draw_circle(Vector2(cc[0], cc[1]), cc[2], w)
			"unicorn":
				_unicorn()
			_:
				if kind.begins_with("ch_"):
					if _font == null:
						_font = SystemFont.new()
						_font.font_names = PackedStringArray(["Arial Black", "Impact", "DejaVu Sans", "Liberation Sans", "sans-serif"])
						_font.font_weight = 900
					var t := kind.trim_prefix("ch_")
					var fs := 230
					var sz := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
					var asc := _font.get_ascent(fs)
					var desc := _font.get_descent(fs)
					draw_string(_font, Vector2(128 - sz.x * 0.5, 128 + (asc - desc) * 0.5 - 10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, w)

	func _poly(pts: Array) -> void:
		draw_colored_polygon(PackedVector2Array(pts), Color.WHITE)

	func _ngon(n: int, r: float, a0: float) -> void:
		var pts: Array = []
		for k in n:
			var a := a0 + TAU * k / n
			pts.append(Vector2(128, 128) + Vector2(cos(a), sin(a)) * r)
		_poly(pts)

	func _star(n: int, r0: float, r1: float) -> void:
		var pts: Array = []
		for k in n * 2:
			var a := -PI * 0.5 + PI * k / n
			pts.append(Vector2(128, 132) + Vector2(cos(a), sin(a)) * (r0 if k % 2 == 0 else r1))
		_poly(pts)

	func _crescent() -> void:
		# the outer arc round the left, back up along a smaller inner arc
		var pts: Array = []
		for k in 49:
			var a := -PI * 0.5 - PI * k / 48.0
			pts.append(Vector2(128, 128) + Vector2(cos(a), sin(a)) * 116)
		for k in 49:
			var a := PI * 0.5 + PI * k / 48.0
			pts.append(Vector2(176, 128) + Vector2(cos(a) * 74, sin(a) * 116))
		_poly(pts)

	## A unicorn standing, facing right: one flat silhouette.
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
