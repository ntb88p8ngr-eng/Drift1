extends Node3D
## The Playground: a big asphalt pad around a compact figure-eight drift track, closed by a concrete
## barrier with sponsor boards. Grass islands inside the loops and in the south corners (red/white
## kerbs, tyre walls), a pit lane with garages along the north edge, small houses outside the barrier,
## and the open asphalt organised in zones full of physics toys – donut circles, cone slaloms, barrel
## fields, stacks of single tyres, water barriers and crates / cardboard boxes that break apart.
## Props are simulated locally (not synced online).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const SignAtlas = preload("res://scripts/world/sign_atlas.gd")
const Houses = preload("res://scripts/world/houses.gd")

const PROP_LAYER := 8
const PROP_MASK := 1 | 2 | 4 | 8
const MAX_DEBRIS := 160
const Colliders = preload("res://scripts/util/colliders.gd")
const PIT_LEN := 110.0         # pit lane length (x)

var track
var terrain
var scenery
var rng := RandomNumberGenerator.new()
var _meshes := {}
var _shapes := {}
var _debris: Array = []
var _stats := {}
var _pit := Rect2()            # pit lane + garages (kept free of loose props)


func build(p_track, p_terrain, p_scenery, quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	rng.seed = 4242
	_make_assets()
	_perimeter()
	_pit_lane()
	_islands()
	_houses()
	for isl in terrain.islands:
		scenery.occupy(Vector3(isl[0].x, 0, isl[0].y), float(isl[1]) + 3.0)
	var free_spots := _open_spots()
	_donut_circles(free_spots, 3)
	_slaloms(free_spots, 4)
	_barrel_clusters(free_spots, 26 if quality >= 1 else 14)
	_crate_stacks(free_spots, 16 if quality >= 1 else 10)
	_box_walls(free_spots, 8 if quality >= 1 else 4)
	_tyre_stacks(free_spots, 34 if quality >= 1 else 18)
	_water_barriers()
	print("PLAYGROUND: ", _stats)


## Ridge / harbor: physics props in the run-off – tyre walls lining the gravel traps, barrel and cone
## groups at marshal posts along the straights, breakable crates (harbor) or cardboard boxes (ridge).
func build_trackside(p_track, p_terrain, p_scenery, quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	rng.seed = hash(track.track_id) + 77
	_make_assets()
	await _tyre_walls(260 if quality >= 1 else 140)
	await Game.load_tick()
	await _marshal_posts(quality)
	print("TRACKSIDE PROPS: ", _stats)


## Room between the road edge and the barrier on `side` at sample i (m).
func _runoff_at(i: int, side: float) -> float:
	var off: float = track.off_left[i] if side < 0.0 else track.off_right[i]
	return off - float(track.half_w)


func _tyre_walls(budget: int) -> void:
	var n: int = track.sample_count()
	var lat: float = float(track.half_w) + float(track.trap_w) + 0.05
	var placed := 0
	var last := Vector3.INF
	for i in n:
		if i % 400 == 0:
			await Game.load_tick()
		var tw: float = track.trap[i]
		if absf(tw) < 0.5 or placed >= budget:
			continue
		var side := signf(tw)
		if _runoff_at(i, side) < float(track.trap_w) + 0.35:
			continue
		# two stacks per 2 m sample: a closed wall
		var j: int = (i + 1) % n
		for h in [0.0, 0.5]:
			var c: Vector3 = track.samples[i].lerp(track.samples[j], h)
			var r: Vector3 = track.rights[i].lerp(track.rights[j], h).normalized()
			var p: Vector3 = c + r * side * lat
			if last != Vector3.INF and p.distance_to(last) < 0.68:
				continue
			tyre_stack(Vector3(p.x, 0, p.z), 3)
			last = p
			placed += 1


func _marshal_posts(quality: int) -> void:
	var n: int = track.sample_count()
	var every := 36 if quality >= 1 else 55    # samples (2 m each)
	if track.elevated:
		every *= 3      # 20 km of track: a marshal post every ~200 m is plenty
	var side := 1.0
	var i: int = (track.start_index + 45) % n
	var count := 0
	while count < n / every:
		if count % 8 == 0:
			await Game.load_tick()
		count += 1
		i = (i + every + rng.randi_range(-8, 8)) % n
		side = -side
		# only on straights (no curbs, no traps) with enough run-off
		var ok := true
		for d in range(-4, 5):
			var k: int = (i + d + n) % n
			if track.curb_mask[k] == 1 or absf(track.trap[k]) > 0.2 or _runoff_at(k, side) < float(track.def["runoff"]) - 0.3:
				ok = false
				break
		if not ok:
			continue
		var room := _runoff_at(i, side)
		var c: Vector3 = track.samples[i] + track.rights[i] * side * (float(track.half_w) + room - 1.1)
		c.y = _ground(c.x, c.z)
		var t: Vector3 = track.tangents[i]
		var b := Basis.looking_at(t, Vector3.UP)
		match count % 3:
			0:
				# barrels
				var key := "barrel_%d" % rng.randi_range(0, 2)
				for k in rng.randi_range(3, 5):
					var p := c + t * (-1.4 + k * 0.7) + Vector3(0, 0.45, 0)
					_body(key, "barrel", 20.0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
			1:
				# stacked crates (harbor) or a cardboard-box wall (ridge)
				if track.track_id == "harbor":
					for x in [-0.55, 0.55]:
						_breakable(_body("crate", "crate", 25.0, Transform3D(b, c + t * x + Vector3(0, 0.5, 0))), "plank", 6, 5.0)
					_breakable(_body("crate", "crate", 25.0, Transform3D(b, c + Vector3(0, 1.5, 0))), "plank", 6, 5.0)
				else:
					for lv in 2:
						for k in 4:
							var p := c + t * (-1.26 + k * 0.84 + (0.42 if lv == 1 else 0.0)) + Vector3(0, 0.3 + lv * 0.6, 0)
							if lv == 1 and k == 3:
								continue
							_breakable(_body("carton", "carton", 4.0, Transform3D(b.rotated(Vector3.UP, PI * 0.5), p)), "flap", 4, 3.0)
			_:
				# tyre stack + cones
				tyre_stack(c, 4)
				for k in 3:
					var p := c + t * (1.2 + k * 0.9) + Vector3(0, 0.37, 0)
					_body("cone", "cone", 3.0, Transform3D(Basis.IDENTITY, p), Vector3(0, -0.35, 0))


# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------
func _vc_material(rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	return m


func _make_assets() -> void:
	# oil drums in three paints
	for col in [Color(0.75, 0.1, 0.08), Color(0.1, 0.3, 0.7), Color(0.9, 0.7, 0.1)]:
		var st := MeshKit.new_st()
		Props._cyl(st, Vector3(0, -0.44, 0), Vector3(0, 0.44, 0), 0.29, 0.29, col, 14)
		for y in [-0.2, 0.2]:
			Props._cyl(st, Vector3(0, y - 0.02, 0), Vector3(0, y + 0.02, 0), 0.3, 0.3, col.darkened(0.3), 14)
		_meshes["barrel_%d" % (_meshes.size())] = MeshKit.commit(st, _vc_material(0.45, 0.4))
	var cone := MeshKit.new_st()
	Props._traffic_cone(cone)
	_meshes["cone"] = MeshKit.commit(cone, _vc_material(0.6))
	var tyres := MeshKit.new_st()
	Props._tyre_stack(tyres)
	_meshes["tyres"] = MeshKit.commit(tyres, _vc_material(0.9))
	# single tyres (stacks are built from these, every tyre has its own physics)
	for k in 2:
		var one := MeshKit.new_st()
		Props._vlathe(one, [Vector2(0.18, -0.11), Vector2(0.3, -0.12), Vector2(0.33, 0.0), Vector2(0.3, 0.12), Vector2(0.18, 0.11)], 14,
			Color(0.06, 0.06, 0.065) if k == 0 else Color(0.88, 0.88, 0.86))
		Props._vlathe(one, [Vector2(0.18, 0.11), Vector2(0.17, 0.0), Vector2(0.18, -0.11)], 14, Color(0.03, 0.03, 0.03))
		_meshes["tyre" if k == 0 else "tyre_white"] = MeshKit.commit(one, _vc_material(0.9))
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_texture = Houses._tex("planks")
	crate_mat.albedo_color = Color(0.72, 0.52, 0.3)
	crate_mat.roughness = 0.85
	var crate := BoxMesh.new()
	crate.size = Vector3(1.0, 1.0, 1.0)
	crate.material = crate_mat
	_meshes["crate"] = crate
	var plank := BoxMesh.new()
	plank.size = Vector3(1.0, 0.1, 0.24)
	plank.material = crate_mat
	_meshes["plank"] = plank
	var card_mat := StandardMaterial3D.new()
	card_mat.albedo_color = Color(0.62, 0.46, 0.28)
	card_mat.roughness = 0.95
	var card := BoxMesh.new()
	card.size = Vector3(0.8, 0.6, 0.6)
	card.material = card_mat
	_meshes["carton"] = card
	var flap := BoxMesh.new()
	flap.size = Vector3(0.6, 0.02, 0.4)
	flap.material = card_mat
	_meshes["flap"] = flap
	var wb := BoxMesh.new()
	wb.size = Vector3(1.8, 0.8, 0.5)
	var wb_mat := StandardMaterial3D.new()
	wb_mat.albedo_color = Color(0.85, 0.12, 0.1)
	wb_mat.roughness = 0.5
	wb.material = wb_mat
	_meshes["water_red"] = wb
	var wb2 := BoxMesh.new()
	wb2.size = Vector3(1.8, 0.8, 0.5)
	var wb2_mat := StandardMaterial3D.new()
	wb2_mat.albedo_color = Color(0.95, 0.95, 0.93)
	wb2_mat.roughness = 0.5
	wb2.material = wb2_mat
	_meshes["water_white"] = wb2
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.29
	cyl.height = 0.88
	_shapes["barrel"] = cyl
	var cone_s := CylinderShape3D.new()
	cone_s.radius = 0.16
	cone_s.height = 0.7
	_shapes["cone"] = cone_s
	var ty := CylinderShape3D.new()
	ty.radius = 0.33
	ty.height = 0.96
	_shapes["tyres"] = ty
	var ty1 := CylinderShape3D.new()
	ty1.radius = 0.33
	ty1.height = 0.24
	_shapes["tyre"] = ty1
	for k in ["crate", "plank", "carton", "flap", "water_red"]:
		var bs := BoxShape3D.new()
		bs.size = (_meshes[k] as BoxMesh).size
		_shapes[k] = bs


func _body(mesh_key: String, shape_key: String, mass: float, xf: Transform3D, mesh_offset := Vector3.ZERO) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.collision_layer = PROP_LAYER
	b.collision_mask = PROP_MASK
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.12
	b.physics_material_override = pm
	b.can_sleep = true
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[mesh_key]
	mi.position = mesh_offset
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _shapes[shape_key]
	b.add_child(cs)
	add_child(b)
	b.global_transform = xf
	b.sleeping = true
	_stats[shape_key] = int(_stats.get(shape_key, 0)) + 1
	return b


func _ground(x: float, z: float) -> float:
	return terrain.height_at(x, z)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
## Open asphalt away from the racing line and the start grid, on a 6 m grid.
func _open_spots() -> Array:
	var r: Rect2 = terrain.pad_rect()
	var out: Array = []
	var gz := r.position.y + 10.0
	while gz < r.end.y - 10.0:
		var gx := r.position.x + 10.0
		while gx < r.end.x - 10.0:
			var p := Vector3(gx, 0, gz)
			# clusters (slaloms, box walls) reach a few metres: keep them clear of the grass belt too
			if terrain.pad_sd(p.x, p.z) < -8.0 and track.distance_to_center(p) > float(track.half_w) + terrain.BELT_GAP + terrain.BELT_WIDTH + 3.0 \
					and not _pit.grow(4.0).has_point(Vector2(p.x, p.z)) and terrain.pad_grass(p.x, p.z) < 0.01:
				p.y = _ground(p.x, p.z)
				out.append(p)
			gx += 6.0
		gz += 6.0
	out.shuffle()
	return out


## Takes a spot whose surroundings (radius r) are clear of the track and of what was placed already.
func _take(spots: Array, r: float) -> Vector3:
	for i in spots.size():
		var p: Vector3 = spots[i]
		if track.distance_to_center(p) < float(track.half_w) + 3.0 + r:
			continue
		if terrain.pad_sd(p.x, p.z) > -4.0 - r:
			continue
		if not scenery.free_at(p, r, 0.0) or _pit.grow(r + 2.0).has_point(Vector2(p.x, p.z)):
			continue
		spots.remove_at(i)
		scenery.occupy(p, r)
		return p
	return Vector3.INF


func _donut_circles(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 13.0)
		if c == Vector3.INF:
			return
		for k in 16:
			var a := TAU * k / 16.0
			var p := c + Vector3(cos(a), 0, sin(a)) * 11.0
			if terrain.pad_grass(p.x, p.z) > 0.01:
				continue
			p.y = _ground(p.x, p.z) + 0.02
			_body("cone", "cone", 3.0, Transform3D(Basis.IDENTITY, p), Vector3(0, -0.35, 0)).position.y += 0.35
		# a barrel in the middle to circle around
		_body("barrel_0", "barrel", 20.0, Transform3D(Basis.IDENTITY, c + Vector3(0, 0.45, 0)))


func _slaloms(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 26.0)
		if c == Vector3.INF:
			return
		var dir := Vector3(cos(rng.randf() * TAU), 0, 0)
		dir = Vector3(1, 0, 0) if rng.randf() < 0.5 else Vector3(0, 0, 1)
		for k in 9:
			var p := c + dir * (-48.0 + k * 12.0)
			if terrain.pad_sd(p.x, p.z) > -4.0 or track.distance_to_center(p) < float(track.half_w) + 2.0 or terrain.pad_grass(p.x, p.z) > 0.01:
				continue
			p.y = _ground(p.x, p.z) + 0.37
			_body("cone", "cone", 3.0, Transform3D(Basis.IDENTITY, p), Vector3(0, -0.35, 0))


func _barrel_clusters(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 3.5)
		if c == Vector3.INF:
			return
		var num := rng.randi_range(3, 7)
		var key := "barrel_%d" % rng.randi_range(0, 2)
		# tight cluster on fixed spots (no overlaps), one or two more standing on top of the others
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		var spots_l := [Vector3(0, 0, 0), Vector3(0.62, 0, 0), Vector3(-0.62, 0, 0), Vector3(0.31, 0, 0.54), Vector3(-0.31, 0, 0.54)]
		var placed: Array = []
		for k in num:
			var p: Vector3
			if k < 5:
				p = c + b * spots_l[k] + Vector3(0, 0.45, 0)
				placed.append(p)
			else:
				p = placed[k - 5] + Vector3(0, 0.9, 0)
			_body(key, "barrel", 20.0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))


func _crate_stacks(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 3.0)
		if c == Vector3.INF:
			return
		var yaw := rng.randf() * TAU
		var b := Basis(Vector3.UP, yaw)
		# pyramid: 3 + 2 + 1
		var rows := [[-1.02, 0.0, 1.02], [-0.51, 0.51], [0.0]]
		for lv in rows.size():
			for x in rows[lv]:
				var p: Vector3 = c + b * Vector3(float(x), 0.505 + lv * 1.01, 0)
				_breakable(_body("crate", "crate", 25.0, Transform3D(b, p)), "plank", 6, 5.0)


func _box_walls(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 4.0)
		if c == Vector3.INF:
			return
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		for lv in 3:
			var cnt := 5 - lv    # every box rests on two below it
			for k in cnt:
				var p: Vector3 = c + b * Vector3((k - (cnt - 1) * 0.5) * 0.84, 0.305 + lv * 0.605, 0)
				_breakable(_body("carton", "carton", 4.0, Transform3D(b, p)), "flap", 4, 3.0)


func _tyre_stacks(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 2.2)
		if c == Vector3.INF:
			return
		# single stacks, pairs and small walls of stacks
		var kind := rng.randi() % 3
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		var cols := 1 if kind == 0 else (2 if kind == 1 else 3)
		for k in cols:
			tyre_stack(c + b * Vector3((k - (cols - 1) * 0.5) * 0.68, 0, 0), rng.randi_range(3, 5))


## A stack of `levels` loose tyres (each its own rigid body) standing on the ground at `c`.
func tyre_stack(c: Vector3, levels: int) -> void:
	var g := _ground(c.x, c.z)
	for k in levels:
		var key := "tyre_white" if (k == levels - 2 and rng.randf() < 0.5) else "tyre"
		var p := Vector3(c.x + rng.randf_range(-0.03, 0.03), g + 0.125 + k * 0.245, c.z + rng.randf_range(-0.03, 0.03))
		_body(key, "tyre", 9.0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))


## Red/white water-filled barriers as chicanes at the edge of the start straight.
func _water_barriers() -> void:
	var s0: int = track.start_index
	var n: int = track.sample_count()
	for side in [-1.0, 1.0]:
		for k in 10:
			var i: int = (s0 + 30 + k + n) % n
			# on the strip of asphalt between the road and the grass belt
			var p: Vector3 = track.samples[i] + track.rights[i] * side * (float(track.half_w) + terrain.BELT_GAP * 0.45)
			p.y = _ground(p.x, p.z) + 0.4
			var b := Basis.looking_at(track.tangents[i], Vector3.UP).rotated(Vector3.UP, PI * 0.5)
			_body("water_red" if k % 2 == 0 else "water_white", "water_red", 60.0, Transform3D(b, p))


# ---------------------------------------------------------------------------
# Grass islands, pit lane, houses
# ---------------------------------------------------------------------------
## Red/white kerb rings around the grass islands and tyre stacks on the corner islands' edges.
func _islands() -> void:
	var st := MeshKit.new_st()
	for isl in terrain.islands:
		var c: Vector2 = isl[0]
		var r: float = isl[1]
		var segs := maxi(24, int(TAU * r / 1.6))
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var col := Color(0.85, 0.1, 0.08) if k % 2 == 0 else Color(0.93, 0.93, 0.9)
			var p0 := Vector2(cos(a0), sin(a0))
			var p1 := Vector2(cos(a1), sin(a1))
			var y := 0.045
			var ia := c + p0 * (r + 0.2)
			var ib := c + p1 * (r + 0.2)
			var oa := c + p0 * (r + 1.2)
			var ob := c + p1 * (r + 1.2)
			MeshKit.quad(st, Vector3(ia.x, _ground(ia.x, ia.y) + y, ia.y), Vector3(oa.x, _ground(oa.x, oa.y) + y, oa.y),
				Vector3(ob.x, _ground(ob.x, ob.y) + y, ob.y), Vector3(ib.x, _ground(ib.x, ib.y) + y, ib.y), Vector3.UP,
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
		# corner islands (small ones) get a ring of tyre stacks to bump into
		if r < 20.0:
			var n := int(TAU * r / 5.0)
			for k in n:
				var a := TAU * (k + 0.5) / n
				var p := c + Vector2(cos(a), sin(a)) * (r + 2.2)
				tyre_stack(Vector3(p.x, 0, p.y), 3 + (k % 2))
	var mat := _vc_material(0.6)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, mat), null, false)
	mi.name = "IslandKerbs"
	add_child(mi)


## Pit lane along the north edge of the pad: garages with six boxes, painted lane and box markings,
## a pit wall with gaps at both ends, tyres and tools in front of the garages.
func _pit_lane() -> void:
	var pr: Rect2 = terrain.pad_rect()
	var cx := pr.get_center().x
	var top := pr.position.y
	var x0 := cx - PIT_LEN * 0.5
	var lane_z0 := top + 14.0
	var lane_z1 := top + 24.0
	_pit = Rect2(x0 - 4.0, top, PIT_LEN + 8.0, lane_z1 - top + 3.0)
	var g := _ground(cx, top + 15.0)
	# --- garages ---
	var bays := 6
	var bay_w := 11.0
	var gw := bays * bay_w
	var gx0 := cx - gw * 0.5
	var depth := 9.0
	var gz0 := top + 3.5
	var gz1 := gz0 + depth
	var h := 5.2
	var building := Node3D.new()
	building.name = "PitGarages"
	add_child(building)
	var wall_mat := TexKit.std(Color(0.78, 0.78, 0.8), 0.8)
	var dark := TexKit.std(Color(0.05, 0.05, 0.06), 0.9)
	var roof_mat := TexKit.std(Color(0.2, 0.2, 0.24), 0.6, 0.3)
	var accent := TexKit.std(Color(0.55, 0.2, 0.9), 0.5)
	building.add_child(MeshKit.box_node(Vector3(gw, h, 0.4), wall_mat, Vector3(cx, g + h * 0.5, gz0 + 0.2)))       # back wall
	building.add_child(MeshKit.box_node(Vector3(gw + 0.6, 0.4, depth + 1.2), roof_mat, Vector3(cx, g + h + 0.2, (gz0 + gz1) * 0.5 + 0.4)))
	building.add_child(MeshKit.box_node(Vector3(gw + 0.6, 1.0, 0.3), accent, Vector3(cx, g + h - 0.3, gz1 + 0.6)))  # fascia
	for k in bays + 1:
		var x := gx0 + k * bay_w
		building.add_child(MeshKit.box_node(Vector3(0.5, h, depth), wall_mat, Vector3(x, g + h * 0.5, (gz0 + gz1) * 0.5)))
	for k in bays:
		var x := gx0 + (k + 0.5) * bay_w
		building.add_child(MeshKit.box_node(Vector3(bay_w - 0.5, 0.05, depth - 0.4), dark, Vector3(x, g + 0.03, (gz0 + gz1) * 0.5)))
		building.add_child(MeshKit.box_node(Vector3(bay_w - 0.6, 0.8, 0.2), wall_mat, Vector3(x, g + h - 1.2, gz1 + 0.05)))  # door lintel
		# a workbench and a tool chest at the back of each box
		building.add_child(MeshKit.box_node(Vector3(3.0, 0.9, 0.8), TexKit.std(Color(0.35, 0.35, 0.38), 0.6, 0.5), Vector3(x - 2.5, g + 0.45, gz0 + 1.0)))
		building.add_child(MeshKit.box_node(Vector3(0.8, 1.1, 0.6), TexKit.std(Color(0.8, 0.1, 0.08), 0.4, 0.4), Vector3(x + 3.2, g + 0.55, gz0 + 0.9)))
	Colliders.add_trimesh(building)
	# --- painted lane lines and box markings ---
	var st := MeshKit.new_st()
	var y := g + 0.04
	for z in [lane_z0, lane_z1]:
		var x := x0
		while x < x0 + PIT_LEN:
			var l := 3.0 if z == lane_z1 else PIT_LEN
			MeshKit.quad(st, Vector3(x, y, z - 0.1), Vector3(x + l, y, z - 0.1), Vector3(x + l, y, z + 0.1), Vector3(x, y, z + 0.1),
				Vector3.UP, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color(0.92, 0.92, 0.9))
			x += l + (3.0 if z == lane_z1 else 0.0)
	for k in bays:
		var bx := gx0 + (k + 0.5) * bay_w
		for side: float in [-1.0, 1.0]:
			var lx := bx + side * 3.0
			MeshKit.quad(st, Vector3(lx - 0.1, y, gz1 + 0.3), Vector3(lx + 0.1, y, gz1 + 0.3), Vector3(lx + 0.1, y, lane_z0 - 0.3), Vector3(lx - 0.1, y, lane_z0 - 0.3),
				Vector3.UP, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color(0.95, 0.75, 0.1))
		MeshKit.quad(st, Vector3(bx - 3.0, y, lane_z0 - 0.5), Vector3(bx + 3.0, y, lane_z0 - 0.5), Vector3(bx + 3.0, y, lane_z0 - 0.3), Vector3(bx - 3.0, y, lane_z0 - 0.3),
			Vector3.UP, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color(0.95, 0.75, 0.1))
	var lines := MeshKit.mesh_instance(MeshKit.commit(st, _vc_material(0.6)), null, false)
	lines.name = "PitMarkings"
	add_child(lines)
	# --- pit wall (concrete, gaps at both ends for entry and exit) ---
	var wall_z := lane_z1 + 1.2
	var wall_len := PIT_LEN - 24.0
	var wall := MeshKit.box_node(Vector3(wall_len, 1.0, 0.6), TexKit.std(Color(0.72, 0.72, 0.7), 0.85), Vector3(cx, g + 0.5, wall_z))
	add_child(wall)
	Colliders.add_trimesh(wall)
	var fence := MeshKit.box_node(Vector3(wall_len, 0.06, 0.06), TexKit.std(Color(0.3, 0.3, 0.32), 0.5, 0.7), Vector3(cx, g + 2.4, wall_z))
	add_child(fence)
	for k in int(wall_len / 4.0) + 1:
		add_child(MeshKit.box_node(Vector3(0.08, 1.4, 0.08), TexKit.std(Color(0.3, 0.3, 0.32), 0.5, 0.7), Vector3(cx - wall_len * 0.5 + k * 4.0, g + 1.7, wall_z)))
	# --- tyres, barrels and cones around the boxes ---
	for k in bays:
		var bx := gx0 + (k + 0.5) * bay_w
		tyre_stack(Vector3(bx + 4.4, 0, gz1 + 1.2), 4)
		tyre_stack(Vector3(bx + 4.4, 0, gz1 + 1.9), 3)
		if k % 2 == 0:
			_body("barrel_%d" % (k % 3), "barrel", 20.0, Transform3D(Basis.IDENTITY, Vector3(bx - 4.5, g + 0.45, gz1 + 1.0)))
	for side: float in [-1.0, 1.0]:
		for k in 5:
			var p := Vector3(cx + side * (wall_len * 0.5 + 2.0 + k * 1.6), g + 0.37, wall_z - 0.6)
			_body("cone", "cone", 3.0, Transform3D(Basis.IDENTITY, p), Vector3(0, -0.35, 0))


## Small houses outside the barrier, facing the pad.
func _houses() -> void:
	var pr: Rect2 = terrain.pad_rect()
	var c := pr.get_center()
	var spots: Array = []
	for x in [-0.36, -0.12, 0.12, 0.36]:
		spots.append(Vector2(c.x + x * pr.size.x, pr.end.y + 20.0))
	for z in [-0.2, 0.2]:
		spots.append(Vector2(pr.position.x - 20.0, c.y + z * pr.size.y))
		spots.append(Vector2(pr.end.x + 20.0, c.y + z * pr.size.y))
	for x in [-0.4, 0.4]:
		spots.append(Vector2(c.x + x * pr.size.x, pr.position.y - 20.0))
	var builder := Houses.new()
	builder.rng = rng
	builder.details = scenery.details
	var styles := ["jp", "barn", "jp", "shop", "jp", "jp", "barn", "jp", "jp", "shop"]
	var i := 0
	for sp in spots:
		var pos := Vector3(sp.x, 0, sp.y)
		pos.y = terrain.flatten(pos, 9.0, 8.0)
		var dir := Vector3(c.x - sp.x, 0, c.y - sp.y).normalized()
		var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
		builder.window_mat = scenery._window_material()
		var house := builder.make(styles[i % styles.size()], xf)
		add_child(house)
		house.global_transform = xf
		Colliders.add_trimesh(house)
		# paths straight out towards the pad
		for hp in builder.paths:
			var start: Vector3 = xf * (hp[0] as Vector3)
			scenery.add_path([start, start - xf.basis.z * 9.0], float(hp[1]), str(hp[2]))
		scenery.occupy(pos, 11.0)
		i += 1
	_stats["houses"] = i


# ---------------------------------------------------------------------------
# Breakables
# ---------------------------------------------------------------------------
func _breakable(b: RigidBody3D, piece: String, pieces: int, threshold: float) -> void:
	b.contact_monitor = true
	b.max_contacts_reported = 2
	b.body_entered.connect(_on_hit.bind(b, piece, pieces, threshold))


func _on_hit(other: Node, b: RigidBody3D, piece: String, pieces: int, threshold: float) -> void:
	if not is_instance_valid(b) or b.is_queued_for_deletion():
		return
	if not (other is RigidBody3D):
		return
	var rel := ((other as RigidBody3D).linear_velocity - b.linear_velocity).length()
	# cars smash them; other props only when flying fast
	var car_hit: bool = other.has_method("visual_transform")
	if rel < (threshold if car_hit else threshold * 2.5):
		return
	call_deferred("_smash", b, piece, pieces, (other as RigidBody3D).linear_velocity)


func _smash(b: RigidBody3D, piece: String, pieces: int, hit_vel: Vector3) -> void:
	if not is_instance_valid(b):
		return
	var xf := b.global_transform
	var v0 := b.linear_velocity
	b.queue_free()
	for k in pieces:
		var off := Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
		var p := _body(piece, piece, 2.0 if piece == "plank" else 0.3,
			Transform3D(xf.basis * Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)), xf * off))
		p.sleeping = false
		p.linear_velocity = v0 + hit_vel * rng.randf_range(0.3, 0.7) + Vector3(rng.randf_range(-2, 2), rng.randf_range(1.5, 4.0), rng.randf_range(-2, 2))
		p.angular_velocity = Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
		_debris.append(p)
	# keep the pile of splinters bounded
	while _debris.size() > MAX_DEBRIS:
		var old = _debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# ---------------------------------------------------------------------------
# Perimeter barrier with sponsor boards
# ---------------------------------------------------------------------------
func _perimeter() -> void:
	var r: Rect2 = terrain.pad_rect().grow(-1.5)
	var rad: float = terrain.PAD_CORNER - 1.5
	var c := r.get_center()
	var h := r.size * 0.5 - Vector2(rad, rad)
	var pts: Array = []
	var corners := [[Vector2(h.x, h.y), 0.0], [Vector2(-h.x, h.y), PI * 0.5], [Vector2(-h.x, -h.y), PI], [Vector2(h.x, -h.y), PI * 1.5]]
	for cr in corners:
		var cc: Vector2 = c + (cr[0] as Vector2)
		for k in 13:
			var a: float = float(cr[1]) + PI * 0.5 * k / 12.0
			pts.append(cc + Vector2(cos(a), sin(a)) * rad)
	# resample the loop every ~3 m
	var loop: Array = []
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var segs := maxi(1, int(ceil(a.distance_to(b) / 3.0)))
		for k in segs:
			loop.append(a.lerp(b, float(k) / segs))
	var st := MeshKit.new_st()
	var faces := PackedVector3Array()
	var hgt := 1.15
	var n := loop.size()
	for i in n:
		var a2: Vector2 = loop[i]
		var b2: Vector2 = loop[(i + 1) % n]
		var a := Vector3(a2.x, _ground(a2.x, a2.y), a2.y)
		var b := Vector3(b2.x, _ground(b2.x, b2.y), b2.y)
		var inward := Vector3(c.x - (a.x + b.x) * 0.5, 0, c.y - (a.z + b.z) * 0.5).normalized()
		var edge := (b - a).normalized()
		var nrm := edge.cross(Vector3.UP).normalized()
		if nrm.dot(inward) < 0.0:
			nrm = -nrm
		var col := Color(0.85, 0.12, 0.1) if (i / 2) % 2 == 0 else Color(0.92, 0.92, 0.9)
		var out := -nrm * 0.5
		var up := Vector3(0, hgt, 0)
		MeshKit.quad(st, a, b, b + up, a + up, nrm, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, col)
		MeshKit.quad(st, a + up, b + up, b + up + out, a + up + out, Vector3.UP, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color(0.7, 0.7, 0.68))
		MeshKit.quad(st, a + out, b + out, b + out + up, a + out + up, -nrm, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color(0.6, 0.6, 0.58))
		var hc := Vector3(0, hgt + 0.6, 0)
		faces.append_array(PackedVector3Array([a, b, b + hc, a, b + hc, a + hc]))
		# sponsor boards on top every ~36 m
		if i % 12 == 0 and scenery.details:
			var mid := (a + b) * 0.5 + Vector3(0, hgt + 0.8, 0) + out * 0.5
			var bx := Vector3.UP.cross(nrm).normalized()
			var kinds := ["drift_zone", "kurohana_motors", "takumi_tires", "nitro_x", "series", "safety"]
			scenery.details.add("bill", Transform3D(Basis(bx * 7.0, Vector3.UP * 0.875, nrm), mid),
				SignAtlas.cell("banner", kinds[(i / 12) % kinds.size()]))
	var mat := _vc_material(0.85)
	mat.albedo_texture = TexKit.noise_texture(51, 0.08, false, 256)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, mat))
	mi.name = "Barrier"
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wall")
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
