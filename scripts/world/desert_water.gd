extends RefCounted
## Utah's lake and river: a round lake in the middle of the map, a river flowing into it from one
## side and out of it on the other (a dam just below the lake holds it up), the land round the lake
## a flat terrace for the ring road and its buildings. Shared by the track (its hills dip into the
## river valleys, so the road crosses the river on bridges), the terrain (lake bed, river channel,
## valleys) and the scenery (water, bridges, dam, ring road).
## Everything here comes from the track definition ("lake"), the same on every machine.

const CELL := 4.0
const RIVER_W := 14.0          # river width (m)
const BANK := 3.5              # river bank top above the water (where a bridge road runs)
const FALL := 0.012            # river gradient
const DAM_DROP := 4.0          # the water falls this far over the dam
const VALLEY := 70.0           # the hills open out into the river valley over this distance
const PLATEAU_FADE := 60.0

var center := Vector2.ZERO
var radius := 45.0             # the lake
var ring_r := 62.0             # the ring road's centre line
var ring_w := 10.0
var terrace := 95.0            # the flat land round the lake reaches this far
var level := 0.8               # the lake's water level
var plateau := 2.0             # the terrace's height
var dam_s := 17.0              # how far down the outflow the dam stands (under the ring road)
## [inflow, outflow]: {pts: PackedVector2Array (from the lake shore outwards), s: PackedFloat32Array}
var rivers: Array = []
var spokes: Array = []         # angles (rad) of the roads from the ring out to the track

var _origin := Vector2.ZERO
var _n := Vector2i.ZERO
var _d := PackedFloat32Array()     # distance to the nearest river centre line
var _w := PackedFloat32Array()     # that river's water level there


func _init(d: Dictionary) -> void:
	center = d.get("center", Vector2.ZERO)
	radius = float(d.get("radius", radius))
	ring_r = float(d.get("ring", ring_r))
	terrace = float(d.get("terrace", terrace))
	plateau = float(d.get("plateau", plateau))
	level = plateau - 1.2
	for k in 2:
		var a := deg_to_rad(float((d.get("rivers", [30.0, 240.0]) as Array)[k]))
		rivers.append(_river_path(a, 900.0, 11 + k))
	for a in d.get("spokes", []):
		spokes.append(deg_to_rad(float(a)))
	_raster()


## The river from the shore at angle `a` outwards, meandering gently.
func _river_path(a: float, length: float, seed_value: int) -> Dictionary:
	var dir := Vector2(cos(a), sin(a))
	var perp := Vector2(-dir.y, dir.x)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var ph := r.randf() * TAU
	var pts := PackedVector2Array()
	var ss := PackedFloat32Array()
	var s := 0.0
	var prev := center + dir * (radius - 6.0)
	while s <= length:
		var wig := (sin(s / 70.0 + ph) * 14.0 + sin(s / 23.0 + ph * 2.0) * 3.0) * smoothstep(20.0, 90.0, s)
		var p := center + dir * (radius - 6.0 + s) + perp * wig
		pts.append(p)
		ss.append(float(ss[ss.size() - 1]) + prev.distance_to(p) if ss.size() > 0 else 0.0)
		prev = p
		s += 4.0
	return {"pts": pts, "s": ss}


## Water level of river k at `s` metres from the lake shore.
func river_level(k: int, s: float) -> float:
	if k == 0:
		return level + s * FALL                       # the inflow runs down into the lake
	if s < dam_s:
		return level                                  # above the dam: the lake itself
	return level - DAM_DROP - (s - dam_s) * FALL      # below it: on down the valley


func _raster() -> void:
	var reach := VALLEY + RIVER_W
	var lo := center - Vector2(1000, 1000)
	_origin = lo
	_n = Vector2i(int(2000.0 / CELL) + 1, int(2000.0 / CELL) + 1)
	_d.resize(_n.x * _n.y)
	_d.fill(1e9)
	_w.resize(_n.x * _n.y)
	_w.fill(level)
	var rc := int(ceil(reach / CELL))
	for k in rivers.size():
		var pts: PackedVector2Array = rivers[k]["pts"]
		var ss: PackedFloat32Array = rivers[k]["s"]
		for i in pts.size():
			var p := pts[i]
			var wl := river_level(k, ss[i])
			var cx := int(round((p.x - lo.x) / CELL))
			var cz := int(round((p.y - lo.y) / CELL))
			for dz in range(-rc, rc + 1):
				var gz := cz + dz
				if gz < 0 or gz >= _n.y:
					continue
				for dx in range(-rc, rc + 1):
					var gx := cx + dx
					if gx < 0 or gx >= _n.x:
						continue
					var q := lo + Vector2(gx, gz) * CELL
					# distance to the segment towards the next point (smooth along the river)
					var j := mini(i + 1, pts.size() - 1)
					var dd := q.distance_to(Geometry2D.get_closest_point_to_segment(q, p, pts[j]))
					var idx := gz * _n.x + gx
					if dd < _d[idx]:
						_d[idx] = dd
						_w[idx] = wl


func _sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - _origin.x) / CELL, 0.0, _n.x - 1.001)
	var fz := clampf((z - _origin.y) / CELL, 0.0, _n.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * _n.x + ix
	return lerpf(lerpf(arr[k], arr[k + 1], tx), lerpf(arr[k + _n.x], arr[k + _n.x + 1], tx), tz)


## [distance to the nearest river's centre line, its water level there]
func river_at(x: float, z: float) -> Vector2:
	return Vector2(_sample(_d, x, z), _sample(_w, x, z))


## The hills, bent to the water: flat terrace round the lake, valleys along the rivers whose
## floor (the bank top) lies BANK above the water.
func shape(x: float, z: float, h: float) -> float:
	var dc := Vector2(x, z).distance_to(center)
	h = lerpf(plateau, h, smoothstep(terrace, terrace + PLATEAU_FADE, dc))
	var r := river_at(x, z)
	if r.x < VALLEY + RIVER_W:
		# (on the terrace the river just runs in its channel: no valley there)
		var k := smoothstep(terrace - 10.0, terrace + 30.0, dc)
		var valley := lerpf(r.y + BANK, h, smoothstep(RIVER_W * 0.5 + 6.0, RIVER_W * 0.5 + VALLEY, r.x))
		h = lerpf(h, valley, k)
	return h


## 1 away from the water, 0 at it (the extra roughness of the land fades out near it).
func calm(x: float, z: float) -> float:
	var dc := Vector2(x, z).distance_to(center)
	var r := river_at(x, z)
	return smoothstep(terrace, terrace + PLATEAU_FADE, dc) * smoothstep(RIVER_W, RIVER_W + VALLEY, r.x)


## The ground cut down to the lake bed and the river channel (INF where neither).
func carve(x: float, z: float) -> float:
	var c := INF
	var dc := Vector2(x, z).distance_to(center)
	if dc < radius + 8.0:
		c = level - 3.0 + 4.8 * smoothstep(radius - 12.0, radius + 5.0, dc)
	var r := river_at(x, z)
	if r.x < RIVER_W * 0.5 + 10.0:
		c = minf(c, r.y - 1.8 + 6.0 * smoothstep(RIVER_W * 0.5 - 3.0, RIVER_W * 0.5 + 7.0, r.x))
	return c


## Wet or water within `margin` metres (keeps buildings, cacti and rocks out of it).
func wet(x: float, z: float, margin: float) -> bool:
	if Vector2(x, z).distance_to(center) < radius + margin:
		return true
	return river_at(x, z).x < RIVER_W * 0.5 + margin


## On the terrace, in the ring road's band or the lake: kept free for the ring and its buildings.
func ring_band(x: float, z: float, margin: float) -> bool:
	var dc := Vector2(x, z).distance_to(center)
	return absf(dc - ring_r) < ring_w * 0.5 + margin
