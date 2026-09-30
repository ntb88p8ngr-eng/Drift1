extends RefCounted
## Procedural textures for the tutorial house (interior and garage). Generated once and cached.

static var _cache := {}


static func _h(x: int, y: int, s: int) -> float:
	var v := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	v = (v ^ (v >> 13)) * 1274126177
	return float((v ^ (v >> 16)) & 0xffff) / 65535.0


static func _noise(seed_v: int, freq: float, oct := 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = oct
	return n


static func _finish(key: String, img: Image) -> ImageTexture:
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## Oak planks: 6 boards across (u), staggered end joints along v, fine grain and knots.
static func floor_wood() -> ImageTexture:
	if _cache.has("floor"):
		return _cache["floor"]
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var grain := _noise(3, 0.02, 3)
	var fine := _noise(4, 0.2, 2)
	var boards := 6
	for y in s:
		for x in s:
			var bw := s / boards
			var bi := x / bw
			var bx := float(x % bw) / bw
			var off := _h(bi, 1, 9) * s
			var seg := int(floor((y + off) / (s * 0.5)))
			var id := bi * 7 + seg * 13
			var tone := 0.82 + 0.3 * _h(id, 2, 5)
			var g := grain.get_noise_2d(x * 0.25 + id * 40.0, y * 3.0)
			var fg := fine.get_noise_2d(x * 2.0, y * 0.4)
			var c := Color(0.52, 0.34, 0.19).lerp(Color(0.68, 0.48, 0.29), 0.5 + g * 0.9) * tone
			c = c.darkened(clampf(fg * 0.12, -0.05, 0.12))
			# seams between the boards and at the board ends
			var yy := fposmod(y + off, s * 0.5)
			var seam := minf(minf(bx, 1.0 - bx) * bw, minf(yy, s * 0.5 - yy))
			if seam < 1.0:
				c = c.darkened(0.45)
			img.set_pixel(x, y, c)
	return _finish("floor", img)


## Cream wallpaper: soft vertical stripes with a small repeating motif.
static func wallpaper() -> ImageTexture:
	if _cache.has("wallpaper"):
		return _cache["wallpaper"]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in s:
		for x in s:
			var u := float(x) / s
			var v := float(y) / s
			var stripe := 0.5 + 0.5 * cos(u * TAU * 4.0)
			var cx := fposmod(u * 4.0, 1.0) - 0.5
			var cy := fposmod(v * 4.0 + (0.5 if int(u * 4.0) % 2 == 1 else 0.0), 1.0) - 0.5
			var motif := smoothstep(0.16, 0.1, absf(cx) + absf(cy) * 0.7) * 0.6
			var c := Color(0.8, 0.76, 0.66).lerp(Color(0.86, 0.82, 0.72), stripe * 0.6)
			c = c.lerp(Color(0.7, 0.62, 0.5), motif)
			img.set_pixel(x, y, c)
	return _finish("wallpaper", img)


## White glossy kitchen tiles (4 x 4 per texture) with grey grout.
static func tiles() -> ImageTexture:
	if _cache.has("tiles"):
		return _cache["tiles"]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in s:
		for x in s:
			var tx := x % 32
			var ty := y % 32
			var g := tx < 2 or ty < 2
			var tone := 0.9 + 0.06 * _h(x / 32, y / 32, 3)
			img.set_pixel(x, y, Color(0.55, 0.55, 0.53) if g else Color(tone, tone, tone * 0.98))
	return _finish("tiles", img)


## Persian-style rug: borders, a medallion and repeating motifs.
static func rug() -> ImageTexture:
	if _cache.has("rug"):
		return _cache["rug"]
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var red := Color(0.42, 0.06, 0.06)
	var navy := Color(0.07, 0.1, 0.22)
	var cream := Color(0.82, 0.74, 0.58)
	var gold := Color(0.72, 0.52, 0.2)
	var fib := _noise(8, 0.4, 2)
	for y in s:
		for x in s:
			var u := float(x) / s * 2.0 - 1.0
			var v := float(y) / s * 2.0 - 1.0
			var e := maxf(absf(u), absf(v))
			var c := red
			if e > 0.9:
				c = navy
			elif e > 0.84:
				c = cream
			elif e > 0.72:
				var m := 0.5 + 0.5 * sin((u + v) * 40.0) * sin((u - v) * 40.0)
				c = navy.lerp(gold, smoothstep(0.55, 0.8, m))
			elif e > 0.68:
				c = cream
			else:
				var d := absf(u) + absf(v)
				if d < 0.45:
					c = navy.lerp(cream, smoothstep(0.3, 0.2, d))
					c = c.lerp(red, smoothstep(0.1, 0.05, d))
				else:
					var p := 0.5 + 0.5 * sin(u * 26.0) * sin(v * 26.0)
					c = red.lerp(gold * 0.7, smoothstep(0.7, 0.9, p))
			c = c.darkened(0.12 * (fib.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5))
			img.set_pixel(x, y, c)
	return _finish("rug", img)


## Woven fabric (greyscale, tinted by the material colour).
static func fabric() -> ImageTexture:
	if _cache.has("fabric"):
		return _cache["fabric"]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n := _noise(11, 0.08, 3)
	for y in s:
		for x in s:
			var weave := 0.5 + 0.25 * sin(x * PI * 0.5) * sin(y * PI * 0.5 + PI * 0.5 * float(x % 4 < 2))
			var v := 0.78 + 0.14 * weave + 0.1 * n.get_noise_2d(x, y)
			img.set_pixel(x, y, Color(v, v, v))
	return _finish("fabric", img)


## Garage floor: sealed concrete with oil stains, tyre marks and hairline cracks.
static func concrete() -> ImageTexture:
	if _cache.has("concrete"):
		return _cache["concrete"]
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n := _noise(21, 0.03, 5)
	var st := _noise(22, 0.012, 3)
	var cr := _noise(23, 0.02, 1)
	cr.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cr.noise_type = FastNoiseLite.TYPE_CELLULAR
	for y in s:
		for x in s:
			var g := 0.52 + 0.08 * n.get_noise_2d(x, y)
			var c := Color(g, g, g * 0.98)
			var stain := smoothstep(0.35, 0.6, st.get_noise_2d(x, y))
			c = c.lerp(Color(0.2, 0.19, 0.18), stain * 0.7)
			var crack := smoothstep(0.03, 0.0, absf(cr.get_noise_2d(x, y) + 0.9))
			c = c.darkened(crack * 0.4)
			img.set_pixel(x, y, c)
	return _finish("concrete", img)


## Painted concrete blocks (0.4 x 0.2 m, texture = 1.6 x 1.6 m) with mortar joints.
static func blocks() -> ImageTexture:
	if _cache.has("blocks"):
		return _cache["blocks"]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n := _noise(31, 0.1, 3)
	for y in s:
		for x in s:
			var row := y / 16
			var xx := x + (16 if row % 2 == 1 else 0)
			var joint := (xx % 32) < 1 or (y % 16) < 1
			var g := 0.74 + 0.05 * n.get_noise_2d(x, y)
			img.set_pixel(x, y, Color(0.58, 0.58, 0.56) if joint else Color(g, g, g * 0.97))
	return _finish("blocks", img)


static func pegboard() -> ImageTexture:
	if _cache.has("pegboard"):
		return _cache["pegboard"]
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in s:
		for x in s:
			var hole := Vector2(x % 8 - 3.5, y % 8 - 3.5).length() < 1.3
			img.set_pixel(x, y, Color(0.12, 0.1, 0.08) if hole else Color(0.6, 0.47, 0.32))
	return _finish("pegboard", img)


## Dark slate roof tiles in overlapping rows.
static func roof() -> ImageTexture:
	if _cache.has("roof"):
		return _cache["roof"]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in s:
		for x in s:
			var row := y / 16
			var xx := x + (8 if row % 2 == 1 else 0)
			var edge := (y % 16) / 16.0
			var tone := 0.16 + 0.05 * _h(xx / 16, row, 4)
			var c := Color(tone, tone * 1.02, tone * 1.1) * (0.7 + 0.3 * edge)
			if xx % 16 < 1:
				c = c.darkened(0.5)
			img.set_pixel(x, y, c)
	return _finish("roof", img)


static func plaster() -> ImageTexture:
	if _cache.has("plaster"):
		return _cache["plaster"]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n := _noise(41, 0.09, 4)
	for y in s:
		for x in s:
			var g := 0.83 + 0.06 * n.get_noise_2d(x, y) + 0.03 * (_h(x, y, 2) - 0.5)
			img.set_pixel(x, y, Color(g, g * 0.97, g * 0.9))
	return _finish("plaster", img)


## Walnut for the furniture.
static func walnut() -> ImageTexture:
	if _cache.has("walnut"):
		return _cache["walnut"]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var g := _noise(51, 0.03, 3)
	for y in s:
		for x in s:
			var v := 0.5 + 0.5 * sin(x * 0.35 + g.get_noise_2d(x * 0.3, y * 2.0) * 6.0)
			img.set_pixel(x, y, Color(0.26, 0.15, 0.08).lerp(Color(0.38, 0.23, 0.12), v))
	return _finish("walnut", img)


## Roller door slats: white painted steel with grooves every 12 px.
static func slats() -> ImageTexture:
	if _cache.has("slats"):
		return _cache["slats"]
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in s:
		for x in s:
			var k := float(y % 16) / 16.0
			var g := 0.78 + 0.12 * sin(k * PI) - (0.3 if y % 16 < 1 else 0.0)
			img.set_pixel(x, y, Color(g, g, g * 1.02))
	return _finish("slats", img)


## Clock face: cream disc, hour and minute ticks, dark rim (the numerals are Label3Ds).
static func clock_face() -> ImageTexture:
	if _cache.has("clock"):
		return _cache["clock"]
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var p := Vector2(x - s * 0.5 + 0.5, y - s * 0.5 + 0.5) / (s * 0.5)
			var r := p.length()
			if r > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c := Color(0.93, 0.9, 0.8)
			var a := fposmod(atan2(p.x, -p.y), TAU)
			var m := fposmod(a / TAU * 60.0 + 0.5, 1.0) - 0.5
			var hr := fposmod(a / TAU * 12.0 + 0.5, 1.0) - 0.5
			if r > 0.8 and r < 0.9 and absf(m) < 0.06:
				c = Color(0.15, 0.13, 0.1)
			if r > 0.72 and r < 0.9 and absf(hr) < 0.035:
				c = Color(0.08, 0.07, 0.05)
			if r > 0.93:
				c = Color(0.25, 0.16, 0.08)
			img.set_pixel(x, y, c)
	return _finish("clock", img)
