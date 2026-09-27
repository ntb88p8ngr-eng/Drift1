extends Node3D
## Everything around the road, standing on the terrain: a dense forest (three levels of detail),
## bushes, shrubs and ferns, boulders, spectators, houses, harbor props, street lamps and the
## skyline. Lamps, windows and signs follow the time of day through set_night().

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const TreeFactory = preload("res://scripts/world/tree_factory.gd")
const Crowd = preload("res://scripts/world/crowd.gd")

const CHUNK := 48.0
const FAR_CHUNK := 192.0        # the coarse outer forest uses big chunks
const LOD0_END := 64.0          # chunk-centre distances
const LOD1_END := 160.0
const FAR_END := 2600.0
const OCC_CELL := 16.0
const SMALL_RADIUS := 10.0

static var _mesh_cache := {}

var track  # track.gd
var terrain  # terrain.gd
var night := 0.0            # 0 = day … 1 = night (lamps / window glow)
var quality := 2
var rng := RandomNumberGenerator.new()
var crowd: Node3D
var lamp_lights: Array = []

var _occupied: Array = []   # large objects: [Vector2 pos, radius]
var _occ_grid := {}         # Vector2i -> Array of [Vector2 pos, radius] (radius <= SMALL_RADIUS)
var _window_mats: Array = []     # [material, lit]
var _glow_mats: Array = []       # [material, day energy, night energy]
var _night_lights: Array = []    # lights that only exist at night: [light, energy]
var _stats := {}


func build(p_track: Node3D, p_terrain: Node3D, p_night: float, p_quality: int) -> void:
	track = p_track
	terrain = p_terrain
	night = p_night
	quality = clampi(p_quality, 0, 3)
	rng.seed = hash(track.track_id)
	var id: String = track.track_id
	_flatten_start()
	if id == "harbor":
		_build_water_and_quay()
		_build_harbor_props()
		_build_houses(5, ["office", "jp", "shop", "jp", "office"])
	else:
		_build_houses(9, ["jp", "jp", "jp", "shop", "jp", "jp", "barn", "jp", "shop"])
	_build_lamps()
	crowd = Crowd.new()
	crowd.name = "Crowd"
	add_child(crowd)
	crowd.build(track, terrain, self, quality)
	_build_forest(id)
	_build_undergrowth(id)
	_build_rocks(id)
	if id == "harbor":
		_build_skyline()
	set_night(night)


# ---------------------------------------------------------------------------
# Placement helpers
# ---------------------------------------------------------------------------
func free_at(pos: Vector3, radius: float, clearance: float) -> bool:
	var p2 := Vector2(pos.x, pos.z)
	for o in _occupied:
		var op: Vector2 = o[0]
		if op.distance_to(p2) < float(o[1]) + radius:
			return false
	var cx := int(floor(pos.x / OCC_CELL))
	var cz := int(floor(pos.z / OCC_CELL))
	var reach := int(ceil((radius + SMALL_RADIUS) / OCC_CELL))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not _occ_grid.has(key):
				continue
			for o in _occ_grid[key]:
				var op: Vector2 = o[0]
				if op.distance_to(p2) < float(o[1]) + radius:
					return false
	if terrain.distance_to_road(pos.x, pos.z) < float(track.wall_base) + clearance:
		return false
	return true


func occupy(pos: Vector3, radius: float) -> void:
	var entry := [Vector2(pos.x, pos.z), radius]
	if radius > SMALL_RADIUS:
		_occupied.append(entry)
		return
	var key := Vector2i(int(floor(pos.x / OCC_CELL)), int(floor(pos.z / OCC_CELL)))
	if not _occ_grid.has(key):
		_occ_grid[key] = []
	_occ_grid[key].append(entry)


## A point beside the track at sample index i, `extra` metres behind the wall.
func _roadside(i: int, extra: float, side: float) -> Vector3:
	var n: int = track.sample_count()
	i = (i % n + n) % n
	var off: float = track.off_left[i] if side < 0.0 else track.off_right[i]
	return track.samples[i] + track.rights[i] * side * (off + extra)


func _face_track(node: Node3D, pos: Vector3) -> void:
	var idx: int = track.nearest_index(pos)
	var target: Vector3 = track.samples[idx]
	var dir := Vector3(target.x - pos.x, 0, target.z - pos.z)
	if dir.length_squared() > 0.01:
		node.global_transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), pos)
	else:
		node.global_position = pos


## The grandstand beside the start line stands on level ground.
func _flatten_start() -> void:
	var g: Transform3D = track.gantry_xf
	for z: float in [-12.0, 0.0, 12.0]:
		terrain.flatten(g * Vector3(float(track.stand_x) + 7.0, 0, z), 9.0, 6.0)
	occupy(g * Vector3(float(track.stand_x) + 7.0, 0, 0), 17.0)


# ---------------------------------------------------------------------------
# Instancing
# ---------------------------------------------------------------------------
static func _cached(key: String, maker: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = maker.call()
	return _mesh_cache[key]


## chunks: Dictionary Vector2i -> Array of [Transform3D, Color]; one MultiMeshInstance per chunk.
func _emit_chunks(mesh: Mesh, chunks: Dictionary, range_begin: float, range_end: float, label: String, shadows: bool, size := CHUNK, shadow_only := false) -> void:
	for key in chunks.keys():
		var items: Array = chunks[key]
		if items.is_empty():
			continue
		var center := Vector3((key.x + 0.5) * size, 0.0, (key.y + 0.5) * size)
		var ysum := 0.0
		for it in items:
			ysum += (it[0] as Transform3D).origin.y
		center.y = ysum / items.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = items.size()
		for k in items.size():
			var xf: Transform3D = items[k][0]
			mm.set_instance_transform(k, Transform3D(xf.basis, xf.origin - center))
			mm.set_instance_custom_data(k, items[k][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = label
		mmi.position = center
		mmi.visibility_range_begin = range_begin
		mmi.visibility_range_end = range_end
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shadow_only:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(mmi)
		_stats[label] = int(_stats.get(label, 0)) + items.size()


static func _chunk_key(p: Vector3, size := CHUNK) -> Vector2i:
	return Vector2i(int(floor(p.x / size)), int(floor(p.z / size)))


static func _push(chunks: Dictionary, p: Vector3, item: Array, size := CHUNK) -> void:
	var key := _chunk_key(p, size)
	if not chunks.has(key):
		chunks[key] = []
	chunks[key].append(item)


# ---------------------------------------------------------------------------
# Forest
# ---------------------------------------------------------------------------
func _build_forest(id: String) -> void:
	# [kind, seed] – broadleaf trees get their autumn colours through the instance tint
	var kinds: Array = [["pine", 404], ["pine", 505], ["leaf", 101]]
	var pine_ratio := 0.62
	var autumn_ratio := 0.1
	if id == "harbor":
		kinds = [["leaf", 101], ["leaf", 202], ["pine", 404]]
		pine_ratio = 0.3
		autumn_ratio = 0.22
	var meshes: Array = []
	for k in kinds:
		var kind: String = k[0]
		var sd: int = k[1]
		meshes.append([
			_cached("tree_%s_%d_hi" % [kind, sd], func(): return TreeFactory.pine(sd, 1.0) if kind == "pine" else TreeFactory.deciduous(sd, 1.0)),
			_cached("tree_%s_%d_mid" % [kind, sd], func(): return TreeFactory.pine(sd, 0.35) if kind == "pine" else TreeFactory.deciduous(sd, 0.25)),
		])
	var far_mesh: Mesh = _cached("far_forest", func(): return TreeFactory.far_forest_mesh(404, 101))
	var chunks: Array = []
	for i in kinds.size():
		chunks.append({})
	var far_chunks := {}
	var spacing: float = [9.0, 7.6, 6.7, 6.1][quality]
	var ext: Rect2 = terrain.extent().grow(-6.0)
	var wb: float = track.wall_base
	var gz := ext.position.y
	while gz < ext.end.y:
		var gx := ext.position.x
		while gx < ext.end.x:
			var pos := Vector3(gx + rng.randf() * spacing, 0.0, gz + rng.randf() * spacing)
			gx += spacing
			var d: float = terrain.distance_to_road(pos.x, pos.z)
			if d < wb + 3.0:
				continue
			var f: float = terrain.forest_density(pos.x, pos.z, d)
			if rng.randf() > f:
				continue
			if not free_at(pos, 1.6, 3.0):
				continue
			var nrm: Vector3 = terrain.normal_at(pos.x, pos.z)
			if nrm.y < 0.62:
				continue
			pos.y = terrain.height_at(pos.x, pos.z) - 0.3
			var is_pine := rng.randf() < pine_ratio
			var options: Array = []
			for i in kinds.size():
				if (kinds[i][0] == "pine") == is_pine:
					options.append(i)
			if options.is_empty():
				options = range(kinds.size())
			var v: int = options[rng.randi() % options.size()]
			var s := rng.randf_range(0.78, 1.3) * (1.0 + smoothstep(wb + 30.0, wb + 150.0, d) * 0.15)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.88, 1.12), s))
			# lean slightly downhill
			basis = Basis(Vector3(nrm.z, 0, -nrm.x).normalized(), (1.0 - nrm.y) * 0.4) * basis if nrm.y < 0.98 else basis
			var tint := _foliage_tint(kinds[v][0] == "pine", autumn_ratio)
			var xf := Transform3D(basis, pos)
			_push(chunks[v], pos, [xf, tint])
			_push(far_chunks, pos, [xf, Color(tint.r, tint.g, tint.b, 0.75 if kinds[v][0] == "pine" else 1.0)])
		gz += spacing
	var lod1_shadow := quality >= 3
	for v in kinds.size():
		# close trees: full detail, but their shadows come from the lighter mid-detail mesh
		_emit_chunks(meshes[v][0], chunks[v], 0.0, LOD0_END, "Trees_hi", false)
		_emit_chunks(meshes[v][1], chunks[v], 0.0, LOD0_END, "Trees_shadow", true, CHUNK, true)
		_emit_chunks(meshes[v][1], chunks[v], LOD0_END, LOD1_END, "Trees_mid", lod1_shadow)
	_emit_chunks(far_mesh, far_chunks, LOD1_END, FAR_END, "Trees_far", false)
	_build_outer_forest(far_mesh, pine_ratio, autumn_ratio)


func _foliage_tint(pine: bool, autumn_ratio: float) -> Color:
	var r := rng.randf_range(0.85, 1.12)
	var g := rng.randf_range(0.86, 1.12)
	var b := rng.randf_range(0.8, 1.05)
	if not pine and rng.randf() < autumn_ratio:
		var warm := rng.randf()
		if warm < 0.45:
			return Color(1.65, 0.95, 0.42, 1.0)     # golden
		elif warm < 0.8:
			return Color(1.75, 0.62, 0.3, 1.0)      # orange
		return Color(1.8, 0.42, 0.28, 1.0)          # maple red
	if pine:
		return Color(r * 0.95, g, b * 0.95, 1.0)
	return Color(r, g, b, 1.0)


## Sparse far trees on the coarse outer terrain so the forest does not end at the grid border.
func _build_outer_forest(far_mesh: Mesh, pine_ratio: float, autumn_ratio: float) -> void:
	var inner: Rect2 = terrain.extent()
	var outer := inner.grow([260.0, 360.0, 480.0, 600.0][quality])
	var spacing := 16.0
	var chunks := {}
	var gz := outer.position.y
	while gz < outer.end.y:
		var gx := outer.position.x
		while gx < outer.end.x:
			var pos := Vector3(gx + rng.randf() * spacing, 0.0, gz + rng.randf() * spacing)
			gx += spacing
			if inner.has_point(Vector2(pos.x, pos.z)):
				continue
			var f: float = terrain.forest_density(pos.x, pos.z, 999.0)
			if rng.randf() > f * 0.85:
				continue
			pos.y = terrain.outer_height(pos.x, pos.z) - 0.4
			if pos.y < -1.0:
				continue
			var is_pine := rng.randf() < pine_ratio
			var s := rng.randf_range(0.9, 1.4)
			var tint := _foliage_tint(is_pine, autumn_ratio)
			_push(chunks, pos, [Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), pos),
				Color(tint.r, tint.g, tint.b, 0.75 if is_pine else 1.0)], FAR_CHUNK)
		gz += spacing
	_emit_chunks(far_mesh, chunks, 0.0, FAR_END, "Trees_outer", false, FAR_CHUNK)


# ---------------------------------------------------------------------------
# Bushes, shrubs, ferns
# ---------------------------------------------------------------------------
func _build_undergrowth(id: String) -> void:
	var bush: Mesh = _cached("bush_606", func(): return TreeFactory.bush(606))
	var shrub: Mesh = _cached("shrub_31", func(): return TreeFactory.shrub(31))
	var fern: Mesh = _cached("fern_5", func(): return TreeFactory.fern(5))
	var sets := [{}, {}, {}]   # bush, shrub, fern
	var spacing: float = [5.2, 4.3, 3.6, 3.2][quality]
	var ext: Rect2 = terrain.extent().grow(-4.0)
	var wb: float = track.wall_base
	var gz := ext.position.y
	while gz < ext.end.y:
		var gx := ext.position.x
		while gx < ext.end.x:
			var pos := Vector3(gx + rng.randf() * spacing, 0.0, gz + rng.randf() * spacing)
			gx += spacing
			var d: float = terrain.distance_to_road(pos.x, pos.z)
			if d < wb + 1.6 or d > 260.0:
				continue
			var f: float = terrain.forest_density(pos.x, pos.z, d)
			var sp: Color = terrain.splat_at(pos.x, pos.z)
			if sp.r > 0.4:
				continue
			# forest edges and the strip behind the barrier are the densest
			var edge := 1.0 - absf(f - 0.5) * 2.0
			var p := 0.12 + edge * 0.5 + f * 0.25
			if id == "ridge":
				p += (1.0 - smoothstep(wb + 4.0, wb + 16.0, d)) * 0.45
			else:
				p *= 0.8
			p *= 1.0 - smoothstep(120.0, 260.0, d) * 0.7
			if rng.randf() > p:
				continue
			if not free_at(pos, 0.6, 1.4):
				continue
			var nrm: Vector3 = terrain.normal_at(pos.x, pos.z)
			if nrm.y < 0.6:
				continue
			pos.y = terrain.height_at(pos.x, pos.z) - 0.08
			var kind := 0
			var roll := rng.randf()
			if f > 0.6 and roll < 0.55:
				kind = 2      # ferns under the trees
			elif roll < 0.35:
				kind = 0
			else:
				kind = 1
			var s := rng.randf_range(0.7, 1.45)
			if kind == 2:
				s = rng.randf_range(0.8, 1.5)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.8, 1.2), s))
			var tint := _foliage_tint(false, 0.06)
			if kind == 2:
				tint = Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.15), rng.randf_range(0.8, 1.0), 1.0)
			_push(sets[kind], pos, [Transform3D(basis, pos), tint])
		gz += spacing
	var far: float = [110.0, 140.0, 170.0, 200.0][quality]
	_emit_chunks(bush, sets[0], 0.0, far, "Bushes", quality >= 3)
	_emit_chunks(shrub, sets[1], 0.0, far * 0.6, "Shrubs", false)
	_emit_chunks(fern, sets[2], 0.0, far * 0.5, "Ferns", false)


# ---------------------------------------------------------------------------
# Boulders
# ---------------------------------------------------------------------------
func _build_rocks(id: String) -> void:
	var rock_mesh: Mesh = _cached("rock_11", func(): return TreeFactory.rock(11))
	var rocks := {}
	var spacing := 11.0
	var ext: Rect2 = terrain.extent().grow(-4.0)
	var wb: float = track.wall_base
	var gz := ext.position.y
	while gz < ext.end.y:
		var gx := ext.position.x
		while gx < ext.end.x:
			var pos := Vector3(gx + rng.randf() * spacing, 0.0, gz + rng.randf() * spacing)
			gx += spacing
			var d: float = terrain.distance_to_road(pos.x, pos.z)
			if d < wb + 2.5:
				continue
			var sp: Color = terrain.splat_at(pos.x, pos.z)
			if sp.r > 0.3:
				continue
			var nrm: Vector3 = terrain.normal_at(pos.x, pos.z)
			var p := 0.05 + (1.0 - nrm.y) * 1.6 + sp.b * 0.05
			if id == "harbor":
				p *= 0.5
			if rng.randf() > p:
				continue
			if not free_at(pos, 1.2, 2.0):
				continue
			pos.y = terrain.height_at(pos.x, pos.z) - 0.15
			var s := rng.randf_range(0.35, 1.2) * (1.0 + (1.0 - nrm.y) * 1.5)
			if rng.randf() < 0.08:
				s *= 2.2
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
			basis = basis.scaled(Vector3(s * rng.randf_range(0.7, 1.3), s * rng.randf_range(0.6, 1.2), s * rng.randf_range(0.7, 1.3)))
			var t := rng.randf_range(0.8, 1.15)
			_push(rocks, pos, [Transform3D(basis, pos), Color(t, t * rng.randf_range(0.95, 1.03), t * rng.randf_range(0.9, 1.0), 1.0)])
		gz += spacing
	_emit_chunks(rock_mesh, rocks, 0.0, 420.0, "Rocks", true)


# ---------------------------------------------------------------------------
# Houses
# ---------------------------------------------------------------------------
func _build_houses(count: int, styles: Array) -> void:
	var n: int = track.sample_count()
	var placed := 0
	var tries := 0
	# cluster houses into a small village around a random stretch of road
	var village := rng.randi_range(0, n - 1)
	while placed < count and tries < 500:
		tries += 1
		var i := village + rng.randi_range(-80, 80) if tries < 300 else rng.randi_range(0, n - 1)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := _roadside(i, rng.randf_range(14.0, 24.0), side)
		if not free_at(pos, 9.0, 12.0):
			continue
		var nrm: Vector3 = terrain.normal_at(pos.x, pos.z)
		if nrm.y < 0.8:
			continue
		pos.y = terrain.flatten(pos, 8.0, 7.0)
		var style: String = styles[placed % styles.size()]
		var house := _make_house(style)
		add_child(house)
		_face_track(house, pos)
		occupy(pos, 9.5)
		placed += 1


func _make_house(style: String) -> Node3D:
	var root := Node3D.new()
	root.name = "House_" + style
	var wall_cols := [Color(0.88, 0.86, 0.8), Color(0.8, 0.74, 0.62), Color(0.72, 0.76, 0.78), Color(0.9, 0.9, 0.9)]
	var roof_cols := [Color(0.18, 0.2, 0.24), Color(0.35, 0.12, 0.1), Color(0.2, 0.25, 0.3), Color(0.25, 0.22, 0.2)]
	var wall := TexKit.std(wall_cols[rng.randi() % wall_cols.size()], 0.85)
	var roof := TexKit.std(roof_cols[rng.randi() % roof_cols.size()], 0.6, 0.2)
	var wood := TexKit.std(Color(0.3, 0.2, 0.12), 0.8)
	var win := _window_material()
	# foundation reaching into the ground (covers small slopes)
	root.add_child(MeshKit.box_node(Vector3(10.5, 2.0, 10.0), TexKit.std(Color(0.42, 0.42, 0.4), 0.95), Vector3(0, -0.9, 0)))
	match style:
		"shop":
			var w := 9.0
			var d := 7.0
			var h := 3.4
			root.add_child(MeshKit.box_node(Vector3(w, h, d), wall, Vector3(0, h * 0.5, 0)))
			root.add_child(MeshKit.box_node(Vector3(w + 0.3, 0.35, d + 0.3), roof, Vector3(0, h + 0.17, 0)))
			root.add_child(MeshKit.box_node(Vector3(w * 0.8, 1.9, 0.08), win, Vector3(0, 1.3, -d * 0.5 - 0.04)))
			var awning := MeshKit.box_node(Vector3(w, 0.1, 1.6), TexKit.std(Color(0.7, 0.1, 0.12), 0.6), Vector3(0, 2.6, -d * 0.5 - 0.8))
			awning.rotation.x = -0.25
			root.add_child(awning)
			var sign_mat := _glow_material(Color(1.0, 0.55, 0.15), 0.5, 3.0)
			root.add_child(MeshKit.box_node(Vector3(w * 0.6, 0.8, 0.12), sign_mat, Vector3(0, h + 0.8, -d * 0.5 + 0.3)))
			_vending_machine(root, Vector3(w * 0.5 - 0.6, 0, -d * 0.5 - 0.6))
			_vending_machine(root, Vector3(w * 0.5 - 1.5, 0, -d * 0.5 - 0.6))
		"office":
			var w := 14.0
			var d := 10.0
			var h := 7.5
			root.add_child(MeshKit.box_node(Vector3(w, h, d), TexKit.std(Color(0.55, 0.57, 0.6), 0.7), Vector3(0, h * 0.5, 0)))
			for fl in 2:
				for k in 5:
					root.add_child(MeshKit.box_node(Vector3(2.0, 1.4, 0.08), win, Vector3(-w * 0.4 + k * w * 0.2, 1.8 + fl * 3.2, -d * 0.5 - 0.04)))
			root.add_child(MeshKit.box_node(Vector3(w + 0.4, 0.4, d + 0.4), roof, Vector3(0, h + 0.2, 0)))
		"barn":
			var w := 8.0
			var d := 12.0
			var h := 4.5
			var red := TexKit.std(Color(0.5, 0.12, 0.08), 0.9)
			root.add_child(MeshKit.box_node(Vector3(w, h, d), red, Vector3(0, h * 0.5, 0)))
			var prism := PrismMesh.new()
			prism.size = Vector3(w + 0.8, 3.0, d + 0.6)
			var r := MeshKit.mesh_instance(prism, roof)
			r.position = Vector3(0, h + 1.5, 0)
			root.add_child(r)
			root.add_child(MeshKit.box_node(Vector3(3.2, 3.4, 0.1), wood, Vector3(0, 1.7, -d * 0.5 - 0.05)))
		_:
			# Japanese-style two-storey house with gabled tiled roof, veranda and sliding door
			var w := rng.randf_range(8.0, 10.0)
			var d := rng.randf_range(7.0, 9.0)
			var h := rng.randf_range(5.2, 6.0)
			root.add_child(MeshKit.box_node(Vector3(w + 0.3, 0.5, d + 0.3), TexKit.std(Color(0.45, 0.45, 0.43), 0.9), Vector3(0, 0.25, 0)))
			root.add_child(MeshKit.box_node(Vector3(w, h, d), wall, Vector3(0, h * 0.5 + 0.4, 0)))
			root.add_child(MeshKit.box_node(Vector3(w + 0.05, 0.25, d + 0.05), wood, Vector3(0, h * 0.5 + 0.4, 0)))
			var prism := PrismMesh.new()
			prism.size = Vector3(w + 1.4, 2.6, d + 1.2)
			var r := MeshKit.mesh_instance(prism, roof)
			r.position = Vector3(0, h + 0.4 + 1.3, 0)
			root.add_child(r)
			var porch := MeshKit.box_node(Vector3(w * 0.7, 0.14, 1.6), roof, Vector3(0, 2.9, -d * 0.5 - 0.7))
			porch.rotation.x = 0.28
			root.add_child(porch)
			root.add_child(MeshKit.box_node(Vector3(1.8, 2.3, 0.1), wood, Vector3(-w * 0.2, 1.55, -d * 0.5 - 0.05)))
			for k in 3:
				root.add_child(MeshKit.box_node(Vector3(1.3, 1.1, 0.08), win, Vector3(-w * 0.3 + k * w * 0.3, h * 0.5 + 2.6, -d * 0.5 - 0.04)))
			root.add_child(MeshKit.box_node(Vector3(1.4, 1.2, 0.08), win, Vector3(w * 0.25, 1.9, -d * 0.5 - 0.04)))
			for k in 2:
				root.add_child(MeshKit.box_node(Vector3(0.08, 1.1, 1.3), win, Vector3(w * 0.5 + 0.04, h * 0.5 + 2.6, -d * 0.2 + k * d * 0.4)))
			root.add_child(MeshKit.box_node(Vector3(0.7, 1.4, 0.7), TexKit.std(Color(0.35, 0.3, 0.28), 0.9), Vector3(w * 0.3, h + 2.4, d * 0.15)))
			root.add_child(MeshKit.box_node(Vector3(w + 3.0, 1.1, 0.25), TexKit.std(Color(0.6, 0.6, 0.58), 0.95), Vector3(0, 0.55, -d * 0.5 - 3.2)))
			if rng.randf() < 0.6:
				_vending_machine(root, Vector3(w * 0.5 + 0.8, 0, -d * 0.5 - 2.6))
	return root


func _window_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.12, 0.15)
	m.roughness = 0.08
	m.metallic = 0.3
	m.emission_enabled = true
	m.emission = Color(1.0, 0.78, 0.45)
	m.emission_energy_multiplier = 0.0
	_window_mats.append([m, rng.randf() < 0.75])
	return m


## Emissive material whose energy follows the time of day.
func _glow_material(color: Color, day_energy: float, night_energy: float) -> StandardMaterial3D:
	var m := TexKit.emissive(color, day_energy)
	_glow_mats.append([m, day_energy, night_energy])
	return m


func _vending_machine(root: Node3D, pos: Vector3) -> void:
	var cols := [Color(0.9, 0.1, 0.1), Color(0.1, 0.35, 0.9), Color(0.95, 0.95, 0.95)]
	var body := MeshKit.box_node(Vector3(1.0, 1.85, 0.8), TexKit.std(cols[rng.randi() % 3], 0.4, 0.2), pos + Vector3(0, 0.925, 0))
	root.add_child(body)
	var glow := _glow_material(Color(0.85, 0.95, 1.0), 0.6, 2.6)
	root.add_child(MeshKit.box_node(Vector3(0.8, 0.9, 0.04), glow, pos + Vector3(0, 1.25, -0.41)))
	var l := OmniLight3D.new()
	l.light_color = Color(0.8, 0.9, 1.0)
	l.omni_range = 4.0
	l.light_energy = 0.8
	l.position = pos + Vector3(0, 1.2, -1.0)
	l.visible = false
	root.add_child(l)
	_night_lights.append([l, 0.8])


## 0 = day … 1 = night: switches lamps, windows and signs.
func set_night(n: float) -> void:
	night = n
	for w in _window_mats:
		(w[0] as StandardMaterial3D).emission_energy_multiplier = (2.2 if w[1] else 0.0) * n
	for g in _glow_mats:
		(g[0] as StandardMaterial3D).emission_energy_multiplier = lerpf(float(g[1]), float(g[2]), n)
	var lights_on := n > 0.3
	for l in _night_lights:
		var light: Light3D = l[0]
		light.visible = lights_on
		light.light_energy = float(l[1]) * n
	for l in lamp_lights:
		(l as Light3D).visible = lights_on


# ---------------------------------------------------------------------------
# Harbor
# ---------------------------------------------------------------------------
func _build_water_and_quay() -> void:
	var b: Rect2 = track.bounds
	var quay_z := b.end.y + 45.0
	var water := PlaneMesh.new()
	water.size = Vector2(3600, 1800)
	var wmi := MeshKit.mesh_instance(water, TexKit.water_material(), false)
	wmi.position = Vector3(b.get_center().x, 0.06, quay_z + 900.0)
	wmi.name = "Water"
	add_child(wmi)
	var quay := MeshKit.box_node(Vector3(3600, 5.6, 1.2), TexKit.std(Color(0.5, 0.5, 0.48), 0.9), Vector3(b.get_center().x, -2.55, quay_z))
	add_child(quay)
	for k in 30:
		var x := b.position.x - 100.0 + k * 22.0
		add_child(MeshKit.cyl_node(0.18, 0.22, 0.6, TexKit.std(Color(0.15, 0.15, 0.16), 0.5, 0.6), Vector3(x, 0.55, quay_z - 0.3)))
	for k in 2:
		var ship := Node3D.new()
		ship.position = Vector3(b.position.x + 80.0 + k * 260.0, 0, quay_z + 40.0 + k * 30.0)
		var hull_col: Color = [Color(0.1, 0.18, 0.35), Color(0.35, 0.08, 0.06)][k]
		ship.add_child(MeshKit.box_node(Vector3(150, 12, 24), TexKit.std(hull_col, 0.6, 0.3), Vector3(0, 3, 0)))
		ship.add_child(MeshKit.box_node(Vector3(20, 14, 20), TexKit.std(Color(0.9, 0.9, 0.88), 0.6), Vector3(60, 16, 0)))
		for c in 8:
			var cm := TexKit.container_material(Color.from_hsv(rng.randf(), 0.6, 0.6))
			ship.add_child(MeshKit.box_node(Vector3(12.2, 2.6, 22), cm, Vector3(-60 + c * 13.0, 10.3, 0)))
		add_child(ship)
		occupy(ship.position, 80.0)
	for k in 2:
		var crane := Node3D.new()
		crane.position = Vector3(b.position.x + 120.0 + k * 180.0, 0, quay_z - 12.0)
		var steel := TexKit.std(Color(0.85, 0.45, 0.08) if k == 0 else Color(0.15, 0.4, 0.75), 0.5, 0.4)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				crane.add_child(MeshKit.box_node(Vector3(1.2, 40, 1.2), steel, Vector3(sx * 9.0, 20, sz * 8.0)))
		crane.add_child(MeshKit.box_node(Vector3(20, 3, 3), steel, Vector3(0, 40, -8)))
		crane.add_child(MeshKit.box_node(Vector3(20, 3, 3), steel, Vector3(0, 40, 8)))
		crane.add_child(MeshKit.box_node(Vector3(3, 3, 90), steel, Vector3(0, 44, 30)))
		crane.add_child(MeshKit.box_node(Vector3(5, 4, 6), TexKit.std(Color(0.9, 0.9, 0.9), 0.5), Vector3(0, 40, 12)))
		var beacon := MeshKit.sphere_node(0.5, TexKit.emissive(Color(1, 0.1, 0.05), 4.0), Vector3(0, 46, 75))
		crane.add_child(beacon)
		add_child(crane)
		occupy(crane.position, 16.0)


func _build_harbor_props() -> void:
	var colors := [Color(0.65, 0.12, 0.06), Color(0.1, 0.3, 0.55), Color(0.15, 0.45, 0.2), Color(0.75, 0.55, 0.1),
		Color(0.5, 0.5, 0.52), Color(0.85, 0.85, 0.85), Color(0.35, 0.15, 0.4)]
	var mats: Array = []
	for c in colors:
		mats.append(TexKit.container_material(c))
	var cont_long := BoxMesh.new()
	cont_long.size = Vector3(2.44, 2.59, 12.19)
	var cont_short := BoxMesh.new()
	cont_short.size = Vector3(2.44, 2.59, 6.06)
	for k in 3:
		var tries := 0
		while tries < 80:
			tries += 1
			var i := rng.randi_range(0, track.sample_count() - 1)
			var pos := _roadside(i, rng.randf_range(20.0, 34.0), -1.0 if rng.randf() < 0.5 else 1.0)
			if not free_at(pos, 26.0, 20.0):
				continue
			pos.y = terrain.flatten(pos, 24.0, 8.0)
			var wh := Node3D.new()
			var w := rng.randf_range(30.0, 45.0)
			var dpt := rng.randf_range(22.0, 30.0)
			var hh := rng.randf_range(9.0, 13.0)
			wh.add_child(MeshKit.box_node(Vector3(w, hh + 2.0, dpt), TexKit.container_material(Color(0.55, 0.57, 0.6)), Vector3(0, hh * 0.5 - 1.0, 0)))
			var prism := PrismMesh.new()
			prism.size = Vector3(w + 1.0, 3.0, dpt + 1.0)
			var roof := MeshKit.mesh_instance(prism, TexKit.std(Color(0.3, 0.32, 0.35), 0.5, 0.6))
			roof.position = Vector3(0, hh + 1.5, 0)
			wh.add_child(roof)
			for dk in 3:
				wh.add_child(MeshKit.box_node(Vector3(5.0, 5.5, 0.15), TexKit.std(Color(0.7, 0.62, 0.15), 0.5, 0.5), Vector3(-w * 0.3 + dk * w * 0.3, 2.75, -dpt * 0.5 - 0.08)))
			var lamp := MeshKit.box_node(Vector3(w * 0.8, 0.3, 0.3), _glow_material(Color(1, 0.9, 0.7), 0.3, 3.3), Vector3(0, 6.5, -dpt * 0.5 - 0.3))
			wh.add_child(lamp)
			add_child(wh)
			_face_track(wh, pos)
			occupy(pos, 26.0)
			break
	var stacks := 0
	var tries2 := 0
	while stacks < 40 and tries2 < 1400:
		tries2 += 1
		var pos: Vector3
		if rng.randf() < 0.75:
			var i := rng.randi_range(0, track.sample_count() - 1)
			pos = _roadside(i, rng.randf_range(4.0, 26.0), -1.0 if rng.randf() < 0.5 else 1.0)
		else:
			var b: Rect2 = track.bounds.grow(40.0)
			pos = Vector3(rng.randf_range(b.position.x, b.end.x), 0, rng.randf_range(b.position.y, b.end.y))
		if not free_at(pos, 7.0, 4.0):
			continue
		if terrain.splat_at(pos.x, pos.z).r < 0.9:
			continue
		pos.y = terrain.height_at(pos.x, pos.z)
		var along := rng.randf() < 0.5
		var levels := rng.randi_range(1, 3)
		var row := rng.randi_range(1, 3)
		var stack := Node3D.new()
		for rr in row:
			for lv in levels:
				var long := rng.randf() < 0.7
				var mi := MeshKit.mesh_instance(cont_long if long else cont_short, mats[rng.randi() % mats.size()])
				mi.position = Vector3(rr * 2.6, 1.3 + lv * 2.6, rng.randf_range(-0.2, 0.2))
				stack.add_child(mi)
		stack.position = pos
		stack.rotation.y = rng.randf_range(-0.1, 0.1) + (PI * 0.5 if along else 0.0)
		add_child(stack)
		occupy(pos, 7.0)
		stacks += 1


func _build_skyline() -> void:
	var c: Vector2 = track.bounds.get_center()
	var win_tex := _skyline_texture()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.21, 0.24)
	mat.albedo_texture = win_tex
	mat.emission_enabled = true
	mat.emission_texture = win_tex
	mat.emission = Color(1.0, 0.85, 0.6)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.04, 0.04, 0.04)
	mat.roughness = 0.4
	mat.metallic = 0.2
	_glow_mats.append([mat, 0.0, 0.55])
	for k in 70:
		var a := rng.randf_range(-PI * 0.95, -PI * 0.05)  # north side (away from the water)
		var r := rng.randf_range(750.0, 1050.0)
		var h := rng.randf_range(30.0, 130.0)
		var w := rng.randf_range(25.0, 60.0)
		var bx := c.x + cos(a) * r
		var bz := c.y + sin(a) * r
		var gy: float = terrain.outer_height(bx, bz) - 3.0
		var b := MeshKit.box_node(Vector3(w, h + 3.0, w * rng.randf_range(0.6, 1.2)), mat, Vector3(bx, gy + (h + 3.0) * 0.5, bz))
		b.rotation.y = rng.randf() * TAU
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		if rng.randf() < 0.3:
			add_child(MeshKit.sphere_node(0.8, TexKit.emissive(Color(1, 0.1, 0.05), 5.0), b.position + Vector3(0, (h + 3.0) * 0.5 + 1.0, 0)))


func _skyline_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.06))
	for y in range(2, 64, 4):
		for x in range(2, 64, 4):
			var lit := rng.randf() < 0.3
			var col := Color(1.0, 0.85, 0.55) * rng.randf_range(0.5, 1.0) if lit else Color(0.06, 0.065, 0.08)
			for yy in 2:
				for xx in 2:
					img.set_pixel(x + xx, y + yy, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Street lamps
# ---------------------------------------------------------------------------
func _build_lamps() -> void:
	var n: int = track.sample_count()
	var every := 36  # samples (≈72 m)
	var pole_mat := TexKit.std(Color(0.3, 0.31, 0.33), 0.5, 0.7)
	var head_mat := _glow_material(Color(1.0, 0.85, 0.6), 0.2, 5.2)
	var k := 0
	for i in range(0, n, every):
		var side := 1.0 if track.curvature[i] > 0.0 else -1.0
		if absf(track.curvature[i]) < 0.002:
			side = -1.0 if k % 2 == 0 else 1.0
		k += 1
		var pos := _roadside(i, 1.4, side)
		pos.y = terrain.height_at(pos.x, pos.z)
		var lamp := Node3D.new()
		lamp.name = "Lamp"
		add_child(lamp)
		var inward: Vector3 = -track.rights[i] * side
		lamp.global_transform = Transform3D(Basis.looking_at(inward, Vector3.UP), pos)
		lamp.add_child(MeshKit.cyl_node(0.08, 0.12, 8.0, pole_mat, Vector3(0, 4.0, 0), Vector3.ZERO, 10))
		lamp.add_child(MeshKit.box_node(Vector3(0.12, 0.12, 2.6), pole_mat, Vector3(0, 7.9, -1.2)))
		lamp.add_child(MeshKit.box_node(Vector3(0.5, 0.18, 0.9), head_mat, Vector3(0, 7.8, -2.4)))
		var l := SpotLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.light_energy = 6.0
		l.spot_range = 22.0
		l.spot_angle = 55.0
		l.spot_attenuation = 0.8
		l.shadow_enabled = false
		l.position = Vector3(0, 7.6, -2.4)
		l.rotation = Vector3(-PI * 0.5, 0, 0)
		l.visible = false
		lamp.add_child(l)
		lamp_lights.append(l)
		_night_lights.append([l, 6.0])
		occupy(pos, 1.5)


func stats_text() -> String:
	var parts: Array = []
	for k in _stats.keys():
		parts.append("%s=%d" % [k, _stats[k]])
	return ", ".join(parts)
