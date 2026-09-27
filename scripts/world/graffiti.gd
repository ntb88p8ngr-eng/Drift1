extends Node
## Graffiti mode (like the tags in the old Tony Hawk games): the track is split into short cells along
## its length; drifting over a cell sprays it in your car colour until someone else drifts over it.
## Whoever holds the most metres of track at the end wins. The road shader tints the cells, the
## minimap draws them. Online the host is the referee: claims go to the host, which applies them in
## arrival order and broadcasts the result, so every player sees the same owners.

const CELL := 4.0             # metres per cell
const SEND_INTERVAL := 0.2

var track
var count := 0
var cell_len := CELL
var owners := PackedInt32Array()     # 0 = nobody, else peer id
var colors := {}                     # peer id -> Color
var names := {}                      # peer id -> String
var texture: ImageTexture

var _img: Image
var _dirty := false
var _upload_t := 0.0
var _pending := PackedInt32Array()
var _send_t := 0.0
var _local_id := 1
var _online := false


func setup(p_track, players: Dictionary, local_id: int, online: bool) -> void:
	track = p_track
	_local_id = local_id
	_online = online
	count = maxi(int(round(track.length / CELL)), 8)
	cell_len = track.length / float(count)
	owners.resize(count)
	owners.fill(0)
	# player colours = car paint, pushed apart when two players drive the same colour
	var ids: Array = players.keys()
	ids.sort()
	for id in ids:
		var c: Color = players[id]["color"]
		for k in 6:
			var clash := false
			for other in colors.values():
				if _color_dist(c, other) < 0.12:
					clash = true
			if not clash:
				break
			c = Color.from_hsv(fposmod(c.h + 0.17, 1.0), clampf(maxf(c.s, 0.6), 0.0, 1.0), clampf(maxf(c.v, 0.6), 0.0, 1.0))
		colors[id] = c
		names[id] = str(players[id]["name"])
	_img = Image.create(count, 1, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	texture = ImageTexture.create_from_image(_img)
	var mat: ShaderMaterial = track.road_material
	if mat:
		mat.set_shader_parameter("graffiti_tex", texture)
		mat.set_shader_parameter("graffiti_len", float(track.length))
	if online:
		Net.graffiti_claimed.connect(apply_claim)


static func _color_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func cell_at(dist_along: float) -> int:
	return clampi(int(fposmod(dist_along, track.length) / cell_len), 0, count - 1)


## Local car drifted over the cell at `dist_along` (metres along the centreline).
func spray(dist_along: float) -> void:
	var c := cell_at(dist_along)
	if owners[c] == _local_id:
		return
	_set_owner(c, _local_id)   # shown right away; online the host's answer is authoritative
	if _online and not _pending.has(c):
		_pending.append(c)


func apply_claim(owner_id: int, cells: PackedInt32Array) -> void:
	for c in cells:
		if c >= 0 and c < count:
			_set_owner(c, owner_id)


func _set_owner(c: int, id: int) -> void:
	if owners[c] == id:
		return
	owners[c] = id
	var col: Color = colors.get(id, Color(1, 1, 1))
	col.a = 1.0 if id != 0 else 0.0
	_img.set_pixel(c, 0, col)
	_dirty = true


func _process(delta: float) -> void:
	_upload_t -= delta
	if _dirty and _upload_t <= 0.0:
		_dirty = false
		_upload_t = 0.1
		texture.update(_img)
	if _online:
		_send_t -= delta
		if _send_t <= 0.0 and not _pending.is_empty():
			_send_t = SEND_INTERVAL
			Net.send_graffiti(_pending)
			_pending = PackedInt32Array()


func metres(id: int) -> float:
	var n := 0
	for o in owners:
		if o == id:
			n += 1
	return n * cell_len


## [[peer id, metres, share 0..1], …] sorted by metres, only players that exist.
func standings() -> Array:
	var per := {}
	for o in owners:
		if o != 0:
			per[o] = int(per.get(o, 0)) + 1
	var out: Array = []
	for id in colors.keys():
		var n: int = per.get(id, 0)
		out.append([id, n * cell_len, float(n) / float(count)])
	out.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return out
