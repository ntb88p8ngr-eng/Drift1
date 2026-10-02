extends Node3D
## The city's light pool: thousands of light sources are registered (streetlights, shop fronts, neon,
## lit signs, vending machines) but only the nearest ones around the camera – ahead of it preferred –
## get one of a fixed number of real lights (spots pointing down for street lamps, omnis for the rest).
## Re-assigned a few times a second; they fade in and out with distance, only at night.

var emitters: Array = []        # [Vector3 position, Color, range, energy, kind 0 omni / 1 spot down]
var night := 0.0
var _grid := {}                 # Vector2i (40 m cells) -> Array of emitter indices
var _omni: Array = []
var _spot: Array = []
var _t := 0.0
const CELL := 40.0
const REACH := 140.0


func setup(list: Array, quality: int) -> void:
	emitters = list
	for i in emitters.size():
		var p: Vector3 = emitters[i][0]
		var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)
	var n_omni: int = [12, 24, 36, 52][clampi(quality, 0, 3)]
	var n_spot: int = [16, 32, 48, 64][clampi(quality, 0, 3)]
	for k in n_omni:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = REACH - 50.0
		l.distance_fade_length = 40.0
		l.visible = false
		add_child(l)
		_omni.append(l)
	for k in n_spot:
		var l := SpotLight3D.new()
		l.shadow_enabled = false
		l.spot_angle = 62.0
		l.spot_attenuation = 0.7
		l.distance_fade_enabled = true
		l.distance_fade_begin = REACH - 50.0
		l.distance_fade_length = 40.0
		l.visible = false
		add_child(l)
		_spot.append(l)


func set_night(n: float) -> void:
	night = n
	if n < 0.15:
		for l in _omni + _spot:
			(l as Light3D).visible = false


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or night < 0.15:
		return
	_t = 0.2
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var c0 := Vector2i(int(floor((cp.x - REACH) / CELL)), int(floor((cp.z - REACH) / CELL)))
	var c1 := Vector2i(int(floor((cp.x + REACH) / CELL)), int(floor((cp.z + REACH) / CELL)))
	var cand_o: Array = []
	var cand_s: Array = []
	for gz in range(c0.y, c1.y + 1):
		for gx in range(c0.x, c1.x + 1):
			var key := Vector2i(gx, gz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				var e: Array = emitters[i]
				var rel: Vector3 = (e[0] as Vector3) - cp
				var d := rel.length()
				if d > REACH:
					continue
				# behind the camera counts as further away
				var score := d * (1.0 if rel.dot(fwd) > -4.0 else 2.2)
				if int(e[4]) == 1:
					cand_s.append(Vector2(score, i))
				else:
					cand_o.append(Vector2(score, i))
	cand_o.sort()
	cand_s.sort()
	_assign(_omni, cand_o)
	_assign(_spot, cand_s)


func _assign(pool: Array, cand: Array) -> void:
	for k in pool.size():
		var l: Light3D = pool[k]
		if k >= cand.size():
			l.visible = false
			continue
		var e: Array = emitters[int(cand[k].y)]
		l.visible = true
		l.light_color = e[1]
		l.light_energy = float(e[3]) * night
		if l is OmniLight3D:
			(l as OmniLight3D).omni_range = e[2]
			l.global_position = e[0]
		else:
			(l as SpotLight3D).spot_range = e[2]
			l.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), e[0])
