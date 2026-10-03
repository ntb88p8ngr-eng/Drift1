extends Node3D
## Height field around the track. The road corridor (road, run-off, walls) stays flat at y = 0;
## behind the walls the ground blends into noise hills, so the road runs through cuttings, along
## embankments and past slopes. Ridge: forested hills that grow into mountains. Harbor: a flat
## concrete apron around the track, grassy berms and hills on the land side, sea floor under the water.
## Built as chunked meshes (splat colours: R = concrete, G = dirt, B = forest floor, A = meadow)
## plus a HeightMapShape3D for collision. Also answers height/ground queries for vegetation, grass,
## spectators and weather.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const CELL := 4.0
const MARGIN := 264.0          # inner grid reaches this far beyond the track bounds (multiple of 24)
const OUTER_CELL := 24.0
const OUTER_HALF := 1800.0
const CHUNK := 32              # cells per mesh chunk
const DIST_CELL := 8.0         # resolution of the distance-to-road field
const DIST_MAX := 140.0
# data tracks (Grüne Hölle): real elevation and land cover, a much bigger map
const BIG_MARGIN := 360.0      # inner grid beyond the track bounds (multiple of 24)
const BIG_OUTER_CELL := 40.0
const BIG_OUTER_HALF := 4400.0
const NEAR_R := 24.0           # exact road heights (projection on the centreline) this close to it
const FINE_DIST := 80.0        # mesh chunks closer to the road than this get the 4 m mesh …
const FINE_RANGE := 900.0      # … up to this camera distance, the 16 m mesh beyond
const COARSE := 4

var track
var track_id := "ridge"
var origin := Vector2.ZERO     # world xz of vertex (0, 0)
var nx := 0
var nz := 0
var heights := PackedFloat32Array()
var splat := PackedColorArray()
var material: ShaderMaterial
var outer_material: ShaderMaterial
var flat_r := 17.0             # distance to the centreline that is guaranteed flat
var banked := false            # the track has banked corners (the ground follows them)

var _dist := PackedFloat32Array()
var _dn := Vector2i.ZERO
var _dorigin := Vector2.ZERO
var _n_large := FastNoiseLite.new()
var _n_mid := FastNoiseLite.new()
var _n_small := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_blend := FastNoiseLite.new()
var _n_forest := FastNoiseLite.new()
var _n_meadow := FastNoiseLite.new()
var _center := Vector2.ZERO
var islands: Array = []        # playground: grass islands [Vector2 centre, radius]
var _quay_z := 1e9
var big := false               # data track: DEM + land cover instead of noise hills
var _dem := PackedFloat32Array()
var _dem_o := Vector2.ZERO
var _dem_c := 10.0
var _dem_n := Vector2i.ZERO
var _cover := PackedByteArray()   # forest, field, village (3 bytes per DEM cell)
var _rh := PackedFloat32Array()   # distance-field grid: road height at the nearest sample
var _near_d := PackedFloat32Array()
var _near_h := PackedFloat32Array()


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------
func generate(p_track: Node3D) -> void:
	track = p_track
	track_id = track.track_id
	var seed_base: int = {"ridge": 1234, "harbor": 5678}.get(track_id, 9012)
	_setup_noise(_n_large, seed_base, 1.0 / 260.0, 4)
	_setup_noise(_n_mid, seed_base + 1, 1.0 / 85.0, 3)
	_setup_noise(_n_small, seed_base + 2, 1.0 / 14.0, 2)
	_setup_noise(_n_ridge, seed_base + 3, 1.0 / 160.0, 3)
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup_noise(_n_blend, seed_base + 4, 1.0 / 120.0, 2)
	_setup_noise(_n_forest, seed_base + 5, 1.0 / 110.0, 3)
	_setup_noise(_n_meadow, seed_base + 6, 1.0 / 45.0, 2)
	var b: Rect2 = track.bounds
	_center = b.get_center()
	_quay_z = b.end.y + 45.0 if track_id == "harbor" else 1e9
	flat_r = float(track.wall_base) + 5.0
	big = bool(track.elevated)
	banked = false
	for bk in track.bank:
		if bk != 0.0:
			banked = true
			break
	if big:
		_load_data()
	var margin := BIG_MARGIN if big else MARGIN
	# the grid border lies on whole outer-ring cells (24 m, 40 m on data tracks)
	var unit := 120.0 if big else 24.0
	origin = Vector2(floor((b.position.x - margin) / unit) * unit, floor((b.position.y - margin) / unit) * unit)
	var end := Vector2(ceil((b.end.x + margin) / unit) * unit, ceil((b.end.y + margin) / unit) * unit)
	nx = int(round((end.x - origin.x) / CELL)) + 1
	nz = int(round((end.y - origin.y) / CELL)) + 1
	await _build_distance_field()
	if track_id == "playground":
		_setup_islands()
	heights.resize(nx * nz)
	splat.resize(nx * nz)
	if big:
		await _stamp_near()
		await _generate_big()
		return
	for iz in nz:
		await Game.load_tick(0.3 + 0.7 * iz / nz)
		var z := origin.y + iz * CELL
		for ix in nx:
			var x := origin.x + ix * CELL
			var d := _dist_raw(x, z)
			var k := iz * nx + ix
			heights[k] = _height_fn(x, z, d)
			splat[k] = _splat_fn(x, z, d)


# ---------------------------------------------------------------------------
# Data tracks: real elevation + land cover (tools/make_gruene_hoelle.py)
# ---------------------------------------------------------------------------
func _load_data() -> void:
	var meta: Dictionary = track.meta
	var dir: String = track.def["data"]
	_dem_o = Vector2(float(meta["grid_origin"][0]), float(meta["grid_origin"][1]))
	_dem_c = float(meta["grid_cell"])
	_dem_n = Vector2i(int(meta["grid_size"][0]), int(meta["grid_size"][1]))
	var raw := FileAccess.get_file_as_bytes(dir + "/dem.bin").decompress(int(meta["dem_bytes"]), FileAccess.COMPRESSION_DEFLATE)
	var base := float(meta["dem_min"]) - float(meta["h0"])
	_dem.resize(_dem_n.x * _dem_n.y)
	for i in _dem.size():
		_dem[i] = base + raw.decode_u16(i * 2) * 0.01
	_cover = FileAccess.get_file_as_bytes(dir + "/cover.bin").decompress(int(meta["cover_bytes"]), FileAccess.COMPRESSION_DEFLATE)


## Heights and ground colours of a data track. The DEM and the land cover are scaled up to the 4 m
## grid natively (Image.resize samples 3 m off the grid – irrelevant at DEM accuracy); everything
## further than DIST_MAX from the road is taken as is, only the corridor is blended per node.
func _generate_big() -> void:
	var base := _upsample(Image.create_from_data(_dem_n.x, _dem_n.y, false, Image.FORMAT_RF, _dem.to_byte_array())).get_data().to_float32_array()
	var cov := _upsample(Image.create_from_data(_dem_n.x, _dem_n.y, false, Image.FORMAT_RGB8, _cover)).get_data()
	var far := DIST_MAX - 1.0
	var dstride := _dn.x
	heights = base
	# chunks that get the 4 m mesh need colours on every node, the others only on the 16 m lattice
	var fine := _fine_chunks()
	var cxn := int(ceil(float(nx - 1) / CHUNK))
	for iz in nz:
		await Game.load_tick(0.4 + 0.6 * iz / nz)
		var z := origin.y + iz * CELL
		var fz := (z - _dorigin.y) / DIST_CELL
		var dz := mini(int(fz), _dn.y - 2)
		for ix in nx:
			var k := iz * nx + ix
			var x := origin.x + ix * CELL
			var fx := (x - _dorigin.x) / DIST_CELL
			var dk := dz * dstride + mini(int(fx), _dn.x - 2)
			if _near_d[k] >= NEAR_R and _dist[dk] >= far and _dist[dk + 1] >= far and _dist[dk + dstride] >= far and _dist[dk + dstride + 1] >= far:
				# away from the road: the real ground as it is, woods from the land cover
				if (ix % COARSE != 0 or iz % COARSE != 0) and ix != nx - 1 and iz != nz - 1 and not fine[mini(iz / CHUNK, fine.size() / cxn - 1) * cxn + mini(ix / CHUNK, cxn - 1)]:
					continue
				var c := k * 3
				var f := smoothstep(0.3, 0.62, cov[c] / 255.0 - cov[c + 2] / 255.0 * 0.8)
				splat[k] = Color(0.0, 0.0, minf(f * 1.2, 1.0), minf(0.3 + cov[c + 1] / 255.0 * 0.45, 1.0) * (1.0 - f))
				continue
			var d := _near_d[k] if _near_d[k] < NEAR_R else _dist_raw(x, z)
			heights[k] = _height_big(x, z, d, k, base[k])
			splat[k] = _splat_big(x, z, d, cov[k * 3] / 255.0, cov[k * 3 + 1] / 255.0, cov[k * 3 + 2] / 255.0)
	_near_d = PackedFloat32Array()
	_near_h = PackedFloat32Array()


## Ground colours along the road of a data track (same rules as _splat_fn + forest_density, with the
## land cover already sampled).
func _splat_big(x: float, z: float, d: float, c_forest: float, c_field: float, c_village: float) -> Color:
	var wb := float(track.wall_base)
	var dirt := smoothstep(wb - 1.0, wb, d) * (1.0 - smoothstep(wb + 0.8, wb + 2.8, d)) * 0.7
	var fade := _far_fade(d)
	var n := _n_forest.get_noise_2d(x, z) * 0.5 + 0.5
	var forest := smoothstep(0.3, 0.62, c_forest * lerpf(1.0, 0.7 + 0.6 * n, fade) - c_village * 0.8)
	forest *= smoothstep(wb + 1.5, wb + 4.0, d)
	var mn := lerpf(0.3, _n_meadow.get_noise_2d(x, z) * 0.9 + 0.2, fade) + c_field * 0.45
	return Color(0.0, dirt, minf(forest * 1.2, 1.0), clampf(mn, 0.0, 1.0) * (1.0 - forest))


## 1 along the road, 0 where the plain far ground starts (data tracks).
static func _far_fade(d: float) -> float:
	return smoothstep(DIST_MAX - 1.0, DIST_MAX - 30.0, d)


## Data tracks: which mesh chunks lie close enough to the road for the 4 m mesh (row-major).
var _fine: Array[bool] = []


func _fine_chunks() -> Array[bool]:
	if not _fine.is_empty():
		return _fine
	var cxn := int(ceil(float(nx - 1) / CHUNK))
	var czn := int(ceil(float(nz - 1) / CHUNK))
	for cz in czn:
		for cx in cxn:
			var x0 := cx * CHUNK
			var z0 := cz * CHUNK
			var w := mini(CHUNK, nx - 1 - x0)
			var h := mini(CHUNK, nz - 1 - z0)
			var dmin := 1e9
			for fz: float in [0.0, 0.5, 1.0]:
				for fx: float in [0.0, 0.5, 1.0]:
					dmin = minf(dmin, _dist_raw(origin.x + (x0 + w * fx) * CELL, origin.y + (z0 + h * fz) * CELL))
			_fine.append(dmin < FINE_DIST)
	return _fine


## A DEM-grid image (10 m cells) scaled to the inner 4 m grid.
func _upsample(src: Image) -> Image:
	var k := _dem_c / CELL
	var cx0 := int(floor((origin.x - _dem_o.x) / _dem_c))
	var cz0 := int(floor((origin.y - _dem_o.y) / _dem_c))
	# an even number of source cells keeps the scale exactly 2.5
	var sw := int(ceil((nx - 1) / k)) + 2
	var sh := int(ceil((nz - 1) / k)) + 2
	sw += sw % 2
	sh += sh % 2
	var img := src.get_region(Rect2i(cx0, cz0, sw, sh))
	img.resize(int(sw * k), int(sh * k), Image.INTERPOLATE_BILINEAR)
	return img.get_region(Rect2i(0, 0, nx, nz))


## Real terrain height (relative to the start line), bilinear on the 10 m grid.
func dem_at(x: float, z: float) -> float:
	var fx := clampf((x - _dem_o.x) / _dem_c, 0.0, _dem_n.x - 1.001)
	var fz := clampf((z - _dem_o.y) / _dem_c, 0.0, _dem_n.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * _dem_n.x + ix
	return lerpf(lerpf(_dem[k], _dem[k + 1], tx), lerpf(_dem[k + _dem_n.x], _dem[k + _dem_n.x + 1], tx), tz)


## Land cover (forest, field, village) 0..1, bilinear.
func cover_at(x: float, z: float) -> Vector3:
	var fx := clampf((x - _dem_o.x) / _dem_c, 0.0, _dem_n.x - 1.001)
	var fz := clampf((z - _dem_o.y) / _dem_c, 0.0, _dem_n.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := (iz * _dem_n.x + ix) * 3
	var k2 := k + _dem_n.x * 3
	var out := Vector3.ZERO
	for c in 3:
		out[c] = lerpf(lerpf(_cover[k + c], _cover[k + 3 + c], tx), lerpf(_cover[k2 + c], _cover[k2 + 3 + c], tx), tz) / 255.0
	return out


## Exact distance to the centreline and road height at the projection, for grid nodes near the road
## (the corridor has to match the 2 m road ribbon, a coarse field would let the ground poke through).
func _stamp_near() -> void:
	_near_d.resize(nx * nz)
	_near_d.fill(1e9)
	_near_h.resize(nx * nz)
	var n: int = track.sample_count()
	var reach := int(ceil(NEAR_R / CELL)) + 1
	for i in n:
		if i % 64 == 0:
			await Game.load_tick(0.25 + 0.15 * i / n)
		var a: Vector3 = track.samples[i]
		var b: Vector3 = track.samples[(i + 1) % n]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var len2 := maxf(ab.length_squared(), 1e-6)
		var cx := int(round((a.x - origin.x) / CELL))
		var cz := int(round((a.z - origin.y) / CELL))
		for dz in range(-reach, reach + 1):
			var gz := cz + dz
			if gz < 0 or gz >= nz:
				continue
			var wz := origin.y + gz * CELL - a.z
			for dx in range(-reach, reach + 1):
				var gx := cx + dx
				if gx < 0 or gx >= nx:
					continue
				var wx := origin.x + gx * CELL - a.x
				var u := clampf((wx * ab.x + wz * ab.y) / len2, 0.0, 1.0)
				var ex := wx - ab.x * u
				var ez := wz - ab.y * u
				var d := sqrt(ex * ex + ez * ez)
				var k := gz * nx + gx
				if d < _near_d[k]:
					_near_d[k] = d
					_near_h[k] = lerpf(a.y, b.y, u)
					if banked:
						# banked corner: the ground follows the tilted road plane
						var r: Vector3 = track.rights[i]
						_near_h[k] += track.ground_bank_y(i, ex * r.x + ez * r.z)


func _road_h_raw(x: float, z: float) -> float:
	var fx := clampf((x - _dorigin.x) / DIST_CELL, 0.0, _dn.x - 1.001)
	var fz := clampf((z - _dorigin.y) / DIST_CELL, 0.0, _dn.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * _dn.x + ix
	return lerpf(lerpf(_rh[k], _rh[k + 1], tx), lerpf(_rh[k + _dn.x], _rh[k + _dn.x + 1], tx), tz)


## Real ground, pulled onto the road level in the corridor (cuttings and embankments where the
## hillside lies higher or lower than the road).
func _height_big(x: float, z: float, d: float, k: int, dem: float) -> float:
	var rh: float = _near_h[k] if _near_d[k] < NEAR_R else _road_h_raw(x, z)
	var base := dem + _n_small.get_noise_2d(x, z) * 0.4 * _far_fade(d)
	var bw := 26.0 + 30.0 * (_n_blend.get_noise_2d(x, z) * 0.5 + 0.5)
	return lerpf(rh, base, smoothstep(flat_r, flat_r + bw, d))


static func _setup_noise(n: FastNoiseLite, seed_value: int, freq: float, octaves: int) -> void:
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves


## Coarse distance-to-centreline field (stamped from the track samples, bilinear lookups).
func _build_distance_field() -> void:
	_dorigin = origin
	_dn = Vector2i(int(ceil((nx - 1) * CELL / DIST_CELL)) + 1, int(ceil((nz - 1) * CELL / DIST_CELL)) + 1)
	_dist.resize(_dn.x * _dn.y)
	_dist.fill(DIST_MAX)
	if big:
		_rh.resize(_dn.x * _dn.y)
		_rh.fill(0.0)
	var reach := int(ceil(DIST_MAX / DIST_CELL))
	var n: int = track.sample_count()
	# every 4 m (6 m on the long data tracks: within NEAR_R the exact field takes over anyway)
	for i in range(0, n, 3 if big else 2):
		if i % 60 == 0:
			await Game.load_tick(0.25 * i / n)
		var s: Vector3 = track.samples[i]
		var tg: Vector3 = track.tangents[i]
		var grade := tg.y / maxf(Vector2(tg.x, tg.z).length(), 0.1)
		var fl := Vector2(tg.x, tg.z).normalized()
		var cx := int(round((s.x - _dorigin.x) / DIST_CELL))
		var cz := int(round((s.z - _dorigin.y) / DIST_CELL))
		for dz in range(-reach, reach + 1):
			var gz := cz + dz
			if gz < 0 or gz >= _dn.y:
				continue
			var wz := _dorigin.y + gz * DIST_CELL - s.z
			for dx in range(-reach, reach + 1):
				var gx := cx + dx
				if gx < 0 or gx >= _dn.x:
					continue
				var wx := _dorigin.x + gx * DIST_CELL - s.x
				var d := sqrt(wx * wx + wz * wz)
				var k := gz * _dn.x + gx
				if d < _dist[k]:
					_dist[k] = d
					if big:
						_rh[k] = s.y + clampf(wx * fl.x + wz * fl.y, -3.0, 3.0) * grade
						if banked:
							_rh[k] += track.ground_bank_y(i, wx * track.rights[i].x + wz * track.rights[i].z)


## Distance from (x, z) to the track centreline (capped at DIST_MAX).
func _dist_raw(x: float, z: float) -> float:
	var fx := (x - _dorigin.x) / DIST_CELL
	var fz := (z - _dorigin.y) / DIST_CELL
	if fx < 0.0 or fz < 0.0 or fx >= _dn.x - 1 or fz >= _dn.y - 1:
		return DIST_MAX
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * _dn.x + ix
	var a := lerpf(_dist[k], _dist[k + 1], tx)
	var c := lerpf(_dist[k + _dn.x], _dist[k + _dn.x + 1], tx)
	return lerpf(a, c, tz)


func distance_to_road(x: float, z: float) -> float:
	return _dist_raw(x, z)


## Terrain height before flattening; d = distance to the centreline.
func _height_fn(x: float, z: float, d: float) -> float:
	var h := _base_height(x, z)
	if track_id == "playground":
		# the whole pad is flat; green hills start a few metres outside its barrier
		var sd := pad_sd(x, z)
		var pbw := 30.0 + 30.0 * (_n_blend.get_noise_2d(x, z) * 0.5 + 0.5)
		return h * smoothstep(6.0, 6.0 + pbw, sd) + _n_small.get_noise_2d(x, z) * 0.55 * smoothstep(6.0, 16.0, sd)
	var fr := _flat_radius(x, z)
	var bw := 26.0 + 30.0 * (_n_blend.get_noise_2d(x, z) * 0.5 + 0.5)
	var blend := smoothstep(fr, fr + bw, d)
	var bumps := _n_small.get_noise_2d(x, z) * 0.55 * smoothstep(fr, fr + 10.0, d)
	if Game.is_city(track_id):
		bumps = 0.0
	return h * blend + bumps


## Distance from the centreline that stays perfectly flat (the whole concrete apron at the harbor).
func _flat_radius(x: float, z: float) -> float:
	if track_id == "harbor":
		return float(track.wall_base) + 33.0 + _n_blend.get_noise_2d(x, z) * 10.0
	return flat_r


## Playground pad: a rounded rectangle around the figure eight; signed distance (negative inside).
const PAD_MARGIN := 70.0
const PAD_CORNER := 45.0


## Playground grass islands: one inside each loop of the figure eight, one in each pad corner.
func _setup_islands() -> void:
	islands.clear()
	_setup_driveways()
	var tc: Vector2 = track.bounds.get_center()
	for side: float in [-1.0, 1.0]:
		var sum := Vector2.ZERO
		var cnt := 0
		for p in track.samples:
			if (p.x - tc.x) * side > 0.0:
				sum += Vector2(p.x, p.z)
				cnt += 1
		var c := sum / maxf(cnt, 1)
		var md := 1e9
		for p in track.samples:
			md = minf(md, c.distance_to(Vector2(p.x, p.z)))
		var r := md - float(track.half_w) - 8.0
		if r > 6.0:
			islands.append([c, r])
	var pr := pad_rect()
	var inset := PAD_CORNER * 0.55 + 16.0
	for cx: float in [pr.position.x + inset, pr.end.x - inset]:
		# the pit lane runs along the north edge (small z): only the south corners get islands
		islands.append([Vector2(cx, pr.end.y - inset), 15.0])
	track.ground_fn = func(pos: Vector3) -> Array:
		if pad_grass(pos.x, pos.z) > 0.5:
			return [0.62 * (1.0 - 0.12 * float(track.wetness)), "grass"]
		return []


## 1 on a grass island or the grass belt around the figure eight, 0 on the asphalt (slightly wavy edge).
func pad_grass(x: float, z: float) -> float:
	var g := 0.0
	for isl in islands:
		var d := Vector2(x, z).distance_to(isl[0]) + _n_small.get_noise_2d(x * 2.0, z * 2.0) * 1.2
		g = maxf(g, 1.0 - smoothstep(float(isl[1]) - 1.0, float(isl[1]) + 0.6, d))
	return maxf(g, _grass_belt(x, z))


## Playground: a 10 m grass belt along both sides of the figure eight (1.5 m of asphalt left beside the
## road), with two driveways through it – north of the east loop (towards the pit lane) and south
## of the west loop.
const BELT_GAP := 1.5
const BELT_WIDTH := 10.0
const BELT_DRIVEWAY := 8.0     # half width of a driveway


func _grass_belt(x: float, z: float) -> float:
	var hw: float = float(track.half_w)
	var d := _dist_raw(x, z)
	var outer := hw + BELT_GAP + BELT_WIDTH + _n_small.get_noise_2d(x * 1.5, z * 1.5) * 0.8
	var g := smoothstep(hw + BELT_GAP - 0.4, hw + BELT_GAP + 0.4, d) * (1.0 - smoothstep(outer - 0.5, outer + 0.5, d))
	if g <= 0.0:
		return 0.0
	# driveways: straight through the belt, outside the loops' northernmost / southernmost point
	for dw in _driveways:
		var p: Vector2 = dw[0]
		if (z - p.y) * float(dw[1]) > hw * 0.5:
			var k := 1.0 - smoothstep(BELT_DRIVEWAY - 0.5, BELT_DRIVEWAY + 0.5, absf(x - p.x))
			g *= 1.0 - k
	return g


## [point on the centreline, direction (-1 north, +1 south)] of the two driveways.
var _driveways: Array = []


func _setup_driveways() -> void:
	var tc: Vector2 = track.bounds.get_center()
	var north := Vector2(0, 1e9)
	var south := Vector2(0, -1e9)
	for s in track.samples:
		if s.x > tc.x and s.z < north.y:
			north = Vector2(s.x, s.z)
		if s.x < tc.x and s.z > south.y:
			south = Vector2(s.x, s.z)
	_driveways = [[north, -1.0], [south, 1.0]]


func pad_rect() -> Rect2:
	return track.bounds.grow(PAD_MARGIN)


func pad_sd(x: float, z: float) -> float:
	var r := pad_rect()
	var c := r.get_center()
	var h := r.size * 0.5 - Vector2(PAD_CORNER, PAD_CORNER)
	var q := Vector2(absf(x - c.x), absf(z - c.y)) - h
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - PAD_CORNER


## Hills, ridges and mountains without the road corridor.
func _base_height(x: float, z: float) -> float:
	var r := Vector2(x, z).distance_to(_center)
	if Game.is_city(track_id):
		return 0.0       # the city is flat; the skyline closes the view
	if track_id == "playground":
		var hills := _n_large.get_noise_2d(x, z) * 12.0 + 8.0 + _n_mid.get_noise_2d(x, z) * 5.0
		hills += smoothstep(550.0, 1100.0, r) * (50.0 + 110.0 * (_n_large.get_noise_2d(x * 0.35, z * 0.35) * 0.5 + 0.5))
		return maxf(hills, 0.0)
	if track_id == "harbor":
		if z > _quay_z - 1.0:
			return -4.5
		var north := smoothstep(float(track.bounds.position.y) + 10.0, float(track.bounds.position.y) - 240.0, z)
		var land := _n_large.get_noise_2d(x, z) * 16.0 + 14.0 + _n_mid.get_noise_2d(x, z) * 6.0
		var berms := maxf(_n_mid.get_noise_2d(x * 1.3, z * 1.3), 0.0) * 7.0
		var hills := north * land + (1.0 - north) * berms
		hills += smoothstep(500.0, 1100.0, r) * (40.0 + 90.0 * (_n_large.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5)) * north
		# keep the waterfront flat
		return hills * smoothstep(_quay_z - 12.0, _quay_z - 70.0, z)
	var h := _n_large.get_noise_2d(x, z) * 24.0 + _n_mid.get_noise_2d(x, z) * 8.0
	var ridge := _n_ridge.get_noise_2d(x, z)
	h += maxf(ridge, 0.0) * maxf(ridge, 0.0) * 14.0
	h = maxf(h, -13.0)
	# the valley is surrounded by mountains
	var m := smoothstep(420.0, 1050.0, r)
	h += m * (70.0 + 170.0 * (_n_large.get_noise_2d(x * 0.35 + 900.0, z * 0.35) * 0.5 + 0.5))
	return h


## Ground colour weights: R = concrete, G = dirt, B = forest floor, A = meadow (dry grass / flowers).
func _splat_fn(x: float, z: float, d: float) -> Color:
	var paved := 0.0
	var dirt := 0.0
	if track_id == "playground":
		var sd := pad_sd(x, z)
		var gr := pad_grass(x, z)
		paved = (1.0 - smoothstep(-1.0, 1.5, sd)) * (1.0 - gr)
		dirt = smoothstep(0.5, 2.0, sd) * (1.0 - smoothstep(3.0, 8.0, sd)) * 0.7
	elif Game.is_city(track_id):
		paved = 1.0      # pavements and plazas everywhere (the parks paint their own grass)
	elif track_id == "harbor":
		var apron := float(track.wall_base) + 30.0 + _n_blend.get_noise_2d(x, z) * 10.0
		paved = 1.0 - smoothstep(apron - 4.0, apron + 3.0, d)
		if z > _quay_z - 34.0:
			paved = 1.0
		dirt = smoothstep(apron - 2.0, apron + 2.0, d) * (1.0 - smoothstep(apron + 2.0, apron + 9.0, d)) * 0.8
	else:
		# a narrow strip of worn gravel right behind the barrier, grass on the run-off
		var wb := float(track.wall_base)
		dirt = smoothstep(wb - 1.0, wb, d) * (1.0 - smoothstep(wb + 0.8, wb + 2.8, d)) * 0.7
	var forest := forest_density(x, z, d) * (1.0 - paved)
	var mn := _n_meadow.get_noise_2d(x, z) * 0.9 + 0.2
	if big:
		# fields: dry, patchy grass; the rest of the open land is meadow (the patches fade out where
		# the plain far ground of _generate_big takes over)
		mn = lerpf(0.3, mn, _far_fade(d)) + cover_at(x, z).y * 0.45
	var meadow := clampf(mn, 0.0, 1.0) * (1.0 - forest) * (1.0 - paved)
	return Color(paved, dirt, clampf(forest * 1.2, 0.0, 1.0), meadow)


## How densely forested a spot is (0..1). Shared with the scenery so trees and forest floor match.
func forest_density(x: float, z: float, d := -1.0) -> float:
	if d < 0.0:
		d = _dist_raw(x, z)
	var n := _n_forest.get_noise_2d(x, z) * 0.5 + 0.5
	var f := smoothstep(0.34, 0.52, n)
	if big:
		# the real woods (land cover), with ragged edges and a clearing behind the barriers
		var cv := cover_at(x, z)
		f = smoothstep(0.3, 0.62, cv.x * lerpf(1.0, 0.7 + 0.6 * n, _far_fade(d)) - cv.z * 0.8)
		return f * smoothstep(float(track.wall_base) + 1.5, float(track.wall_base) + 4.0, d)
	if Game.is_city(track_id):
		return 0.0       # streets and buildings; the city places its own street trees
	if track_id == "playground":
		return f * smoothstep(14.0, 40.0, pad_sd(x, z))
	if track_id == "harbor":
		var apron := float(track.wall_base) + 36.0
		f *= smoothstep(apron, apron + 20.0, d)
		f *= smoothstep(_quay_z - 60.0, _quay_z - 140.0, z)
	else:
		# a dense wall of trees along the road, with some open meadows further out
		f = maxf(f, 1.0 - smoothstep(float(track.wall_base) + 16.0, float(track.wall_base) + 40.0, d))
		f *= smoothstep(float(track.wall_base) + 1.5, float(track.wall_base) + 4.0, d)
	return f


## Flattens a round pad (for buildings) to its average height with a soft edge.
## Levels the ground around `pos` to the height `target` (pit lane, grandstands, campsites): fully
## within `radius`, blended out over `falloff`. Unlike flatten() it may also touch the road corridor
## (the target is the road's own height there).
func level_to(pos: Vector3, radius: float, falloff: float, target: float) -> void:
	var r_cells := int(ceil((radius + falloff) / CELL))
	var cx := int(round((pos.x - origin.x) / CELL))
	var cz := int(round((pos.z - origin.y) / CELL))
	for dz in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			var ix := cx + dx
			var iz := cz + dz
			if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
				continue
			var w := Vector2(origin.x + ix * CELL - pos.x, origin.y + iz * CELL - pos.z).length()
			var k := 1.0 - smoothstep(radius, radius + falloff, w)
			if k <= 0.0:
				continue
			var idx := iz * nx + ix
			heights[idx] = lerpf(heights[idx], target, k)


func flatten(pos: Vector3, radius: float, falloff := 8.0) -> float:
	var target := 0.0
	var count := 0
	var r_cells := int(ceil((radius + falloff) / CELL))
	var cx := int(round((pos.x - origin.x) / CELL))
	var cz := int(round((pos.z - origin.y) / CELL))
	for dz in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			var ix := cx + dx
			var iz := cz + dz
			if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
				continue
			var w := Vector2(origin.x + ix * CELL - pos.x, origin.y + iz * CELL - pos.z).length()
			if w <= radius:
				target += heights[iz * nx + ix]
				count += 1
	if count == 0:
		return height_at(pos.x, pos.z)
	target /= float(count)
	for dz in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			var ix := cx + dx
			var iz := cz + dz
			if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
				continue
			var wx := origin.x + ix * CELL
			var wz := origin.y + iz * CELL
			var w := Vector2(wx - pos.x, wz - pos.z).length()
			var k := 1.0 - smoothstep(radius, radius + falloff, w)
			# never touch the road corridor
			var dr := _dist_raw(wx, wz)
			k *= smoothstep(flat_r, flat_r + 6.0, dr)
			var idx := iz * nx + ix
			heights[idx] = lerpf(heights[idx], target, k)
	return target


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
## Height of the rendered surface (same triangle split as the mesh).
func height_at(x: float, z: float) -> float:
	if not (is_finite(x) and is_finite(z)):
		return 0.0
	var fx := (x - origin.x) / CELL
	var fz := (z - origin.y) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= nx - 1 or fz >= nz - 1:
		return outer_height(x, z)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * nx + ix
	var h00 := heights[k]
	var h10 := heights[k + 1]
	var h01 := heights[k + nx]
	var h11 := heights[k + nx + 1]
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func outer_height(x: float, z: float) -> float:
	if big:
		return dem_at(x, z)
	return _base_height(x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := CELL
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func splat_at(x: float, z: float) -> Color:
	var ix := clampi(int(round((x - origin.x) / CELL)), 0, nx - 1)
	var iz := clampi(int(round((z - origin.y) / CELL)), 0, nz - 1)
	return splat[iz * nx + ix]


func inside(x: float, z: float) -> bool:
	return x > origin.x and z > origin.y and x < origin.x + (nx - 1) * CELL and z < origin.y + (nz - 1) * CELL


func extent() -> Rect2:
	return Rect2(origin, Vector2((nx - 1) * CELL, (nz - 1) * CELL))


## Heights as a float image (one texel per vertex) for GPU grass.
func height_image() -> Image:
	var data := heights.to_byte_array()
	return Image.create_from_data(nx, nz, false, Image.FORMAT_RF, data)


# ---------------------------------------------------------------------------
# Meshes & collision (call after all flatten() calls)
# ---------------------------------------------------------------------------
func build_meshes(wet_capable := true) -> void:
	material = TexKit.terrain_material(track_id)
	if track_id != "playground":
		var ed: Dictionary = track.edge_data()
		material.set_shader_parameter("edge_tex", ed["tex"])
		material.set_shader_parameter("edge_origin", ed["origin"])
		material.set_shader_parameter("edge_inv_size", ed["inv_size"])
		material.set_shader_parameter("trap_w", float(track.trap_w))
		material.set_shader_parameter("shoulder", 1.0)
	outer_material = material
	var cx_count := int(ceil(float(nx - 1) / CHUNK))
	var cz_count := int(ceil(float(nz - 1) / CHUNK))
	for cz in cz_count:
		await Game.load_tick(float(cz) / cz_count)
		for cx in cx_count:
			var x0 := cx * CHUNK
			var z0 := cz * CHUNK
			var w := mini(CHUNK, nx - 1 - x0)
			var h := mini(CHUNK, nz - 1 - z0)
			if not big:
				_build_chunk(x0, z0, w, h)
				continue
			# data tracks: 4 m mesh only along the road (and only up to FINE_RANGE), 16 m elsewhere
			if _fine_chunks()[cz * cx_count + cx]:
				_build_chunk(x0, z0, w, h, 1, 0.0, FINE_RANGE)
				_build_chunk(x0, z0, w, h, COARSE, FINE_RANGE, 0.0)
			elif not _in_far_block(cx, cz, cx_count, cz_count):
				_build_chunk(x0, z0, w, h, COARSE)
	if big:
		# far from the road: one 16 m mesh per 4x4 chunks (fewer nodes to cull every frame)
		for bz in range(0, cz_count, FAR_BLOCK):
			await Game.load_tick()
			for bx in range(0, cx_count, FAR_BLOCK):
				if _far_block_ok(bx, bz, cx_count, cz_count):
					var x0 := bx * CHUNK
					var z0 := bz * CHUNK
					_build_chunk(x0, z0, mini(CHUNK * FAR_BLOCK, nx - 1 - x0), mini(CHUNK * FAR_BLOCK, nz - 1 - z0), COARSE)
	await Game.load_tick()
	_build_outer()
	await Game.load_tick()
	await _build_collision()


## Data tracks: a block of FAR_BLOCK x FAR_BLOCK chunks without any 4 m chunk is built as one mesh.
const FAR_BLOCK := 4


func _far_block_ok(bx: int, bz: int, cx_count: int, cz_count: int) -> bool:
	for cz in range(bz, mini(bz + FAR_BLOCK, cz_count)):
		for cx in range(bx, mini(bx + FAR_BLOCK, cx_count)):
			if _fine_chunks()[cz * cx_count + cx]:
				return false
	return true


func _in_far_block(cx: int, cz: int, cx_count: int, cz_count: int) -> bool:
	return big and _far_block_ok(cx - cx % FAR_BLOCK, cz - cz % FAR_BLOCK, cx_count, cz_count)


func _vertex_normal(ix: int, iz: int, e := 1) -> Vector3:
	var l := heights[iz * nx + maxi(ix - e, 0)]
	var r := heights[iz * nx + mini(ix + e, nx - 1)]
	var d := heights[maxi(iz - e, 0) * nx + ix]
	var u := heights[mini(iz + e, nz - 1) * nx + ix]
	return Vector3(l - r, 2.0 * CELL * e, d - u).normalized()


## Height of a coarse-mesh vertex: near the road the lowest of the nodes around it, so the 16 m
## triangles never cover the road in a cutting.
func _coarse_height(ix: int, iz: int) -> float:
	var k := iz * nx + ix
	if _dist_raw(origin.x + ix * CELL, origin.y + iz * CELL) > 45.0:
		return heights[k]
	var h := heights[k]
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var jx := clampi(ix + dx, 0, nx - 1)
			var jz := clampi(iz + dz, 0, nz - 1)
			h = minf(h, heights[jz * nx + jx])
	return h


func _build_chunk(x0: int, z0: int, w: int, h: int, stride := 1, range_begin := 0.0, range_end := 0.0) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# vertex columns / rows (the last one always on the chunk border)
	var xs: Array[int] = []
	var zs: Array[int] = []
	for i in range(0, w, stride):
		xs.append(x0 + i)
	xs.append(x0 + w)
	for i in range(0, h, stride):
		zs.append(z0 + i)
	zs.append(z0 + h)
	var stride_v := xs.size()
	var hv := PackedFloat32Array()
	for iz in zs:
		for ix in xs:
			var k := iz * nx + ix
			var y := heights[k] if stride == 1 else _coarse_height(ix, iz)
			hv.append(y)
			verts.append(Vector3(origin.x + ix * CELL, y, origin.y + iz * CELL))
			norms.append(_vertex_normal(ix, iz, stride))
			cols.append(splat[k])
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			var a := j * stride_v + i
			var b := a + 1
			var c := a + stride_v
			var d := c + 1
			# triangles (00, 10, 11) and (00, 11, 01) – clockwise seen from above (Godot front faces)
			idx.append_array(PackedInt32Array([a, b, d, a, d, c]))
	# skirts hide cracks: towards the coarse outer ring, and on data tracks between 4 m and 16 m chunks
	var border := [[z0 == 0 or big, true], [z0 + h == nz - 1 or big, true], [x0 == 0 or big, false], [x0 + w == nx - 1 or big, false]]
	for side in 4:
		if not border[side][0]:
			continue
		var line: Array = []
		if side == 0 or side == 1:
			var row := 0 if side == 0 else zs.size() - 1
			for i in xs.size():
				line.append(Vector2i(i, row))
		else:
			var colm := 0 if side == 2 else xs.size() - 1
			for j in zs.size():
				line.append(Vector2i(colm, j))
		for q in range(line.size() - 1):
			var base := verts.size()
			for p: Vector2i in [line[q], line[q + 1]]:
				var vi := p.y * stride_v + p.x
				var top: Vector3 = verts[vi]
				verts.append(top)
				verts.append(top - Vector3(0, 6.0, 0))
				norms.append(Vector3.UP)
				norms.append(Vector3.UP)
				cols.append(cols[vi])
				cols.append(cols[vi])
			idx.append_array(PackedInt32Array([base, base + 1, base + 3, base, base + 3, base + 2]))
			idx.append_array(PackedInt32Array([base, base + 3, base + 1, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "TerrainChunk"
	mi.set_meta("chunk", [x0, z0, w, h, stride, range_begin, range_end])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if range_begin > 0.0 or range_end > 0.0:
		mi.visibility_range_begin = range_begin
		mi.visibility_range_end = range_end
	add_child(mi)


## Coarse terrain around the inner grid out to the horizon (mountains / sea floor).
func _build_outer() -> void:
	var ext := extent()
	var oc := BIG_OUTER_CELL if big else OUTER_CELL
	var oh := BIG_OUTER_HALF if big else OUTER_HALF
	var o := Vector2(floor((_center.x - oh - origin.x) / oc) * oc + origin.x,
		floor((_center.y - oh - origin.y) / oc) * oc + origin.y)
	var n := int(ceil(oh * 2.0 / oc)) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for iz in n:
		for ix in n:
			var x := o.x + ix * oc
			var z := o.y + iz * oc
			hs[iz * n + ix] = height_at(x, z) if ext.has_point(Vector2(x, z)) or _on_rect_edge(ext, x, z) else outer_height(x, z)
	for iz in n:
		for ix in n:
			var x := o.x + ix * oc
			var z := o.y + iz * oc
			verts.append(Vector3(x, hs[iz * n + ix], z))
			var l := hs[iz * n + maxi(ix - 1, 0)]
			var r := hs[iz * n + mini(ix + 1, n - 1)]
			var d := hs[maxi(iz - 1, 0) * n + ix]
			var u := hs[mini(iz + 1, n - 1) * n + ix]
			norms.append(Vector3(l - r, 2.0 * oc, d - u).normalized())
			var f := forest_density(x, z, DIST_MAX)
			var paved := 1.0 if z > _quay_z - 34.0 and track_id == "harbor" else 0.0
			cols.append(Color(paved, 0.0, clampf(f * 1.3, 0.0, 1.0), 0.3 * (1.0 - f)))
	var idx := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var x0 := o.x + i * oc
			var z0 := o.y + j * oc
			# skip cells covered by the inner grid
			if x0 >= ext.position.x - 0.1 and z0 >= ext.position.y - 0.1 and x0 + oc <= ext.end.x + 0.1 and z0 + oc <= ext.end.y + 0.1:
				continue
			var a := j * n + i
			idx.append_array(PackedInt32Array([a, a + 1, a + n + 1, a, a + n + 1, a + n]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, outer_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "TerrainOuter"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


static func _on_rect_edge(r: Rect2, x: float, z: float) -> bool:
	var inside_x := x >= r.position.x - 0.1 and x <= r.end.x + 0.1
	var inside_z := z >= r.position.y - 0.1 and z <= r.end.y + 0.1
	return inside_x and inside_z


## The editor changed heights in the vertex rectangle ix0..ix1 x iz0..iz1: rebuild the meshes there.
func rebuild_region(ix0: int, iz0: int, ix1: int, iz1: int) -> void:
	for c in get_children():
		if not (c is MeshInstance3D) or not c.has_meta("chunk"):
			continue
		var m: Array = c.get_meta("chunk")
		var x0: int = m[0]
		var z0: int = m[1]
		if x0 > ix1 + 1 or z0 > iz1 + 1 or x0 + int(m[2]) < ix0 - 1 or z0 + int(m[3]) < iz0 - 1:
			continue
		remove_child(c)
		c.queue_free()
		_build_chunk(x0, z0, m[2], m[3], m[4], m[5], m[6])
	heights_changed.emit(ix0, iz0, ix1, iz1)


## The physics ground after editing (once a stroke is done: it copies the whole grid).
func refresh_collision() -> void:
	if _hshape == null:
		return
	var data := PackedFloat32Array()
	data.resize(nx * nz)
	for i in nx * nz:
		data[i] = heights[i] / CELL
	_hshape.map_data = data


signal heights_changed(ix0: int, iz0: int, ix1: int, iz1: int)
var _hshape: HeightMapShape3D


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "ground")
	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	var data := PackedFloat32Array()
	data.resize(nx * nz)
	for i in nx * nz:
		if i % 262144 == 0:
			await Game.load_tick()
		data[i] = heights[i] / CELL
	shape.map_data = data
	_hshape = shape
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# the height map is centred on its node; uniform scale = cell size
	cs.position = Vector3(origin.x + (nx - 1) * CELL * 0.5, 0.0, origin.y + (nz - 1) * CELL * 0.5)
	cs.scale = Vector3(CELL, CELL, CELL)
	body.add_child(cs)
	add_child(body)
