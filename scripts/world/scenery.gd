extends Node3D
## Places trees, houses, harbor props, street lamps and horizon decoration around a track.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const TreeFactory = preload("res://scripts/world/tree_factory.gd")

const CHUNK := 90.0
const TREE_LOD_DIST := 150.0

var track  # track.gd instance
var night := 0.0            # 0 = day … 1 = night (drives lamps / window glow)
var rng := RandomNumberGenerator.new()
var _occupied: Array = []   # [Vector2 pos, radius]
var _window_mats: Array = []
var lamp_lights: Array = []


func build(p_track: Node3D, p_night: float, quality: int) -> void:
	track = p_track
	night = p_night
	rng.seed = hash(track.track_id)
	var id: String = track.track_id
	if id == "harbor":
		_build_water_and_quay()
		_build_harbor_props()
		_build_houses(4, ["office", "jp", "jp", "shop"])
		_build_trees(70 if quality >= 1 else 40, 0.0, 0.25)
		_build_skyline()
	else:
		_build_houses(8, ["jp", "jp", "jp", "shop", "jp", "jp", "barn", "jp"])
		var count := [220, 380, 480, 600][clampi(quality, 0, 3)]
		_build_trees(count, 0.62, 0.08)
		_build_mountains()
	_build_lamps()


# ---------------------------------------------------------------------------
# Placement helpers
# ---------------------------------------------------------------------------
func _free_at(pos: Vector3, radius: float, clearance: float) -> bool:
	if track.distance_to_center(pos) < track.wall_base + clearance:
		return false
	var p2 := Vector2(pos.x, pos.z)
	for o in _occupied:
		var op: Vector2 = o[0]
		if op.distance_to(p2) < float(o[1]) + radius:
			return false
	return true


func _occupy(pos: Vector3, radius: float) -> void:
	_occupied.append([Vector2(pos.x, pos.z), radius])


## A point beside the track at sample index i, `extra` metres behind the wall (outside of the corner).
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


# ---------------------------------------------------------------------------
# Trees (chunked multimeshes with two LOD levels)
# ---------------------------------------------------------------------------
func _build_trees(count: int, pine_ratio: float, autumn_ratio: float) -> void:
	var variants: Array = []
	# [hi mesh, lo mesh, crown radius]
	variants.append([TreeFactory.deciduous(101, 1.0), TreeFactory.deciduous(101, 0.35), 4.5, "leaf"])
	variants.append([TreeFactory.deciduous(202, 1.0), TreeFactory.deciduous(202, 0.35), 4.5, "leaf"])
	variants.append([TreeFactory.deciduous(303, 1.0, true), TreeFactory.deciduous(303, 0.35, true), 4.5, "autumn"])
	if pine_ratio > 0.0:
		variants.append([TreeFactory.pine(404, 1.0), TreeFactory.pine(404, 0.35), 3.5, "pine"])
		variants.append([TreeFactory.pine(505, 1.0), TreeFactory.pine(505, 0.35), 3.5, "pine"])
	var bush_mesh := TreeFactory.bush(606)
	var b: Rect2 = track.bounds.grow(220.0)
	# chunks[variant][chunk_key] = Array of Transform3D
	var chunks: Array = []
	for v in variants.size():
		chunks.append({})
	var bushes := {}
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 30:
		tries += 1
		# bias half of the trees close to the track so the forest frames the road
		var pos: Vector3
		if rng.randf() < 0.55:
			var i := rng.randi_range(0, track.sample_count() - 1)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			pos = _roadside(i, rng.randf_range(3.5, 45.0), side)
		else:
			pos = Vector3(rng.randf_range(b.position.x, b.end.x), 0, rng.randf_range(b.position.y, b.end.y))
		if not _free_at(pos, 2.0, 3.5):
			continue
		var v := 0
		if rng.randf() < pine_ratio and variants.size() > 3:
			v = 3 + rng.randi_range(0, 1)
		else:
			v = 2 if rng.randf() < autumn_ratio else rng.randi_range(0, 1)
		var s := rng.randf_range(0.8, 1.25)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s)), pos)
		var key := Vector2i(int(floor(pos.x / CHUNK)), int(floor(pos.z / CHUNK)))
		if not chunks[v].has(key):
			chunks[v][key] = []
		chunks[v][key].append(xf)
		_occupy(pos, 2.0)
		placed += 1
		# a bush or two around some trees
		if rng.randf() < 0.35:
			var bp := pos + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			if _free_at(bp, 0.5, 2.0):
				if not bushes.has(key):
					bushes[key] = []
				var bs := rng.randf_range(0.7, 1.5)
				bushes[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(bs, bs, bs)), bp))
	for v in variants.size():
		for key in chunks[v].keys():
			var xfs: Array = chunks[v][key]
			_add_multimesh(variants[v][0], xfs, 0.0, TREE_LOD_DIST, "Trees_hi")
			_add_multimesh(variants[v][1], xfs, TREE_LOD_DIST, 1400.0, "Trees_lo")
	for key in bushes.keys():
		_add_multimesh(bush_mesh, bushes[key], 0.0, 220.0, "Bushes")


func _add_multimesh(mesh: Mesh, xfs: Array, range_begin: float, range_end: float, label: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = label
	mmi.visibility_range_begin = range_begin
	mmi.visibility_range_end = range_end
	mmi.visibility_range_begin_margin = 10.0 if range_begin > 0.0 else 0.0
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


# ---------------------------------------------------------------------------
# Houses
# ---------------------------------------------------------------------------
func _build_houses(count: int, styles: Array) -> void:
	var n: int = track.sample_count()
	var placed := 0
	var tries := 0
	# cluster houses into a small village around a random stretch of road
	var village := rng.randi_range(0, n - 1)
	while placed < count and tries < 400:
		tries += 1
		var i := village + rng.randi_range(-70, 70) if tries < 250 else rng.randi_range(0, n - 1)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := _roadside(i, rng.randf_range(9.0, 22.0), side)
		if not _free_at(pos, 9.0, 6.0):
			continue
		var style: String = styles[placed % styles.size()]
		var house := _make_house(style)
		add_child(house)
		_face_track(house, pos)
		_occupy(pos, 9.0)
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
			var sign_mat := TexKit.emissive(Color(1.0, 0.55, 0.15), 0.5 + night * 2.5)
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
			# small lower roof over the entrance
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
			# garden wall
			root.add_child(MeshKit.box_node(Vector3(w + 3.0, 1.1, 0.25), TexKit.std(Color(0.6, 0.6, 0.58), 0.95), Vector3(0, 0.55, -d * 0.5 - 3.2)))
			if rng.randf() < 0.6:
				_vending_machine(root, Vector3(w * 0.5 + 0.8, 0, -d * 0.5 - 2.6))
	return root


func _window_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var lit := rng.randf() < 0.75
	m.albedo_color = Color(0.1, 0.12, 0.15)
	m.roughness = 0.08
	m.metallic = 0.3
	m.emission_enabled = true
	m.emission = Color(1.0, 0.78, 0.45)
	m.emission_energy_multiplier = (2.2 if lit else 0.0) * night
	_window_mats.append(m)
	return m


func _vending_machine(root: Node3D, pos: Vector3) -> void:
	var cols := [Color(0.9, 0.1, 0.1), Color(0.1, 0.35, 0.9), Color(0.95, 0.95, 0.95)]
	var body := MeshKit.box_node(Vector3(1.0, 1.85, 0.8), TexKit.std(cols[rng.randi() % 3], 0.4, 0.2), pos + Vector3(0, 0.925, 0))
	root.add_child(body)
	var glow := TexKit.emissive(Color(0.85, 0.95, 1.0), 0.6 + night * 2.0)
	root.add_child(MeshKit.box_node(Vector3(0.8, 0.9, 0.04), glow, pos + Vector3(0, 1.25, -0.41)))
	if night > 0.3:
		var l := OmniLight3D.new()
		l.light_color = Color(0.8, 0.9, 1.0)
		l.omni_range = 4.0
		l.light_energy = 0.8 * night
		l.position = pos + Vector3(0, 1.2, -1.0)
		root.add_child(l)


# ---------------------------------------------------------------------------
# Harbor
# ---------------------------------------------------------------------------
func _build_water_and_quay() -> void:
	var b: Rect2 = track.bounds
	var quay_z := b.end.y + 45.0
	var water := PlaneMesh.new()
	water.size = Vector2(3200, 1600)
	var wmi := MeshKit.mesh_instance(water, TexKit.water_material(), false)
	wmi.position = Vector3(b.get_center().x, 0.06, quay_z + 800.0)
	wmi.name = "Water"
	add_child(wmi)
	var quay := MeshKit.box_node(Vector3(3200, 0.5, 1.2), TexKit.std(Color(0.5, 0.5, 0.48), 0.9), Vector3(b.get_center().x, 0.25, quay_z))
	add_child(quay)
	# bollards
	for k in 30:
		var x := b.position.x - 100.0 + k * 22.0
		add_child(MeshKit.cyl_node(0.18, 0.22, 0.6, TexKit.std(Color(0.15, 0.15, 0.16), 0.5, 0.6), Vector3(x, 0.8, quay_z - 0.3)))
	# a couple of ships
	for k in 2:
		var ship := Node3D.new()
		ship.position = Vector3(b.position.x + 80.0 + k * 260.0, 0, quay_z + 40.0 + k * 30.0)
		var hull_col := [Color(0.1, 0.18, 0.35), Color(0.35, 0.08, 0.06)][k]
		ship.add_child(MeshKit.box_node(Vector3(150, 12, 24), TexKit.std(hull_col, 0.6, 0.3), Vector3(0, 3, 0)))
		ship.add_child(MeshKit.box_node(Vector3(20, 14, 20), TexKit.std(Color(0.9, 0.9, 0.88), 0.6), Vector3(60, 16, 0)))
		for c in 8:
			var cm := TexKit.container_material(Color.from_hsv(rng.randf(), 0.6, 0.6))
			ship.add_child(MeshKit.box_node(Vector3(12.2, 2.6, 22), cm, Vector3(-60 + c * 13.0, 10.3, 0)))
		add_child(ship)
		_occupy(ship.position, 80.0)
	# gantry cranes on the quay
	for k in 2:
		var crane := Node3D.new()
		crane.position = Vector3(b.position.x + 120.0 + k * 180.0, 0, quay_z - 12.0)
		var steel := TexKit.std(Color(0.85, 0.45, 0.08) if k == 0 else Color(0.15, 0.4, 0.75), 0.5, 0.4)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				crane.add_child(MeshKit.box_node(Vector3(1.2, 40, 1.2), steel, Vector3(sx * 9.0, 20, sz * 8.0)))
		crane.add_child(MeshKit.box_node(Vector3(20, 3, 3), steel, Vector3(0, 40, -8)))
		crane.add_child(MeshKit.box_node(Vector3(20, 3, 3), steel, Vector3(0, 40, 8)))
		crane.add_child(MeshKit.box_node(Vector3(3, 3, 90), steel, Vector3(0, 44, 30)))
		crane.add_child(MeshKit.box_node(Vector3(5, 4, 6), TexKit.std(Color(0.9, 0.9, 0.9), 0.5), Vector3(0, 40, 12)))
		var beacon := MeshKit.sphere_node(0.5, TexKit.emissive(Color(1, 0.1, 0.05), 4.0), Vector3(0, 46, 75))
		crane.add_child(beacon)
		add_child(crane)
		_occupy(crane.position, 16.0)


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
	# warehouses
	for k in 3:
		var tries := 0
		while tries < 80:
			tries += 1
			var i := rng.randi_range(0, track.sample_count() - 1)
			var pos := _roadside(i, rng.randf_range(22.0, 40.0), -1.0 if rng.randf() < 0.5 else 1.0)
			if not _free_at(pos, 26.0, 20.0):
				continue
			var wh := Node3D.new()
			var w := rng.randf_range(30.0, 45.0)
			var dpt := rng.randf_range(22.0, 30.0)
			var hh := rng.randf_range(9.0, 13.0)
			wh.add_child(MeshKit.box_node(Vector3(w, hh, dpt), TexKit.container_material(Color(0.55, 0.57, 0.6)), Vector3(0, hh * 0.5, 0)))
			var prism := PrismMesh.new()
			prism.size = Vector3(w + 1.0, 3.0, dpt + 1.0)
			var roof := MeshKit.mesh_instance(prism, TexKit.std(Color(0.3, 0.32, 0.35), 0.5, 0.6))
			roof.position = Vector3(0, hh + 1.5, 0)
			wh.add_child(roof)
			for dk in 3:
				wh.add_child(MeshKit.box_node(Vector3(5.0, 5.5, 0.15), TexKit.std(Color(0.7, 0.62, 0.15), 0.5, 0.5), Vector3(-w * 0.3 + dk * w * 0.3, 2.75, -dpt * 0.5 - 0.08)))
			var lamp := MeshKit.box_node(Vector3(w * 0.8, 0.3, 0.3), TexKit.emissive(Color(1, 0.9, 0.7), 0.3 + night * 3.0), Vector3(0, 6.5, -dpt * 0.5 - 0.3))
			wh.add_child(lamp)
			add_child(wh)
			_face_track(wh, pos)
			_occupy(pos, 26.0)
			break
	# container stacks
	var stacks := 0
	var tries2 := 0
	while stacks < 36 and tries2 < 1200:
		tries2 += 1
		var pos: Vector3
		if rng.randf() < 0.7:
			var i := rng.randi_range(0, track.sample_count() - 1)
			pos = _roadside(i, rng.randf_range(4.0, 30.0), -1.0 if rng.randf() < 0.5 else 1.0)
		else:
			var b: Rect2 = track.bounds.grow(60.0)
			pos = Vector3(rng.randf_range(b.position.x, b.end.x), 0, rng.randf_range(b.position.y, b.end.y))
		if not _free_at(pos, 7.0, 4.0):
			continue
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
		_occupy(pos, 7.0)
		stacks += 1


func _build_skyline() -> void:
	var c: Vector2 = track.bounds.get_center()
	var win_tex := _skyline_texture()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.23, 0.27)
	mat.albedo_texture = win_tex
	mat.emission_enabled = true
	mat.emission_texture = win_tex
	mat.emission = Color(1.0, 0.85, 0.6)
	mat.emission_energy_multiplier = 0.05 + night * 1.8
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.05, 0.05, 0.05)
	mat.roughness = 0.4
	for k in 70:
		var a := rng.randf_range(-PI * 0.95, -PI * 0.05)  # north side (away from the water)
		var r := rng.randf_range(700.0, 1000.0)
		var h := rng.randf_range(30.0, 130.0)
		var w := rng.randf_range(25.0, 60.0)
		var b := MeshKit.box_node(Vector3(w, h, w * rng.randf_range(0.6, 1.2)), mat, Vector3(c.x + cos(a) * r, h * 0.5, c.y + sin(a) * r))
		b.rotation.y = rng.randf() * TAU
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		if rng.randf() < 0.3:
			add_child(MeshKit.sphere_node(0.8, TexKit.emissive(Color(1, 0.1, 0.05), 5.0), b.position + Vector3(0, h * 0.5 + 1.0, 0)))


func _skyline_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.06))
	for y in range(2, 64, 4):
		for x in range(2, 64, 4):
			var lit := rng.randf() < 0.45
			var col := Color(1.0, 0.85, 0.55) * rng.randf_range(0.5, 1.0) if lit else Color(0.1, 0.11, 0.13)
			for yy in 2:
				for xx in 2:
					img.set_pixel(x + xx, y + yy, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Ridge: distant mountains
# ---------------------------------------------------------------------------
func _build_mountains() -> void:
	var c: Vector2 = track.bounds.get_center()
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 1.4
	var segs := 160
	var radii := [720.0, 820.0, 980.0, 1150.0, 1400.0]
	var rows: Array = []
	var centers: Array = []
	for ri in radii.size():
		var row := PackedVector3Array()
		row.resize(segs)
		for s in segs:
			var a := TAU * float(s) / segs
			var dir := Vector3(cos(a), 0, sin(a))
			var n1 := noise.get_noise_2d(cos(a) * 1.0, sin(a) * 1.0) * 0.5 + 0.5
			var n2 := noise.get_noise_2d(cos(a) * 3.0 + 10.0, sin(a) * 3.0) * 0.5 + 0.5
			var peak := 60.0 + n1 * 170.0 + n2 * 50.0
			var hmul: float = [0.0, 0.45, 1.0, 0.8, 0.2][ri]
			var r: float = radii[ri] + (n2 - 0.5) * 60.0
			row[s] = Vector3(c.x, -2.0, c.y) + dir * r + Vector3(0, peak * hmul, 0)
		rows.append(row)
		centers.append(Vector3(c.x, 3000.0, c.y))
	var st := MeshKit.new_st()
	MeshKit.grid(st, rows, centers, true, Vector2(40, 0.02), Color.WHITE, true)
	var mat := TexKit.ground_material(Color(0.09, 0.15, 0.07), Color(0.13, 0.19, 0.09), Color(0.25, 0.24, 0.22), 0.95)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, mat), null, false)
	mi.name = "Mountains"
	add_child(mi)


# ---------------------------------------------------------------------------
# Street lamps
# ---------------------------------------------------------------------------
func _build_lamps() -> void:
	var n: int = track.sample_count()
	var every := 36  # samples (≈72 m)
	var pole_mat := TexKit.std(Color(0.3, 0.31, 0.33), 0.5, 0.7)
	var head_mat := TexKit.emissive(Color(1.0, 0.85, 0.6), 0.2 + night * 5.0)
	var k := 0
	for i in range(0, n, every):
		# put the lamp on the outside of the corner
		var side := 1.0 if track.curvature[i] > 0.0 else -1.0
		if absf(track.curvature[i]) < 0.002:
			side = -1.0 if k % 2 == 0 else 1.0
		k += 1
		var pos := _roadside(i, 1.4, side)
		var lamp := Node3D.new()
		lamp.name = "Lamp"
		add_child(lamp)
		var inward: Vector3 = -track.rights[i] * side
		lamp.global_transform = Transform3D(Basis.looking_at(inward, Vector3.UP), pos)
		lamp.add_child(MeshKit.cyl_node(0.08, 0.12, 8.0, pole_mat, Vector3(0, 4.0, 0), Vector3.ZERO, 10))
		lamp.add_child(MeshKit.box_node(Vector3(0.12, 0.12, 2.6), pole_mat, Vector3(0, 7.9, -1.2)))
		lamp.add_child(MeshKit.box_node(Vector3(0.5, 0.18, 0.9), head_mat, Vector3(0, 7.8, -2.4)))
		if night > 0.3:
			var l := SpotLight3D.new()
			l.light_color = Color(1.0, 0.82, 0.55)
			l.light_energy = 6.0 * night
			l.spot_range = 22.0
			l.spot_angle = 55.0
			l.spot_attenuation = 0.8
			l.shadow_enabled = false
			l.position = Vector3(0, 7.6, -2.4)
			l.rotation = Vector3(-PI * 0.5, 0, 0)
			lamp.add_child(l)
			lamp_lights.append(l)
		_occupy(pos, 1.5)
