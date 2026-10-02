extends Node
## Neo Tokyo's signs and ads in one 2048² texture, drawn once at load time with real fonts (Japanese
## where the system has a font for it, else the romaji): 16 billboard ads, 32 vertical blade signs,
## 64 shop signs and a few misc cells (noren cloth, "P", the iApfel logo). Every sign in the city is a
## 3D board whose front face has its UVs in one cell (city_mesh.gd); the material glows at night.

const SIZE := 2048
const SIGN_SHADER := """
shader_type spatial;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float glow = 0.25;
varying float lit;

void vertex() {
	lit = COLOR.r;
}

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * 0.8;
	EMISSION = t.rgb * glow * lit;
	ROUGHNESS = 0.32;
	METALLIC = 0.0;
}
"""

const BLADES := [["ラーメン", "RAMEN"], ["寿司", "SUSHI"], ["居酒屋", "IZAKAYA"], ["カラオケ", "KARAOKE"],
	["薬", "DRUG"], ["珈琲", "COFFEE"], ["焼肉", "BBQ"], ["本屋", "BOOKS"], ["酒場", "BAR"], ["歯科", "DENTAL"],
	["美容室", "SALON"], ["パチンコ", "PACHINKO"], ["ゲーム", "GAMES"], ["不動産", "ESTATE"], ["中華", "CHINA"],
	["うどん", "UDON"], ["喫茶", "CAFE"], ["焼鳥", "YAKITORI"], ["銀行", "BANK"], ["漫画", "MANGA"], ["古着", "VINTAGE"],
	["整体", "MASSAGE"], ["英会話", "ENGLISH"], ["ホテル", "HOTEL"], ["天ぷら", "TEMPURA"], ["そば", "SOBA"],
	["カフェ", "CAFE"], ["占い", "FORTUNE"], ["麻雀", "MAHJONG"], ["質屋", "PAWN"], ["眼鏡", "GLASSES"], ["花屋", "FLOWERS"]]
## Shop signs: the first ones are fixed (named places), the rest generic shop fronts.
const SHOPS := [["MEGA COFFEE  珈琲", "MEGA COFFEE"], ["DONUT DREAM", "DONUT DREAM"], ["ラーメン 一番", "RAMEN ICHIBAN"],
	["寿司 さくら", "SUSHI SAKURA"], ["居酒屋 とりや", "IZAKAYA TORIYA"], ["24h MART", "24h MART"], ["iApfel", "iApfel"],
	["スーパー 大正屋", "TAISHOYA MARKET"], ["P 駐車場", "P PARKING"], ["BOWLING", "BOWLING"], ["交番", "KOBAN"],
	["警視庁", "POLICE"], ["GAS 給油", "GAS"], ["カラオケ館", "KARAOKE"], ["PACHINKO 大当", "PACHINKO"],
	["本 BOOKS", "BOOKS"], ["薬局 PHARMACY", "PHARMACY"], ["パン BAKERY", "BAKERY"], ["花 FLOWERS", "FLOWERS"],
	["焼肉 炎", "YAKINIKU"], ["うどん 丸", "UDON MARU"], ["CAFÉ 喫茶", "KISSATEN"], ["ゲームセンター", "GAME CENTER"],
	["メガネ", "OPTICIAN"], ["美容室 HAIR", "HAIR SALON"], ["ホテル 月", "HOTEL TSUKI"], ["銀行 BANK", "SAKURA BANK"],
	["100円 SHOP", "100 YEN SHOP"], ["寿司 回転", "KAITEN SUSHI"], ["天丼 てん", "TENDON"], ["DRUGSTORE", "DRUGSTORE"],
	["洋服 FASHION", "FASHION"], ["電気 ELECTRONICS", "ELECTRONICS"], ["靴 SHOES", "SHOES"], ["時計 WATCH", "WATCHES"],
	["酒 LIQUOR", "LIQUOR"], ["魚屋", "FISH MARKET"], ["八百屋", "GREENGROCER"], ["ネットカフェ", "NET CAFE"],
	["歯科 DENTAL", "DENTAL"], ["整骨院", "CLINIC"], ["不動産", "REAL ESTATE"], ["文具", "STATIONERY"],
	["おもちゃ TOYS", "TOYS"], ["ペット PETS", "PETS"], ["写真 PHOTO", "PHOTO"], ["中華 龍", "DRAGON CHINA"],
	["カレー", "CURRY HOUSE"], ["そば 更科", "SOBA"], ["牛丼", "GYUDON"], ["バー BAR", "BAR"], ["ジム GYM", "GYM"],
	["古本", "USED BOOKS"], ["家具", "FURNITURE"], ["自転車", "BICYCLES"], ["携帯 MOBILE", "MOBILE"], ["茶 TEA", "TEA HOUSE"],
	["餃子", "GYOZA"], ["たこ焼き", "TAKOYAKI"], ["クリーニング", "CLEANERS"], ["郵便局", "POST OFFICE"], ["病院", "HOSPITAL"],
	["映画館 CINEMA", "CINEMA"], ["通行止め", "ROAD CLOSED"]]
const ADS := [["iApfel", "Phone 17 Pro", "Das neue iApfel. Jetzt da."], ["NEO COLA", "ネオコーラ", "Ice cold. Neon fresh."],
	["RAMEN ICHIBAN", "ラーメン一番", "Since 1978"], ["DONUT DREAM", "ドーナツ", "12 for 1000 Yen"],
	["KUROHANA MOTORS", "THE NEW KR-9", "Built for the night"], ["TAKUMI TIRES", "GRIP. CONTROL.", "Drift ready"],
	["SAKURA BANK", "さくら銀行", "Your future blooms"], ["MEGA COFFEE", "珈琲", "Wake up, Tokyo"],
	["NITRO X", "ENERGY DRINK", "Boost your night"], ["TOKYO AIR", "東京航空", "Fly beyond"],
	["POCKET ARCADE", "ゲーム", "Play everywhere"], ["MIDNIGHT DRIFT", "LIVE TONIGHT", "Neo Tokyo street series"],
	["SUSHI GO", "回転寿司", "Fresh every minute"], ["NEON BEER", "ビール", "Taste the lights"],
	["KAIJU 2", "怪獣", "In cinemas now"], ["TAISHOYA", "スーパー", "Fresh. Cheap. Open late."]]
const AD_COLS := [Color(0.95, 0.95, 0.96), Color(0.85, 0.05, 0.1), Color(0.95, 0.75, 0.1), Color(1.0, 0.55, 0.75),
	Color(0.08, 0.08, 0.1), Color(0.95, 0.45, 0.05), Color(1.0, 0.7, 0.8), Color(0.35, 0.2, 0.12), Color(0.2, 0.9, 0.3),
	Color(0.1, 0.3, 0.75), Color(0.6, 0.2, 0.9), Color(0.55, 0.2, 0.95), Color(0.1, 0.55, 0.7), Color(1.0, 0.85, 0.2),
	Color(0.15, 0.6, 0.2), Color(0.9, 0.2, 0.15)]
const SIGN_COLS := [[Color(0.85, 0.08, 0.08), Color(1, 1, 1)], [Color(1, 1, 1), Color(0.1, 0.1, 0.15)],
	[Color(0.95, 0.8, 0.1), Color(0.15, 0.1, 0.05)], [Color(0.08, 0.2, 0.6), Color(1, 1, 1)],
	[Color(0.05, 0.05, 0.06), Color(1.0, 0.85, 0.3)], [Color(0.1, 0.55, 0.3), Color(1, 1, 1)],
	[Color(0.95, 0.4, 0.6), Color(1, 1, 1)], [Color(0.95, 0.5, 0.05), Color(1, 1, 1)],
	[Color(0.45, 0.15, 0.6), Color(1, 0.95, 0.6)], [Color(0.05, 0.05, 0.06), Color(0.3, 0.9, 1.0)]]

static var texture: Texture2D
static var _materials: Array = []
static var _building := false
static var _cjk := -1


## The sign material (shared). Until the atlas is drawn it shows a plain grey.
static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SIGN_SHADER
	m.shader = sh
	if texture:
		m.set_shader_parameter("atlas", texture)
	else:
		_materials.append(m)
	return m


static func ensure_painted(host: Node) -> void:
	if texture or _building or host == null or not host.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	_building = true
	var painter: Node = load("res://scripts/world/city/city_atlas.gd").new()
	painter.name = "CityAtlasPainter"
	host.add_child(painter)


# --- cells (UV rectangles in 0..1) -------------------------------------------------------------
static func ad(i: int) -> Rect2:
	i = posmod(i, 16)
	return Rect2((i % 4) * 512.0 / SIZE, (i / 4) * 256.0 / SIZE, 512.0 / SIZE, 256.0 / SIZE)


static func blade(i: int) -> Rect2:
	i = posmod(i, BLADES.size())
	return Rect2(i * 64.0 / SIZE, 1024.0 / SIZE, 64.0 / SIZE, 320.0 / SIZE)


static func shop(i: int) -> Rect2:
	i = posmod(i, 64)
	return Rect2((i % 8) * 256.0 / SIZE, (1344.0 + (i / 8) * 64.0) / SIZE, 256.0 / SIZE, 64.0 / SIZE)


## misc: 0 black, 1 white, 2-5 noren cloths, 6 big "P", 7 iApfel logo, 8 menu board, 9 police star,
## 10 phone screen, 11 vending front
static func misc(i: int) -> Rect2:
	return Rect2((i % 16) * 128.0 / SIZE, 1856.0 / SIZE, 128.0 / SIZE, 192.0 / SIZE)


# --- painter --------------------------------------------------------------------------------------
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


static func _jp_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Yu Gothic", "Yu Gothic UI", "Meiryo", "MS Gothic", "Noto Sans CJK JP", "Noto Sans JP",
		"Source Han Sans JP", "Hiragino Sans", "IPAGothic", "IPAexGothic", "TakaoGothic", "WenQuanYi Zen Hei"])
	f.font_weight = 800
	return f


static func _latin_font(weight := 800) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Helvetica", "Liberation Sans", "DejaVu Sans"])
	f.font_weight = weight
	return f


## Japanese text when the system can draw it (else the romaji fallback).
static func jp(pair: Array) -> String:
	if _cjk < 0:
		_cjk = 1 if _jp_font().has_char(0x30E9) and _jp_font().has_char(0x5BFF) else 0
	return str(pair[0]) if _cjk == 1 else str(pair[1])


static func _label(root: Control, rect: Rect2, text: String, size: int, col: Color, font: Font, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.position = rect.position
	l.size = rect.size
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	root.add_child(l)
	return l


static func _box(root: Control, rect: Rect2, col: Color, radius := 0, border := 0, border_col := Color.BLACK) -> void:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_col
	p.add_theme_stylebox_override("panel", sb)
	root.add_child(p)


func _paint(root: Control) -> void:
	var jpf := _jp_font()
	var lat := _latin_font()
	var thin := _latin_font(500)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.size = Vector2(SIZE, SIZE)
	root.add_child(bg)
	# ads: brand, a second line, a slogan and a product shape
	for i in 16:
		var o := Vector2((i % 4) * 512, (i / 4) * 256)
		var a: Array = ADS[i]
		var c: Color = AD_COLS[i]
		var dark := c.get_luminance() > 0.6
		var fg := Color(0.08, 0.08, 0.1) if dark else Color(1, 1, 1)
		_box(root, Rect2(o + Vector2(4, 4), Vector2(504, 248)), c)
		_box(root, Rect2(o + Vector2(4, 196), Vector2(504, 56)), c.darkened(0.35))
		_label(root, Rect2(o + Vector2(24, 20), Vector2(300, 80)), str(a[0]), 52 if str(a[0]).length() < 12 else 38, fg, lat, HORIZONTAL_ALIGNMENT_LEFT)
		_label(root, Rect2(o + Vector2(24, 100), Vector2(300, 70)), str(a[1]), 40, fg.lerp(c, 0.2), jpf if jp(["あ", "a"]) == "あ" else lat, HORIZONTAL_ALIGNMENT_LEFT)
		_label(root, Rect2(o + Vector2(24, 200), Vector2(470, 48)), str(a[2]), 28, Color(1, 1, 1), thin, HORIZONTAL_ALIGNMENT_LEFT)
		_product(root, o, i, c)
	# blade signs: the characters stacked top to bottom (or the latin name rotated by its letters)
	for i in BLADES.size():
		var o := Vector2(i * 64, 1024)
		var sc: Array = SIGN_COLS[i % SIGN_COLS.size()]
		_box(root, Rect2(o + Vector2(2, 2), Vector2(60, 316)), sc[0], 4, 3, (sc[1] as Color))
		var t := jp(BLADES[i])
		var stacked := ""
		for ch in t:
			stacked += ch + "\n"
		var n := t.length()
		var fs := clampi(int(280.0 / maxf(n, 1.0) * (0.78 if _cjk == 1 else 0.62)), 16, 52)
		var l := _label(root, Rect2(o + Vector2(4, 8), Vector2(56, 304)), stacked.strip_edges(), fs, sc[1], jpf if _cjk == 1 else lat)
		l.add_theme_constant_override("line_spacing", -int(fs * 0.25))
	# shop signs
	for i in 64:
		var o := Vector2((i % 8) * 256, 1344 + (i / 8) * 64)
		var sc: Array = SIGN_COLS[(i * 3 + 1) % SIGN_COLS.size()]
		if i == 6:
			sc = [Color(0.96, 0.96, 0.97), Color(0.1, 0.1, 0.12)]
		_box(root, Rect2(o + Vector2(2, 2), Vector2(252, 60)), sc[0], 3, 2, (sc[1] as Color).darkened(0.2))
		var t := jp(SHOPS[i]) if i < SHOPS.size() else "SHOP"
		_label(root, Rect2(o + Vector2(6, 4), Vector2(244, 56)), t, 34 if t.length() < 11 else (26 if t.length() < 15 else 20), sc[1], jpf if _cjk == 1 else lat)
	# misc cells
	var m0 := Vector2(0, 1856)
	_box(root, Rect2(m0, Vector2(128, 192)), Color(0.02, 0.02, 0.02))
	_box(root, Rect2(m0 + Vector2(128, 0), Vector2(128, 192)), Color(0.97, 0.97, 0.97))
	var noren := [[Color(0.1, 0.12, 0.3), "ら"], [Color(0.55, 0.05, 0.05), "寿"], [Color(0.95, 0.92, 0.85), "酒"], [Color(0.15, 0.15, 0.15), "麺"]]
	for k in 4:
		var o := m0 + Vector2(256 + k * 128, 0)
		_box(root, Rect2(o + Vector2(2, 0), Vector2(124, 192)), noren[k][0])
		_label(root, Rect2(o, Vector2(128, 192)), str(noren[k][1]) if _cjk == 1 else "", 90, Color(1, 1, 1) if k != 2 else Color(0.1, 0.1, 0.1), jpf)
	var po := m0 + Vector2(768, 0)
	_box(root, Rect2(po + Vector2(4, 4), Vector2(120, 184)), Color(0.08, 0.3, 0.8), 14)
	_label(root, Rect2(po, Vector2(128, 160)), "P", 140, Color(1, 1, 1), lat)
	_label(root, Rect2(po + Vector2(0, 140), Vector2(128, 50)), "24H", 32, Color(1, 0.9, 0.2), lat)
	var ao := m0 + Vector2(896, 0)
	_box(root, Rect2(ao, Vector2(128, 192)), Color(0.96, 0.96, 0.97))
	_box(root, Rect2(ao + Vector2(28, 54), Vector2(72, 76)), Color(0.75, 0.76, 0.8), 36)      # the fruit
	_box(root, Rect2(ao + Vector2(66, 30), Vector2(22, 30)), Color(0.45, 0.75, 0.35), 11)     # its leaf
	_label(root, Rect2(ao + Vector2(0, 140), Vector2(128, 44)), "iApfel", 30, Color(0.15, 0.15, 0.18), thin)
	var mo := m0 + Vector2(1024, 0)
	_box(root, Rect2(mo + Vector2(4, 4), Vector2(120, 184)), Color(0.12, 0.1, 0.08), 6, 4, Color(0.5, 0.35, 0.2))
	var menu := ["ラーメン 800", "味噌 900", "餃子 400", "ビール 500"] if _cjk == 1 else ["RAMEN 800", "MISO 900", "GYOZA 400", "BEER 500"]
	for k in 4:
		_label(root, Rect2(mo + Vector2(10, 18 + k * 40), Vector2(108, 36)), menu[k], 18, Color(1, 0.95, 0.85), jpf if _cjk == 1 else thin, HORIZONTAL_ALIGNMENT_LEFT)
	var so := m0 + Vector2(1152, 0)
	_box(root, Rect2(so + Vector2(14, 40), Vector2(100, 100)), Color(1.0, 0.8, 0.2), 50, 6, Color(0.6, 0.4, 0.05))
	var ph := m0 + Vector2(1280, 0)
	_box(root, Rect2(ph, Vector2(128, 192)), Color(0.15, 0.4, 0.95))
	_box(root, Rect2(ph + Vector2(12, 20), Vector2(104, 60)), Color(1.0, 0.5, 0.7), 10)
	_box(root, Rect2(ph + Vector2(12, 96), Vector2(48, 48)), Color(0.3, 0.95, 0.6), 10)
	_box(root, Rect2(ph + Vector2(68, 96), Vector2(48, 48)), Color(1.0, 0.85, 0.2), 10)
	var vo := m0 + Vector2(1408, 0)
	_box(root, Rect2(vo, Vector2(128, 192)), Color(0.85, 0.92, 1.0))
	for r in 4:
		for c in 4:
			var cc: Color = AD_COLS[(r * 4 + c) % AD_COLS.size()]
			_box(root, Rect2(vo + Vector2(10 + c * 28, 14 + r * 34), Vector2(20, 26)), cc, 4)


## A simple product picture on the right of an ad (rounded shapes).
func _product(root: Control, o: Vector2, i: int, c: Color) -> void:
	var p := o + Vector2(340, 24)
	match i:
		0:   # phone
			_box(root, Rect2(p + Vector2(40, 0), Vector2(84, 166)), Color(0.15, 0.15, 0.17), 16)
			_box(root, Rect2(p + Vector2(46, 8), Vector2(72, 150)), Color(0.3, 0.55, 1.0), 12)
			_box(root, Rect2(p + Vector2(52, 20), Vector2(60, 50)), Color(1.0, 0.5, 0.75), 10)
		1, 8, 13:   # can / bottle
			_box(root, Rect2(p + Vector2(48, 10), Vector2(70, 150)), c.lightened(0.3) if i != 1 else Color(0.95, 0.95, 0.96), 18)
			_box(root, Rect2(p + Vector2(48, 60), Vector2(70, 40)), c.darkened(0.3), 0)
		2:   # bowl
			_box(root, Rect2(p + Vector2(10, 70), Vector2(140, 80)), Color(0.9, 0.2, 0.1), 40)
			_box(root, Rect2(p + Vector2(18, 64), Vector2(124, 24)), Color(0.95, 0.8, 0.45), 12)
		3:   # donut
			_box(root, Rect2(p + Vector2(20, 20), Vector2(130, 130)), Color(0.95, 0.75, 0.45), 65)
			_box(root, Rect2(p + Vector2(28, 26), Vector2(114, 110)), Color(1.0, 0.45, 0.7), 57)
			_box(root, Rect2(p + Vector2(66, 66), Vector2(38, 38)), c, 19)
		4, 11:   # car
			_box(root, Rect2(p + Vector2(0, 80), Vector2(160, 50)), Color(0.85, 0.1, 0.15), 18)
			_box(root, Rect2(p + Vector2(34, 54), Vector2(84, 40)), Color(0.75, 0.08, 0.12), 16)
			_box(root, Rect2(p + Vector2(18, 116), Vector2(34, 34)), Color(0.05, 0.05, 0.05), 17)
			_box(root, Rect2(p + Vector2(108, 116), Vector2(34, 34)), Color(0.05, 0.05, 0.05), 17)
		5:   # tyre
			_box(root, Rect2(p + Vector2(20, 10), Vector2(140, 140)), Color(0.08, 0.08, 0.08), 70)
			_box(root, Rect2(p + Vector2(56, 46), Vector2(68, 68)), Color(0.75, 0.75, 0.78), 34)
		7:   # cup
			_box(root, Rect2(p + Vector2(30, 40), Vector2(100, 110)), Color(0.95, 0.93, 0.88), 16)
			_box(root, Rect2(p + Vector2(122, 70), Vector2(30, 46)), Color(0.95, 0.93, 0.88), 14)
			_box(root, Rect2(p + Vector2(38, 40), Vector2(84, 18)), Color(0.35, 0.2, 0.1), 8)
		9:   # plane-ish
			_box(root, Rect2(p + Vector2(0, 70), Vector2(160, 30)), Color(0.95, 0.95, 0.97), 15)
			_box(root, Rect2(p + Vector2(60, 30), Vector2(30, 110)), Color(0.95, 0.95, 0.97), 10)
		_:
			_box(root, Rect2(p + Vector2(20, 20), Vector2(130, 130)), c.lightened(0.35), 30)
			_box(root, Rect2(p + Vector2(50, 50), Vector2(70, 70)), c.darkened(0.25), 35)
