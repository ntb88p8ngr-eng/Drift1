extends RefCounted
## Painted ground textures (world editor): one texel per square metre in a 1 km x 1 km window
## (placed where the first stroke lands) holding which of the standard textures lies there
## (R = id, 0 = none) and how strongly (G). The terrain shader blends it over the ground, the grass
## stays off everything that isn't grass. Saved with the map.

const SIZE := 1024
const RES := 1.0

## id -> [name, swatch colour] (the shader draws the textures; ids must stay as they are – saved maps)
const TEXTURES := [
	[1, "Gras", Color(0.17, 0.36, 0.07)],
	[2, "Trockenes Gras", Color(0.42, 0.4, 0.2)],
	[3, "Waldboden", Color(0.09, 0.12, 0.05)],
	[4, "Erde", Color(0.3, 0.22, 0.14)],
	[5, "Schlamm", Color(0.16, 0.12, 0.08)],
	[6, "Fels", Color(0.4, 0.39, 0.37)],
	[7, "Kies", Color(0.5, 0.47, 0.42)],
	[8, "Sand", Color(0.66, 0.58, 0.42)],
	[9, "Asphalt", Color(0.12, 0.12, 0.13)],
	[10, "Beton", Color(0.5, 0.49, 0.46)],
]

var active := false
var origin := Vector2.ZERO
var img: Image
var tex: ImageTexture
var _dirty := false
var _targets: Array = []     # ShaderMaterials (terrain) that draw it
var _grass                   # grass.gd


func _start(at: Vector2) -> void:
	origin = Vector2(floor(at.x - SIZE * RES * 0.5), floor(at.y - SIZE * RES * 0.5))
	img = Image.create(SIZE, SIZE, false, Image.FORMAT_RG8)
	tex = ImageTexture.create_from_image(img)
	active = true
	_bind()


## The terrain materials (and the grass) that show the paint.
func attach(materials: Array, grass) -> void:
	_targets = materials
	_grass = grass
	if active:
		_bind()


func _bind() -> void:
	for m in _targets:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("paint_tex", tex)
			(m as ShaderMaterial).set_shader_parameter("paint_origin", origin)
			(m as ShaderMaterial).set_shader_parameter("paint_res", RES)
			(m as ShaderMaterial).set_shader_parameter("paint_size", SIZE if active else 0)
	if _grass and is_instance_valid(_grass) and _grass.has_method("set_paint"):
		_grass.set_paint(tex, origin, RES, SIZE if active else 0)


## One dab of the brush: texture `id` (0 / erase: rub out) within `radius`, `amount` 0..1.
func dab(at: Vector3, radius: float, id: int, amount: float, erase: bool) -> void:
	if not active:
		_start(Vector2(at.x, at.z))
	var c := (Vector2(at.x, at.z) - origin) / RES
	var r := int(ceil(radius / RES))
	var x0 := maxi(int(c.x) - r, 0)
	var y0 := maxi(int(c.y) - r, 0)
	var x1 := mini(int(c.x) + r, SIZE - 1)
	var y1 := mini(int(c.y) + r, SIZE - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) * RES
			var k := (1.0 - smoothstep(radius * 0.5, radius, d)) * amount
			if k <= 0.0:
				continue
			var px := img.get_pixel(x, y)
			var cur := int(round(px.r * 255.0))
			var op := px.g
			if erase:
				op = maxf(op - k, 0.0)
			elif cur == id or op < 0.03:
				cur = id
				op = minf(op + k, 1.0)
			else:
				# another texture lies here: it fades out first, then the new one comes in
				op -= k * 1.5
				if op <= 0.0:
					cur = id
					op = -op * 0.5
			img.set_pixel(x, y, Color(float(cur) / 255.0, op, 0.0))
	_dirty = true


## Uploads the changed image (the editor calls it a few times a second while painting).
func flush() -> void:
	if _dirty and tex:
		tex.update(img)
		_dirty = false


func snapshot():
	return null if not active else [origin, img.duplicate()]


func restore(snap) -> void:
	if snap == null:
		active = false
		img = null
		tex = null
		_bind()
		return
	var was := active
	origin = snap[0]
	img = (snap[1] as Image).duplicate()
	if tex == null or not was:
		tex = ImageTexture.create_from_image(img)
		active = true
		_bind()
	else:
		tex.update(img)
		_bind()


func to_dict() -> Dictionary:
	if not active:
		return {}
	var raw := img.get_data()
	return {"origin": [origin.x, origin.y], "size": SIZE, "len": raw.size(),
		"data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_ZSTD))}


func from_dict(d: Dictionary) -> void:
	if d.is_empty() or int(d.get("size", 0)) != SIZE:
		return
	var raw := Marshalls.base64_to_raw(str(d.get("data", ""))).decompress(int(d.get("len", SIZE * SIZE * 2)), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != SIZE * SIZE * 2:
		return
	origin = Vector2(float(d["origin"][0]), float(d["origin"][1]))
	img = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RG8, raw)
	tex = ImageTexture.create_from_image(img)
	active = true
	_bind()
