extends Node
## Texture atlas for billboards, banners and traffic signs, drawn once with ordinary Controls in a
## SubViewport (so the text uses the normal UI font) and then copied into a mipmapped ImageTexture
## that is cached for all later worlds. All brands are made up.
##
## Layout (2048 x 2048): 4 billboards 1024x512 (rows 0-1023), 8 banners 1024x128 (rows 1024-1535),
## 16 square signs 256x256 (rows 1536-2047).

const SIZE := 2048

const ADS := ["kurohana_motors", "nitro_x", "takumi_tires", "series"]
const BANNERS := ["drift_zone", "kurohana_motors", "takumi_tires", "nitro_x", "series", "safety", "harbor", "hana_mart"]
const SIGNS := ["chevron_r", "chevron_l", "speed_40", "speed_60", "curve_r", "curve_l", "winding", "stop",
	"direction", "board_100", "board_50", "no_parking", "bus", "no_entry", "parking", "km"]

## Shader for boards: the front face samples the atlas cell given per instance (INSTANCE_CUSTOM = uv
## offset.xy, uv scale.zw), all other faces are painted metal. `glow` lights the print at night.
const BOARD_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 back_color : source_color = vec3(0.45, 0.46, 0.48);
uniform float glow = 0.0;
uniform float roughness_front = 0.45;
uniform bool baked_uv = false;   // banner strips carry atlas UVs in the mesh

varying float front;
varying vec4 cell;

void vertex() {
	front = (baked_uv || NORMAL.z > 0.5) ? 1.0 : 0.0;
	cell = INSTANCE_CUSTOM;
}

void fragment() {
	if (front > 0.5) {
		vec2 uv = baked_uv ? UV : cell.xy + clamp(UV, vec2(0.002), vec2(0.998)) * cell.zw;
		vec3 c = texture(atlas, uv).rgb;
		ALBEDO = c;
		ROUGHNESS = roughness_front;
		EMISSION = c * glow;
	} else {
		ALBEDO = back_color;
		ROUGHNESS = 0.55;
		METALLIC = 0.6;
	}
}
"""

static var texture: Texture2D          # final mipmapped atlas (null until rendered)
static var _materials: Array = []      # ShaderMaterials waiting for / using the atlas
static var _building := false
static var _shader: Shader


## Returns [uv offset, uv scale] of a cell as a Color for INSTANCE_CUSTOM.
static func cell(kind: String, name: String) -> Color:
	var s := 1.0 / SIZE
	match kind:
		"ad":
			var i: int = maxi(ADS.find(name), 0)
			return Color((i % 2) * 1024 * s, (i / 2) * 512 * s, 1024 * s, 512 * s)
		"banner":
			var i: int = maxi(BANNERS.find(name), 0)
			return Color((i % 2) * 1024 * s, (1024 + (i / 2) * 128) * s, 1024 * s, 128 * s)
		_:
			var i: int = maxi(SIGNS.find(name), 0)
			return Color((i % 8) * 256 * s, (1536 + (i / 8) * 256) * s, 256 * s, 256 * s)


## A board material bound to the atlas. The atlas is drawn on first use (by `host`, which must be in the
## scene tree); until it is ready the boards show plain grey.
static func board_material(host: Node, glow := 0.0, baked_uv := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = BOARD_SHADER
	m.shader = _shader
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("baked_uv", baked_uv)
	if texture:
		m.set_shader_parameter("atlas", texture)
	else:
		_materials.append(m)
		ensure_painted(host)
	return m


## Starts drawing the atlas (once) when there are materials waiting for it.
static func ensure_painted(host: Node) -> void:
	if texture or _building or _materials.is_empty() or host == null or not host.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	_building = true
	var painter: Node = load("res://scripts/world/sign_atlas.gd").new()
	painter.name = "SignAtlasPainter"
	host.add_child(painter)


# ---------------------------------------------------------------------------
# Painter (instance): renders the atlas, publishes the texture, frees itself
# ---------------------------------------------------------------------------
var _vp: SubViewport


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = false
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	var root := Control.new()
	root.size = Vector2(SIZE, SIZE)
	_vp.add_child(root)
	_paint(root)
	# show the viewport texture right away, swap in the mipmapped copy once it has been drawn
	for m in _materials:
		(m as ShaderMaterial).set_shader_parameter("atlas", _vp.get_texture())
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = _vp.get_texture().get_image()
	if img and not img.is_empty():
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		texture = ImageTexture.create_from_image(img)
		for m in _materials:
			if is_instance_valid(m):
				(m as ShaderMaterial).set_shader_parameter("atlas", texture)
		_materials.clear()
	_building = false
	queue_free()


static func _font(bold := true, italic := false) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Helvetica", "Liberation Sans", "DejaVu Sans"])
	f.font_weight = 800 if bold else 500
	f.font_italic = italic
	return f


func _rect(parent: Control, r: Rect2, col: Color, radius := 0.0, border := 0.0, border_col := Color.WHITE) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	if border > 0.0:
		sb.set_border_width_all(int(border))
		sb.border_color = border_col
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	parent.add_child(p)
	return p


func _gradient(parent: Control, r: Rect2, top: Color, bottom: Color) -> void:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = r.position
	tr.size = r.size
	parent.add_child(tr)


func _text(parent: Control, r: Rect2, text: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER,
		bold := true, italic := false, outline := 0, outline_col := Color.BLACK) -> void:
	var l := Label.new()
	l.text = text
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font := _font(bold, italic)
	# shrink to fit the cell (the system font's width is only known at runtime)
	while size > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + outline * 2 > r.size.x * 0.95:
		size -= 2
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_col)
	l.clip_text = true
	parent.add_child(l)


func _poly(parent: Control, pts: PackedVector2Array, col: Color, offset := Vector2.ZERO) -> void:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = col
	p.position = offset
	p.antialiased = true
	parent.add_child(p)


func _paint(root: Control) -> void:
	_rect(root, Rect2(0, 0, SIZE, SIZE), Color(0.5, 0.5, 0.5))
	for i in ADS.size():
		_ad(root, Rect2((i % 2) * 1024, (i / 2) * 512, 1024, 512), ADS[i])
	for i in BANNERS.size():
		_banner(root, Rect2((i % 2) * 1024, 1024 + (i / 2) * 128, 1024, 128), BANNERS[i])
	for i in SIGNS.size():
		_sign(root, Rect2((i % 8) * 256, 1536 + (i / 8) * 256, 256, 256), SIGNS[i])


func _ad(root: Control, r: Rect2, kind: String) -> void:
	var o := r.position
	match kind:
		"kurohana_motors":
			_gradient(root, r, Color(0.16, 0.03, 0.25), Color(0.03, 0.0, 0.08))
			_poly(root, PackedVector2Array([Vector2(0, 380), Vector2(1024, 250), Vector2(1024, 290), Vector2(0, 420)]), Color(0.75, 0.2, 1.0), o)
			_poly(root, PackedVector2Array([Vector2(0, 430), Vector2(1024, 300), Vector2(1024, 312), Vector2(0, 442)]), Color(0.3, 0.85, 1.0), o)
			_text(root, Rect2(o + Vector2(40, 40), Vector2(944, 190)), "KUROHANA MOTORS", 112, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT, true, true, 10, Color(0.5, 0.1, 0.8))
			_text(root, Rect2(o + Vector2(44, 220), Vector2(940, 80)), "Tuning & Drift Parts seit 1987", 52, Color(0.85, 0.75, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
			_text(root, Rect2(o + Vector2(560, 400), Vector2(440, 90)), "kurohana-motors.jp", 40, Color(0.7, 0.7, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, false)
		"nitro_x":
			_rect(root, r, Color(0.04, 0.05, 0.04))
			_poly(root, PackedVector2Array([Vector2(760, 20), Vector2(640, 250), Vector2(730, 250), Vector2(620, 490), Vector2(900, 200), Vector2(800, 200), Vector2(920, 20)]), Color(0.55, 1.0, 0.1), o)
			_text(root, Rect2(o + Vector2(40, 60), Vector2(620, 220)), "NITRO-X", 170, Color(0.6, 1.0, 0.15), HORIZONTAL_ALIGNMENT_LEFT, true, true, 8, Color(0.1, 0.3, 0.0))
			_text(root, Rect2(o + Vector2(44, 290), Vector2(620, 80)), "ENERGY DRINK", 64, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)
			_text(root, Rect2(o + Vector2(44, 380), Vector2(620, 80)), "Voller Boost. Null Zucker.", 40, Color(0.75, 0.9, 0.7), HORIZONTAL_ALIGNMENT_LEFT, false, true)
		"takumi_tires":
			_rect(root, r, Color(0.95, 0.45, 0.05))
			_rect(root, Rect2(o + Vector2(0, 330), Vector2(1024, 182)), Color(0.08, 0.08, 0.09))
			_rect(root, Rect2(o + Vector2(700, 40), Vector2(280, 280)), Color(0.08, 0.08, 0.09), 140)
			_rect(root, Rect2(o + Vector2(770, 110), Vector2(140, 140)), Color(0.75, 0.75, 0.78), 70, 14, Color(0.4, 0.4, 0.42))
			_text(root, Rect2(o + Vector2(40, 50), Vector2(660, 170)), "TAKUMI", 150, Color(0.08, 0.08, 0.09), HORIZONTAL_ALIGNMENT_LEFT, true, true)
			_text(root, Rect2(o + Vector2(44, 210), Vector2(660, 100)), "TIRES", 90, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT, true, true)
			_text(root, Rect2(o + Vector2(40, 350), Vector2(944, 140)), "Grip bis zum Limit – und darüber hinaus", 50, Color(0.95, 0.55, 0.1), HORIZONTAL_ALIGNMENT_LEFT)
		"series":
			_rect(root, r, Color(0.02, 0.02, 0.03))
			for k in 16:
				for j in 2:
					if (k + j) % 2 == 0:
						_rect(root, Rect2(o + Vector2(k * 64, 448 + j * 32), Vector2(64, 32)), Color(0.92, 0.92, 0.92))
			_text(root, Rect2(o + Vector2(20, 40), Vector2(984, 160)), "MIDNIGHT DRIFT", 128, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, true, true, 12, Color(0.55, 0.1, 0.9))
			_text(root, Rect2(o + Vector2(20, 200), Vector2(984, 90)), "SERIES 2026", 76, Color(0.9, 0.35, 1.0), HORIZONTAL_ALIGNMENT_CENTER, true, true)
			_text(root, Rect2(o + Vector2(20, 300), Vector2(984, 90)), "Kurohana Ridge · Harbor Drift Yard", 44, Color(0.75, 0.75, 0.85), HORIZONTAL_ALIGNMENT_CENTER, false)


func _banner(root: Control, r: Rect2, kind: String) -> void:
	var o := r.position
	match kind:
		"drift_zone":
			_rect(root, r, Color(0.08, 0.08, 0.1))
			for k in 12:
				_poly(root, PackedVector2Array([Vector2(k * 88, 0), Vector2(k * 88 + 40, 0), Vector2(k * 88 - 20, 128), Vector2(k * 88 - 60, 128)]), Color(0.95, 0.8, 0.05), o)
			_rect(root, Rect2(o + Vector2(200, 14), Vector2(624, 100)), Color(0.08, 0.08, 0.1))
			_text(root, Rect2(o + Vector2(200, 10), Vector2(624, 108)), "DRIFT ZONE", 84, Color(0.95, 0.8, 0.05), HORIZONTAL_ALIGNMENT_CENTER, true, true)
		"kurohana_motors":
			_gradient(root, r, Color(0.2, 0.04, 0.3), Color(0.05, 0.0, 0.1))
			_text(root, Rect2(o + Vector2(20, 0), Vector2(984, 128)), "KUROHANA MOTORS  ·  TUNING & DRIFT PARTS", 64, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, true, true)
		"takumi_tires":
			_rect(root, r, Color(0.95, 0.45, 0.05))
			_text(root, Rect2(o + Vector2(20, 0), Vector2(984, 128)), "TAKUMI TIRES", 92, Color(0.08, 0.08, 0.09), HORIZONTAL_ALIGNMENT_CENTER, true, true)
		"nitro_x":
			_rect(root, r, Color(0.04, 0.05, 0.04))
			_text(root, Rect2(o + Vector2(20, 0), Vector2(984, 128)), "NITRO-X  ENERGY DRINK", 84, Color(0.6, 1.0, 0.15), HORIZONTAL_ALIGNMENT_CENTER, true, true)
		"series":
			_rect(root, r, Color(0.02, 0.02, 0.03))
			_text(root, Rect2(o + Vector2(20, 0), Vector2(984, 128)), "MIDNIGHT DRIFT SERIES 2026", 76, Color(0.9, 0.4, 1.0), HORIZONTAL_ALIGNMENT_CENTER, true, true)
		"safety":
			_rect(root, r, Color(0.95, 0.95, 0.93))
			_rect(root, Rect2(o, Vector2(1024, 14)), Color(0.85, 0.1, 0.1))
			_rect(root, Rect2(o + Vector2(0, 114), Vector2(1024, 14)), Color(0.85, 0.1, 0.1))
			_text(root, Rect2(o + Vector2(20, 0), Vector2(984, 128)), "ZUSCHAUER HINTER DEN ZAUN!", 70, Color(0.1, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
		"harbor":
			_rect(root, r, Color(0.05, 0.2, 0.45))
			_text(root, Rect2(o + Vector2(20, 0), Vector2(984, 128)), "HARBOR LOGISTICS  ·  PORT 7", 72, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
		"hana_mart":
			_rect(root, r, Color(0.97, 0.97, 0.95))
			_rect(root, Rect2(o + Vector2(24, 20), Vector2(88, 88)), Color(0.9, 0.2, 0.45), 44)
			_poly(root, PackedVector2Array([Vector2(68, 34), Vector2(80, 58), Vector2(98, 64), Vector2(80, 70), Vector2(68, 94), Vector2(56, 70), Vector2(38, 64), Vector2(56, 58)]), Color(1, 1, 1), o)
			_text(root, Rect2(o + Vector2(130, 0), Vector2(640, 128)), "HANA MART", 84, Color(0.1, 0.45, 0.25), HORIZONTAL_ALIGNMENT_LEFT, true)
			_text(root, Rect2(o + Vector2(760, 0), Vector2(240, 128)), "24h", 76, Color(0.9, 0.2, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, true)


func _sign(root: Control, r: Rect2, kind: String) -> void:
	var o := r.position
	var c := o + Vector2(128, 128)
	_rect(root, r, Color(0.5, 0.5, 0.52))
	match kind:
		"chevron_r", "chevron_l":
			_rect(root, Rect2(o + Vector2(4, 40), Vector2(248, 176)), Color(0.85, 0.08, 0.06))
			for k in 3:
				var x := 30.0 + k * 70.0
				var pts := PackedVector2Array([Vector2(x, 60), Vector2(x + 40, 60), Vector2(x + 90, 128), Vector2(x + 40, 196), Vector2(x, 196), Vector2(x + 50, 128)])
				if kind == "chevron_l":
					for q in pts.size():
						pts[q].x = 256.0 - pts[q].x
				_poly(root, pts, Color(1, 1, 1), o)
		"speed_40", "speed_60":
			_rect(root, Rect2(o + Vector2(8, 8), Vector2(240, 240)), Color(1, 1, 1), 120, 26, Color(0.85, 0.08, 0.06))
			_text(root, Rect2(o + Vector2(30, 40), Vector2(196, 176)), kind.substr(6), 120, Color(0.1, 0.2, 0.6))
		"curve_r", "curve_l", "winding":
			_poly(root, PackedVector2Array([Vector2(128, 6), Vector2(250, 128), Vector2(128, 250), Vector2(6, 128)]), Color(0.1, 0.1, 0.1), o)
			_poly(root, PackedVector2Array([Vector2(128, 18), Vector2(238, 128), Vector2(128, 238), Vector2(18, 128)]), Color(0.98, 0.8, 0.05), o)
			var pts: PackedVector2Array
			if kind == "winding":
				pts = PackedVector2Array([Vector2(118, 200), Vector2(118, 160), Vector2(150, 130), Vector2(106, 100), Vector2(106, 80), Vector2(90, 80),
					Vector2(122, 44), Vector2(154, 80), Vector2(136, 80), Vector2(136, 92), Vector2(176, 128), Vector2(140, 166), Vector2(140, 200)])
			else:
				pts = PackedVector2Array([Vector2(112, 200), Vector2(112, 120), Vector2(140, 92), Vector2(140, 80), Vector2(122, 80),
					Vector2(160, 44), Vector2(198, 80), Vector2(170, 80), Vector2(170, 104), Vector2(140, 134), Vector2(140, 200)])
			if kind == "curve_l":
				for q in pts.size():
					pts[q].x = 256.0 - pts[q].x
			_poly(root, pts, Color(0.08, 0.08, 0.08), o)
		"stop":
			var oct := PackedVector2Array()
			for k in 8:
				var a := PI / 8.0 + k * PI / 4.0
				oct.append(Vector2(128, 128) + Vector2(cos(a), sin(a)) * 122.0)
			_poly(root, oct, Color(1, 1, 1), o)
			var inner := PackedVector2Array()
			for k in 8:
				var a := PI / 8.0 + k * PI / 4.0
				inner.append(Vector2(128, 128) + Vector2(cos(a), sin(a)) * 110.0)
			_poly(root, inner, Color(0.8, 0.06, 0.05), o)
			_text(root, Rect2(o + Vector2(10, 60), Vector2(236, 136)), "STOP", 76, Color(1, 1, 1))
		"direction":
			_rect(root, Rect2(o + Vector2(4, 30), Vector2(248, 196)), Color(0.05, 0.3, 0.7), 12, 6, Color(1, 1, 1))
			_text(root, Rect2(o + Vector2(16, 44), Vector2(224, 60)), "↑ Kurohana Pass", 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)
			_text(root, Rect2(o + Vector2(16, 100), Vector2(224, 60)), "← Hafen  12 km", 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)
			_text(root, Rect2(o + Vector2(16, 156), Vector2(224, 60)), "→ Onsen  4 km", 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)
		"board_100", "board_50":
			_rect(root, Rect2(o + Vector2(40, 4), Vector2(176, 248)), Color(1, 1, 1), 6, 8, Color(0.1, 0.1, 0.1))
			_text(root, Rect2(o + Vector2(40, 30), Vector2(176, 200)), kind.substr(6), 96, Color(0.1, 0.1, 0.1))
		"no_parking":
			_rect(root, Rect2(o + Vector2(8, 8), Vector2(240, 240)), Color(0.1, 0.3, 0.75), 120, 24, Color(0.85, 0.08, 0.06))
			_poly(root, PackedVector2Array([Vector2(60, 76), Vector2(76, 60), Vector2(196, 180), Vector2(180, 196)]), Color(0.85, 0.08, 0.06), o)
		"bus":
			_rect(root, Rect2(o + Vector2(8, 8), Vector2(240, 240)), Color(1, 1, 1), 120, 16, Color(0.1, 0.4, 0.2))
			_text(root, Rect2(o + Vector2(20, 50), Vector2(216, 90)), "BUS", 80, Color(0.1, 0.4, 0.2))
			_text(root, Rect2(o + Vector2(20, 140), Vector2(216, 60)), "Kurohana", 34, Color(0.15, 0.15, 0.15))
		"no_entry":
			_rect(root, Rect2(o + Vector2(8, 8), Vector2(240, 240)), Color(0.8, 0.06, 0.05), 120)
			_rect(root, Rect2(o + Vector2(40, 106), Vector2(176, 44)), Color(1, 1, 1))
		"parking":
			_rect(root, Rect2(o + Vector2(12, 12), Vector2(232, 232)), Color(0.05, 0.3, 0.7), 16, 8, Color(1, 1, 1))
			_text(root, Rect2(o + Vector2(12, 12), Vector2(232, 232)), "P", 180, Color(1, 1, 1))
		"km":
			_rect(root, Rect2(o + Vector2(60, 4), Vector2(136, 248)), Color(0.95, 0.95, 0.95), 10)
			_rect(root, Rect2(o + Vector2(60, 4), Vector2(136, 40)), Color(0.85, 0.08, 0.06), 10)
			_text(root, Rect2(o + Vector2(60, 70), Vector2(136, 120)), "12", 80, Color(0.1, 0.1, 0.1))
