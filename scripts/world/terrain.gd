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
var _quay_z := 1e9


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------
func generate(p_track: Node3D) -> void:
	track = p_track
	track_id = track.track_id
	var seed_base := 1234 if track_id == "ridge" else 5678
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
	origin = Vector2(floor((b.position.x - MARGIN) / 24.0) * 24.0, floor((b.position.y - MARGIN) / 24.0) * 24.0)
	var end := Vector2(ceil((b.end.x + MARGIN) / 24.0) * 24.0, ceil((b.end.y + MARGIN) / 24.0) * 24.0)
	nx = int(round((end.x - origin.x) / CELL)) + 1
	nz = int(round((end.y - origin.y) / CELL)) + 1
	_build_distance_field()
	heights.resize(nx * nz)
	splat.resize(nx * nz)
	for iz in nz:
		var z := origin.y + iz * CELL
		for ix in nx:
			var x := origin.x + ix * CELL
			var d := _dist_raw(x, z)
			heights[iz * nx + ix] = _height_fn(x, z, d)
			splat[iz * nx + ix] = _splat_fn(x, z, d)


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
	var reach := int(ceil(DIST_MAX / DIST_CELL))
	var n: int = track.sample_count()
	for i in range(0, n, 2):
		var s: Vector3 = track.samples[i]
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
	var fr := _flat_radius(x, z)
	var bw := 26.0 + 30.0 * (_n_blend.get_noise_2d(x, z) * 0.5 + 0.5)
	var blend := smoothstep(fr, fr + bw, d)
	var bumps := _n_small.get_noise_2d(x, z) * 0.55 * smoothstep(fr, fr + 10.0, d)
	return h * blend + bumps


## Distance from the centreline that stays perfectly flat (the whole concrete apron at the harbor).
func _flat_radius(x: float, z: float) -> float:
	if track_id == "harbor":
		return float(track.wall_base) + 33.0 + _n_blend.get_noise_2d(x, z) * 10.0
	return flat_r


## Hills, ridges and mountains without the road corridor.
func _base_height(x: float, z: float) -> float:
	var r := Vector2(x, z).distance_to(_center)
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
	if track_id == "harbor":
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
	var meadow := clampf(_n_meadow.get_noise_2d(x, z) * 0.9 + 0.2, 0.0, 1.0) * (1.0 - forest) * (1.0 - paved)
	return Color(paved, dirt, clampf(forest * 1.2, 0.0, 1.0), meadow)


## How densely forested a spot is (0..1). Shared with the scenery so trees and forest floor match.
func forest_density(x: float, z: float, d := -1.0) -> float:
	if d < 0.0:
		d = _dist_raw(x, z)
	var n := _n_forest.get_noise_2d(x, z) * 0.5 + 0.5
	var f := smoothstep(0.34, 0.52, n)
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
	outer_material = material
	var cx_count := int(ceil(float(nx - 1) / CHUNK))
	var cz_count := int(ceil(float(nz - 1) / CHUNK))
	for cz in cz_count:
		for cx in cx_count:
			_build_chunk(cx * CHUNK, cz * CHUNK, mini(CHUNK, nx - 1 - cx * CHUNK), mini(CHUNK, nz - 1 - cz * CHUNK))
	_build_outer()
	_build_collision()


func _vertex_normal(ix: int, iz: int) -> Vector3:
	var l := heights[iz * nx + maxi(ix - 1, 0)]
	var r := heights[iz * nx + mini(ix + 1, nx - 1)]
	var d := heights[maxi(iz - 1, 0) * nx + ix]
	var u := heights[mini(iz + 1, nz - 1) * nx + ix]
	return Vector3(l - r, 2.0 * CELL, d - u).normalized()


func _build_chunk(x0: int, z0: int, w: int, h: int) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var stride := w + 1
	for iz in range(z0, z0 + h + 1):
		for ix in range(x0, x0 + w + 1):
			var k := iz * nx + ix
			verts.append(Vector3(origin.x + ix * CELL, heights[k], origin.y + iz * CELL))
			norms.append(_vertex_normal(ix, iz))
			cols.append(splat[k])
	for j in h:
		for i in w:
			var a := j * stride + i
			var b := a + 1
			var c := a + stride
			var d := c + 1
			# triangles (00, 10, 11) and (00, 11, 01) – clockwise seen from above (Godot front faces)
			idx.append_array(PackedInt32Array([a, b, d, a, d, c]))
	# skirts on the outer border of the inner grid hide cracks towards the coarse outer ring
	var border := [[z0 == 0, true], [z0 + h == nz - 1, true], [x0 == 0, false], [x0 + w == nx - 1, false]]
	for side in 4:
		if not border[side][0]:
			continue
		var line: Array = []
		if side == 0 or side == 1:
			var zz := z0 if side == 0 else z0 + h
			for ix in range(x0, x0 + w + 1):
				line.append(Vector2i(ix, zz))
		else:
			var xx := x0 if side == 2 else x0 + w
			for iz in range(z0, z0 + h + 1):
				line.append(Vector2i(xx, iz))
		for q in range(line.size() - 1):
			var p0: Vector2i = line[q]
			var p1: Vector2i = line[q + 1]
			var base := verts.size()
			for p: Vector2i in [p0, p1]:
				var k2 := p.y * nx + p.x
				var top := Vector3(origin.x + p.x * CELL, heights[k2], origin.y + p.y * CELL)
				verts.append(top)
				verts.append(top - Vector3(0, 6.0, 0))
				norms.append(Vector3.UP)
				norms.append(Vector3.UP)
				cols.append(splat[k2])
				cols.append(splat[k2])
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


## Coarse terrain around the inner grid out to the horizon (mountains / sea floor).
func _build_outer() -> void:
	var ext := extent()
	var o := Vector2(floor((_center.x - OUTER_HALF - origin.x) / OUTER_CELL) * OUTER_CELL + origin.x,
		floor((_center.y - OUTER_HALF - origin.y) / OUTER_CELL) * OUTER_CELL + origin.y)
	var n := int(ceil(OUTER_HALF * 2.0 / OUTER_CELL)) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for iz in n:
		for ix in n:
			var x := o.x + ix * OUTER_CELL
			var z := o.y + iz * OUTER_CELL
			hs[iz * n + ix] = height_at(x, z) if ext.has_point(Vector2(x, z)) or _on_rect_edge(ext, x, z) else outer_height(x, z)
	for iz in n:
		for ix in n:
			var x := o.x + ix * OUTER_CELL
			var z := o.y + iz * OUTER_CELL
			verts.append(Vector3(x, hs[iz * n + ix], z))
			var l := hs[iz * n + maxi(ix - 1, 0)]
			var r := hs[iz * n + mini(ix + 1, n - 1)]
			var d := hs[maxi(iz - 1, 0) * n + ix]
			var u := hs[mini(iz + 1, n - 1) * n + ix]
			norms.append(Vector3(l - r, 2.0 * OUTER_CELL, d - u).normalized())
			var f := forest_density(x, z, DIST_MAX)
			var paved := 1.0 if z > _quay_z - 34.0 and track_id == "harbor" else 0.0
			cols.append(Color(paved, 0.0, clampf(f * 1.3, 0.0, 1.0), 0.3 * (1.0 - f)))
	var idx := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var x0 := o.x + i * OUTER_CELL
			var z0 := o.y + j * OUTER_CELL
			# skip cells covered by the inner grid
			if x0 >= ext.position.x - 0.1 and z0 >= ext.position.y - 0.1 and x0 + OUTER_CELL <= ext.end.x + 0.1 and z0 + OUTER_CELL <= ext.end.y + 0.1:
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
		data[i] = heights[i] / CELL
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# the height map is centred on its node; uniform scale = cell size
	cs.position = Vector3(origin.x + (nx - 1) * CELL * 0.5, 0.0, origin.y + (nz - 1) * CELL * 0.5)
	cs.scale = Vector3(CELL, CELL, CELL)
	body.add_child(cs)
	add_child(body)
